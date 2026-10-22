import Foundation
import Testing
@testable import NotchCore

@Suite("Inbox sync")
struct InboxSyncTests {
    let now = Date(timeIntervalSince1970: 2_000_000)

    private func mail(_ id: String, minutesAgo: Double = 0) -> MailMessage {
        let m = Fixtures.message(id)
        return MailMessage(
            id: m.id, account: m.account, senderName: m.senderName, senderAddress: m.senderAddress,
            subject: m.subject, body: m.body, receivedAt: now.addingTimeInterval(-minutesAgo * 60)
        )
    }

    @Test func firstCheckLoadsQuietlyWithoutAlerts() {
        let (_, changes) = InboxSync.empty.ingest([mail("a"), mail("b")], now: now)

        #expect(Set(changes.loaded.map(\.id)) == ["a", "b"])
        #expect(changes.arrived.isEmpty)
    }

    @Test func laterNewMailAlerts() {
        let (primed, _) = InboxSync.empty.ingest([mail("a")], now: now)

        let (_, changes) = primed.ingest([mail("b"), mail("a")], now: now)

        #expect(changes.arrived.map(\.id) == ["b"])
        #expect(changes.loaded.isEmpty)
    }

    @Test func severalNewAtOnceOnlyAlertTheNewest() {
        let (primed, _) = InboxSync.empty.ingest([], now: now)

        let (_, changes) = primed.ingest([mail("old", minutesAgo: 30), mail("new", minutesAgo: 1), mail("mid", minutesAgo: 10)], now: now)

        #expect(changes.arrived.map(\.id) == ["new"])
        #expect(Set(changes.loaded.map(\.id)) == ["old", "mid"])
    }

    @Test func mailNoLongerListedIsOnlyReportedAsMissing() {
        let (primed, _) = InboxSync.empty.ingest([mail("a"), mail("b")], now: now)

        // Might be read elsewhere, or just outside the "recent, max 25" window.
        let (unconfirmed, changes) = primed.ingest([mail("a")], now: now)
        #expect(changes.missing == ["b"])
        #expect(unconfirmed.known.contains("b"))

        // Asked again next time until the caller confirms it's gone.
        let (_, again) = unconfirmed.ingest([mail("a")], now: now)
        #expect(again.missing == ["b"])
    }

    @Test func confirmedRemovalsAreForgotten() {
        let (primed, _) = InboxSync.empty.ingest([mail("a"), mail("b")], now: now)
        let (missing, _) = primed.ingest([mail("a")], now: now)

        let (_, changes) = missing.confirmingRemoved(["b"]).ingest([mail("a")], now: now)

        #expect(changes.missing.isEmpty)
    }

    @Test func handledMailIsNotResurrectedBeforeTheServerCatchesUp() {
        let (primed, _) = InboxSync.empty.ingest([mail("a")], now: now)
        let handled = primed.handling("a")

        // The server still lists it on the next check (the archive is in flight).
        let (afterRace, raceChanges) = handled.ingest([mail("a")], now: now)
        #expect(raceChanges.arrived.isEmpty && raceChanges.loaded.isEmpty)
        #expect(raceChanges.missing.isEmpty)

        // Once the server agrees, it's forgotten for good.
        let (settled, _) = afterRace.ingest([], now: now)
        #expect(settled.handled.isEmpty)
    }

    @Test func failedActionBringsTheMessageBackAsKnown() {
        let (primed, _) = InboxSync.empty.ingest([mail("a")], now: now)

        let restored = primed.handling("a").unhandling("a")
        let (_, changes) = restored.ingest([mail("a")], now: now)

        #expect(changes.arrived.isEmpty && changes.loaded.isEmpty && changes.missing.isEmpty)
    }

    @Test func snoozedMailStaysHiddenUntilDue() {
        let (primed, _) = InboxSync.empty.ingest([mail("a")], now: now)
        let snoozed = primed.snoozing("a", until: now.addingTimeInterval(3_600))

        let (stillSnoozed, early) = snoozed.ingest([mail("a")], now: now.addingTimeInterval(60))
        #expect(early.arrived.isEmpty && early.loaded.isEmpty && early.due.isEmpty)

        let (afterDue, due) = stillSnoozed.ingest([mail("a")], now: now.addingTimeInterval(3_601))
        #expect(due.due == ["a"])
        #expect(due.arrived.isEmpty && due.loaded.isEmpty)
        // Kept until it has really been shown.
        #expect(afterDue.reminders["a"] != nil)
        #expect(afterDue.announcing("a").reminders.isEmpty)
    }

    @Test func dueReminderIsReportedAgainUntilAnnounced() {
        let (primed, _) = InboxSync.empty.ingest([mail("a")], now: now)
        let (failedToShow, _) = primed.snoozing("a", until: now).ingest([mail("a")], now: now)

        let (_, retry) = failedToShow.ingest([mail("a")], now: now.addingTimeInterval(20))

        #expect(retry.due == ["a"])
    }

    @Test func droppedReminderIsForgotten() {
        let (primed, _) = InboxSync.empty.ingest([mail("a")], now: now)
        let (due, _) = primed.snoozing("a", until: now).ingest([], now: now)

        let (_, changes) = due.droppingReminder("a").ingest([], now: now)

        #expect(changes.due.isEmpty)
    }

    @Test func dueRemindersAreReportedEvenWhenNoLongerListed() {
        let (primed, _) = InboxSync.empty.ingest([mail("a")], now: now)
        let snoozed = primed.snoozing("a", until: now.addingTimeInterval(60))

        // Fell out of the "unread, last few days" window meanwhile.
        let (_, changes) = snoozed.ingest([], now: now.addingTimeInterval(120))

        #expect(changes.due == ["a"])
        #expect(changes.missing.isEmpty)
    }

    @Test func reminderAnnouncedByTheCoordinatorBecomesKnown() {
        let (primed, _) = InboxSync.empty.ingest([mail("a")], now: now)
        let (afterDue, _) = primed.snoozing("a", until: now).ingest([mail("a")], now: now)

        let announced = afterDue.announcing("a")
        let (_, changes) = announced.ingest([mail("a")], now: now)

        #expect(changes.arrived.isEmpty && changes.loaded.isEmpty)
    }

    @Test func remindersSurviveARestart() {
        let reminders = ["a": now.addingTimeInterval(600)]
        let restored = InboxSync.empty.restoringReminders(reminders)

        let (_, changes) = restored.ingest([mail("a"), mail("b")], now: now)

        #expect(changes.loaded.map(\.id) == ["b"])
    }
}
