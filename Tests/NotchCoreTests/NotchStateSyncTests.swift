import Foundation
import Testing
@testable import NotchCore

/// Events that come from a real mailbox: quiet loads, removals, snoozes, failures.
@Suite("Notch state with a real mailbox")
struct NotchStateSyncTests {
    private func mail(_ id: String, at seconds: TimeInterval) -> MailMessage {
        let m = Fixtures.message(id)
        return MailMessage(
            id: m.id, account: m.account, senderName: m.senderName, senderAddress: m.senderAddress,
            subject: m.subject, body: m.body, receivedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test func loadedMailJoinsQuietlySortedNewestFirst() {
        let state = NotchState.initial.applying(.mailLoaded([mail("old", at: 10), mail("new", at: 30), mail("mid", at: 20)]))

        #expect(state.mode == .closed)
        #expect(state.unread.map(\.id) == ["new", "mid", "old"])
    }

    @Test func arrivingMailIsSortedByTimeNotArrivalOrder() {
        let state = NotchState.initial
            .applying(.mailLoaded([mail("new", at: 30)]))
            .applying(.mailArrived(mail("older", at: 20)))

        #expect(state.unread.map(\.id) == ["new", "older"])
        #expect(state.mode == .alert("older"))
    }

    @Test func removingTheAlertedMessageClosesTheNotch() {
        let state = NotchState.initial
            .applying(.mailArrived(mail("a", at: 10)))
            .applying(.mailRemoved(["a"]))

        #expect(state.mode == .closed)
        #expect(state.unread.isEmpty)
    }

    @Test func removingTheOpenMessageFallsBackToTheList() {
        let state = NotchState.initial
            .applying(.mailLoaded([mail("a", at: 10), mail("b", at: 20)]))
            .applying(.hoverChanged(true))
            .applying(.selected("b"))
            .applying(.mailRemoved(["b"]))

        #expect(state.mode == .list)
        #expect(state.unread.map(\.id) == ["a"])
    }

    @Test func removingOtherMessagesLeavesTheViewAlone() {
        let state = NotchState.initial
            .applying(.mailLoaded([mail("a", at: 10), mail("b", at: 20)]))
            .applying(.hoverChanged(true))
            .applying(.selected("b"))
            .applying(.mailRemoved(["a"]))

        #expect(state.mode == .expanded("b", from: .list))
    }

    @Test func snoozingFromTheListReturnsToTheListWithItsLabel() {
        let state = NotchState.initial
            .applying(.mailLoaded([mail("a", at: 10), mail("b", at: 20)]))
            .applying(.hoverChanged(true))
            .applying(.selected("b"))
            .applying(.snoozed("b", confirmation: "Back at 18:00"))

        #expect(state.mode == .list)
        #expect(state.notice == "Back at 18:00")
        #expect(state.unread.map(\.id) == ["a"])
    }

    @Test func snoozingAPoppedUpMessageConfirms() {
        let state = NotchState.initial
            .applying(.mailArrived(mail("a", at: 10)))
            .applying(.hoverChanged(true))
            .applying(.snoozed("a", confirmation: "Back tomorrow 08:00"))

        #expect(state.mode == .confirmation("Back tomorrow 08:00"))
    }

    @Test func failedActionPutsTheMessageBackAndSaysSo() {
        let a = mail("a", at: 10)
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.hoverChanged(true))
            .applying(.performed(.archive, "a"))
            .applying(.hoverChanged(false))
            .applying(.confirmationEnded)
            .applying(.actionFailed(a, "Couldn't archive"))

        #expect(state.unread.map(\.id) == ["a"])
        #expect(state.mode == .confirmation("Couldn't archive"))
    }

    @Test(arguments: [false, true])
    func notifyShowsAShortMessage(browsing: Bool) {
        let start = browsing
            ? NotchState.initial.applying(.mailLoaded([mail("a", at: 10)])).applying(.hoverChanged(true))
            : NotchState.initial

        let state = start.applying(.notify("Gmail connected"))

        if browsing {
            #expect(state.mode == .list)
            #expect(state.notice == "Gmail connected")
        } else {
            #expect(state.mode == .confirmation("Gmail connected"))
        }
    }

    @Test func failedActionWhileBrowsingTheListShowsANotice() {
        let a = mail("a", at: 10)
        let state = NotchState.initial
            .applying(.mailLoaded([a, mail("b", at: 20)]))
            .applying(.hoverChanged(true))
            .applying(.selected("a"))
            .applying(.performed(.delete, "a"))
            .applying(.actionFailed(a, "Couldn't delete"))

        #expect(state.mode == .list)
        #expect(state.notice == "Couldn't delete")
        #expect(state.unread.map(\.id) == ["b", "a"])
    }
}
