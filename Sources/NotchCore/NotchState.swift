/// What the notch is currently showing.
public enum NotchMode: Equatable, Sendable {
    /// How an open message was reached; decides where an action leads.
    public enum Origin: Equatable, Sendable {
        /// Hovered while it popped up: acting on it closes the notch.
        case alert
        /// Picked from the list: acting on it returns to the list.
        case list
    }

    /// Looks like the hardware notch; nothing visible.
    case closed
    /// A new message peeking out below the notch.
    case alert(MailMessage.ID)
    /// Recent unread mail (or "inbox zero") while the pointer rests on the notch.
    case list
    /// One message open, with its actions.
    case expanded(MailMessage.ID, from: Origin)
    /// Short feedback after an action, e.g. "Archived", before closing.
    case confirmation(String)
    /// Writing a reply. Holds the message, so the reply survives it being read elsewhere.
    /// Stays open when the pointer leaves: you're typing.
    case replying(MailMessage, from: Origin)
    /// "Send" was pressed: a few seconds to undo before it goes out.
    case sending(MailMessage, from: Origin)
}

/// Everything that can happen to the notch. Timers and the mouse turn into events.
public enum NotchEvent: Sendable {
    /// New mail that should pop up.
    case mailArrived(MailMessage)
    /// Mail that joins the list without popping up (first check, older ones of a batch).
    case mailLoaded([MailMessage])
    /// Gone from the server (read or archived elsewhere).
    case mailRemoved(Set<MailMessage.ID>)
    case hoverChanged(Bool)
    case alertTimedOut
    case selected(MailMessage.ID)
    case performed(MailAction, MailMessage.ID)
    /// "Remind me": hidden like an action, with its own confirmation ("Back at 18:00").
    case snoozed(MailMessage.ID, confirmation: String)
    /// The server refused an action: the message comes back.
    case actionFailed(MailMessage, String)
    /// A short status message, e.g. "Gmail connected".
    case notify(String)
    case confirmationEnded
    case noticeEnded
    case backToList
    /// Reply pressed in the open message.
    case replyOpened(MailMessage.ID)
    case replyCancelled
    /// Send pressed; the undo countdown runs.
    case replySending
    case replyUndone
    case replySent
    /// Sending failed: back to the reply (it shows the error itself).
    case replyFailed
}

/// The notch's whole state. Values only: `applying(_:)` returns a new state.
public struct NotchState: Equatable, Sendable {
    /// Unread messages across all accounts, newest first.
    public let unread: [MailMessage]
    public let mode: NotchMode
    public let isHovering: Bool
    /// Small "Archived" beside the notch while the list stays open after an action.
    public let notice: String?

    public static let initial = NotchState(unread: [], mode: .closed, isHovering: false)

    public init(unread: [MailMessage], mode: NotchMode, isHovering: Bool, notice: String? = nil) {
        self.unread = unread
        self.mode = mode
        self.isHovering = isHovering
        self.notice = notice
    }

    public func message(_ id: MailMessage.ID) -> MailMessage? {
        unread.first { $0.id == id }
    }

    /// Writing or about to send a reply: the notch needs the keyboard and stays open.
    public var isReplying: Bool {
        switch mode {
        case .replying, .sending: true
        default: false
        }
    }

    public func applying(_ event: NotchEvent) -> NotchState {
        switch event {
        case .mailArrived(let message):
            return arriving(message)
        case .mailLoaded(let messages):
            let new = messages.filter { message($0.id) == nil }
            return NotchState(unread: Self.sorted(unread + new), mode: mode, isHovering: isHovering, notice: notice)
        case .mailRemoved(let ids):
            return removing(ids)
        case .hoverChanged(let hovering):
            return hovering ? enteringHover() : leavingHover()
        case .alertTimedOut:
            guard case .alert = mode, !isHovering else { return self }
            return with(mode: .closed)
        case .selected(let id):
            guard message(id) != nil, !isReplying else { return self }
            return with(mode: .expanded(id, from: .list))
        case .performed(let action, let id):
            return performing(action.confirmation, on: id)
        case .snoozed(let id, let confirmation):
            return performing(confirmation, on: id)
        case .actionFailed(let message, let text):
            return failing(message, text)
        case .notify(let text):
            return notifying(text)
        case .confirmationEnded:
            guard case .confirmation = mode else { return self }
            // Done with that message: get out of the way, whatever else is waiting.
            return NotchState(unread: unread, mode: .closed, isHovering: false)
        case .noticeEnded:
            return NotchState(unread: unread, mode: mode, isHovering: isHovering)
        case .backToList:
            guard case .expanded = mode else { return self }
            return with(mode: .list)
        case .replyOpened, .replyCancelled, .replySending, .replyUndone, .replySent, .replyFailed:
            return replying(event)
        }
    }

    private func replying(_ event: NotchEvent) -> NotchState {
        switch (event, mode) {
        case (.replyOpened(let id), .expanded(let open, let origin)) where id == open:
            guard let message = message(id) else { return self }
            return with(mode: .replying(message, from: origin))
        case (.replyCancelled, .replying(let message, let origin)):
            if self.message(message.id) != nil { return with(mode: .expanded(message.id, from: origin)) }
            return NotchState(unread: unread, mode: isHovering ? .list : .closed, isHovering: isHovering)
        case (.replySending, .replying(let message, let origin)):
            return with(mode: .sending(message, from: origin))
        case (.replyUndone, .sending(let message, let origin)), (.replyFailed, .sending(let message, let origin)):
            return with(mode: .replying(message, from: origin))
        case (.replySent, .sending(let message, let origin)):
            let remaining = unread.filter { $0.id != message.id }
            if origin == .list, isHovering, !remaining.isEmpty {
                return NotchState(unread: remaining, mode: .list, isHovering: true, notice: "Sent")
            }
            return NotchState(unread: remaining, mode: .confirmation("Sent"), isHovering: isHovering)
        default:
            return self
        }
    }

    private func arriving(_ message: MailMessage) -> NotchState {
        guard self.message(message.id) == nil else { return self }
        let unread = Self.sorted(unread + [message])
        // A notch you're reading in just gains a row; otherwise new mail pops up.
        switch mode {
        case .closed, .alert:
            return NotchState(unread: unread, mode: .alert(message.id), isHovering: isHovering)
        case .confirmation:
            // Start fresh: the pointer is re-checked against the alert, so
            // hovering opens it and otherwise it times out.
            return NotchState(unread: unread, mode: .alert(message.id), isHovering: false)
        case .list, .expanded, .replying, .sending:
            return NotchState(unread: unread, mode: mode, isHovering: isHovering, notice: notice)
        }
    }

    private func performing(_ confirmation: String, on id: MailMessage.ID) -> NotchState {
        guard message(id) != nil else { return self }
        let remaining = unread.filter { $0.id != id }
        if case .expanded(_, from: .list) = mode, !remaining.isEmpty {
            return NotchState(unread: remaining, mode: .list, isHovering: isHovering, notice: confirmation)
        }
        return NotchState(unread: remaining, mode: .confirmation(confirmation), isHovering: isHovering)
    }

    private func removing(_ ids: Set<MailMessage.ID>) -> NotchState {
        let remaining = unread.filter { !ids.contains($0.id) }
        let mode: NotchMode
        switch self.mode {
        case .alert(let id) where ids.contains(id):
            mode = .closed
        case .expanded(let id, _) where ids.contains(id):
            mode = isHovering ? .list : .closed
        default:
            mode = self.mode
        }
        return NotchState(unread: remaining, mode: mode, isHovering: isHovering, notice: notice)
    }

    private func failing(_ message: MailMessage, _ text: String) -> NotchState {
        let unread = self.message(message.id) == nil ? Self.sorted(unread + [message]) : unread
        return NotchState(unread: unread, mode: mode, isHovering: isHovering, notice: notice).notifying(text)
    }

    /// Inline beside the camera while browsing; otherwise a short confirmation.
    private func notifying(_ text: String) -> NotchState {
        switch mode {
        case .list, .expanded, .replying, .sending:
            return NotchState(unread: unread, mode: mode, isHovering: isHovering, notice: text)
        case .closed, .alert, .confirmation:
            return NotchState(unread: unread, mode: .confirmation(text), isHovering: isHovering)
        }
    }

    /// Newest first; on equal times the later-added one goes on top.
    private static func sorted(_ messages: [MailMessage]) -> [MailMessage] {
        messages.enumerated()
            .sorted { ($0.element.receivedAt, $0.offset) > ($1.element.receivedAt, $1.offset) }
            .map(\.element)
    }

    private func enteringHover() -> NotchState {
        guard !isHovering else { return self }
        switch mode {
        case .closed:
            return NotchState(unread: unread, mode: .list, isHovering: true)
        case .alert(let id):
            return NotchState(unread: unread, mode: .expanded(id, from: .alert), isHovering: true)
        case .list, .expanded, .confirmation, .replying, .sending:
            return NotchState(unread: unread, mode: mode, isHovering: true, notice: notice)
        }
    }

    private func leavingHover() -> NotchState {
        guard isHovering else { return self }
        // A confirmation finishes on its own timer, then closes; a reply stays until sent or cancelled.
        if case .confirmation = mode {
            return NotchState(unread: unread, mode: mode, isHovering: false)
        }
        if isReplying {
            return NotchState(unread: unread, mode: mode, isHovering: false, notice: notice)
        }
        return NotchState(unread: unread, mode: .closed, isHovering: false)
    }

    /// Changing what's shown drops any notice.
    private func with(mode: NotchMode) -> NotchState {
        NotchState(unread: unread, mode: mode, isHovering: isHovering)
    }
}
