import Foundation

/// What one mailbox check changed, ready to turn into notch events.
public struct InboxChanges: Equatable, Sendable {
    /// Join the list quietly (first check, or the older ones of a batch).
    public let loaded: [MailMessage]
    /// Pop up as an alert.
    public let arrived: [MailMessage]
    /// Shown in the notch but no longer listed. Could be read elsewhere, or just
    /// outside the "recent, max 25" window: the caller asks the server, then
    /// confirms with `confirmingRemoved(_:)`.
    public let missing: Set<MailMessage.ID>
    /// Reminders that are due. The caller fetches and announces them, then calls
    /// `announcing(_:)`, or `droppingReminder(_:)` if the mail is gone.
    public let due: [MailMessage.ID]

    public static let none = InboxChanges(loaded: [], arrived: [], missing: [], due: [])
}

/// Remembers, per account, what the notch already knows, so repeated checks
/// only report real changes. Values only.
public struct InboxSync: Equatable, Sendable {
    /// Messages the notch is showing.
    public let known: Set<MailMessage.ID>
    /// Acted on here, waiting for the server to stop listing them.
    public let handled: Set<MailMessage.ID>
    /// "Remind me" messages, hidden until their date and kept until shown.
    public let reminders: [MailMessage.ID: Date]
    /// False until the first check, which loads without alerts.
    public let isPrimed: Bool

    public static let empty = InboxSync(known: [], handled: [], reminders: [:], isPrimed: false)

    /// `fetched`: the server's current list of recent unread inbox mail for this account.
    public func ingest(_ fetched: [MailMessage], now: Date) -> (InboxSync, InboxChanges) {
        let fetchedIDs = Set(fetched.map(\.id))
        let due = reminders.filter { $0.value <= now }.keys.sorted()

        // Reminders (due or not) are announced by the caller, not as ordinary new mail.
        let hidden = handled.union(reminders.keys)
        let fresh = fetched
            .filter { !known.contains($0.id) && !hidden.contains($0.id) }
            .sorted { $0.receivedAt > $1.receivedAt }

        // First check: everything quietly. Later: only the newest pops up.
        let arrived = isPrimed ? Array(fresh.prefix(1)) : []
        let loaded = isPrimed ? Array(fresh.dropFirst()) : fresh

        let next = InboxSync(
            known: known.union(fresh.map(\.id)),
            handled: handled.intersection(fetchedIDs),
            reminders: reminders,
            isPrimed: true
        )
        let changes = InboxChanges(loaded: loaded, arrived: arrived, missing: known.subtracting(fetchedIDs), due: due)
        return (next, changes)
    }

    /// The server confirmed these are read, archived or gone.
    public func confirmingRemoved(_ ids: Set<MailMessage.ID>) -> InboxSync {
        InboxSync(known: known.subtracting(ids), handled: handled, reminders: reminders, isPrimed: isPrimed)
    }

    /// After archive / delete / read: hide it, even if the next check still lists it.
    public func handling(_ id: MailMessage.ID) -> InboxSync {
        InboxSync(known: known.subtracting([id]), handled: handled.union([id]), reminders: reminders, isPrimed: isPrimed)
    }

    /// The action failed: the message is back in the notch.
    public func unhandling(_ id: MailMessage.ID) -> InboxSync {
        InboxSync(known: known.union([id]), handled: handled.subtracting([id]), reminders: reminders, isPrimed: isPrimed)
    }

    public func snoozing(_ id: MailMessage.ID, until date: Date) -> InboxSync {
        InboxSync(
            known: known.subtracting([id]), handled: handled,
            reminders: reminders.merging([id: date]) { $1 }, isPrimed: isPrimed
        )
    }

    /// A due reminder was shown again: it's ordinary unread mail from now on.
    public func announcing(_ id: MailMessage.ID) -> InboxSync {
        InboxSync(known: known.union([id]), handled: handled, reminders: reminders.filter { $0.key != id }, isPrimed: isPrimed)
    }

    /// A due reminder whose mail is gone (read, archived, deleted elsewhere).
    public func droppingReminder(_ id: MailMessage.ID) -> InboxSync {
        InboxSync(known: known, handled: handled, reminders: reminders.filter { $0.key != id }, isPrimed: isPrimed)
    }

    /// Reminders saved before the app quit.
    public func restoringReminders(_ saved: [MailMessage.ID: Date]) -> InboxSync {
        InboxSync(known: known, handled: handled, reminders: reminders.merging(saved) { $1 }, isPrimed: isPrimed)
    }
}
