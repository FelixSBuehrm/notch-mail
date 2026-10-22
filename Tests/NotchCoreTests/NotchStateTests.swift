import Testing
@testable import NotchCore

@Suite("Notch state machine")
struct NotchStateTests {
    let a = Fixtures.message("a")
    let b = Fixtures.message("b")

    @Test func newMailWhileClosedShowsAlert() {
        let state = NotchState.initial.applying(.mailArrived(a))

        #expect(state.mode == .alert("a"))
        #expect(state.unread.map(\.id) == ["a"])
    }

    @Test func newerMailGoesOnTop() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.mailArrived(b))

        #expect(state.unread.map(\.id) == ["b", "a"])
        #expect(state.mode == .alert("b"))
    }

    @Test func duplicateMailIsIgnored() {
        let once = NotchState.initial.applying(.mailArrived(a))
        let twice = once.applying(.mailArrived(a))

        #expect(twice == once)
    }

    @Test func newMailDoesNotInterruptAnOpenMessage() {
        let reading = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.hoverChanged(true))

        let state = reading.applying(.mailArrived(b))

        #expect(state.mode == .expanded("a", from: .alert))
        #expect(state.unread.map(\.id) == ["b", "a"])
    }

    @Test func hoveringAnAlertOpensThatMessage() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.hoverChanged(true))

        #expect(state.mode == .expanded("a", from: .alert))
    }

    @Test func hoveringTheClosedNotchShowsTheList() {
        let state = NotchState.initial.applying(.hoverChanged(true))

        #expect(state.mode == .list)
        #expect(state.isHovering)
    }

    @Test func leavingTheNotchClosesIt() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.hoverChanged(true))
            .applying(.hoverChanged(false))

        #expect(state.mode == .closed)
        #expect(state.unread.map(\.id) == ["a"])
    }

    @Test func alertTimesOutWhenNotHovered() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.alertTimedOut)

        #expect(state.mode == .closed)
    }

    @Test func alertTimeoutIsIgnoredOnceTheMessageIsOpen() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.hoverChanged(true))
            .applying(.alertTimedOut)

        #expect(state.mode == .expanded("a", from: .alert))
    }

    @Test func selectingFromTheListOpensTheMessage() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.alertTimedOut)
            .applying(.hoverChanged(true))
            .applying(.selected("a"))

        #expect(state.mode == .expanded("a", from: .list))
    }

    @Test func selectingAnUnknownMessageChangesNothing() {
        let list = NotchState.initial.applying(.hoverChanged(true))

        #expect(list.applying(.selected("missing")) == list)
    }

    @Test(arguments: MailAction.allCases)
    func actionOnAPoppedUpMessageConfirms(action: MailAction) {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.mailArrived(b))
            .applying(.hoverChanged(true))
            .applying(.performed(action, "b"))

        #expect(state.unread.map(\.id) == ["a"])
        #expect(state.mode == .confirmation(action.confirmation))
    }

    @Test func confirmationClosesTheNotchEvenWhileHovering() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.mailArrived(b))
            .applying(.hoverChanged(true))
            .applying(.performed(.archive, "b"))
            .applying(.confirmationEnded)

        #expect(state.mode == .closed)
        #expect(!state.isHovering)
        #expect(state.unread.map(\.id) == ["a"])
    }

    @Test(arguments: MailAction.allCases)
    func actionFromTheListGoesBackToTheListWithANotice(action: MailAction) {
        let state = listOpened(on: "b")
            .applying(.performed(action, "b"))

        #expect(state.mode == .list)
        #expect(state.unread.map(\.id) == ["a"])
        #expect(state.notice == action.confirmation)
    }

    @Test func actionOnTheLastMessageFromTheListConfirmsAndCloses() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.alertTimedOut)
            .applying(.hoverChanged(true))
            .applying(.selected("a"))
            .applying(.performed(.archive, "a"))

        #expect(state.mode == .confirmation(MailAction.archive.confirmation))
        #expect(state.notice == nil)
        #expect(state.applying(.confirmationEnded).mode == .closed)
    }

    @Test func noticeEndsOnItsOwn() {
        let state = listOpened(on: "b")
            .applying(.performed(.archive, "b"))
            .applying(.noticeEnded)

        #expect(state.notice == nil)
        #expect(state.mode == .list)
    }

    @Test func noticeIsDroppedWhenTheNextMessageOpens() {
        let state = listOpened(on: "b")
            .applying(.performed(.archive, "b"))
            .applying(.selected("a"))

        #expect(state.notice == nil)
        #expect(state.mode == .expanded("a", from: .list))
    }

    @Test func noticeSurvivesNewMailArrivingInTheList() {
        let c = Fixtures.message("c")
        let state = listOpened(on: "b")
            .applying(.performed(.archive, "b"))
            .applying(.mailArrived(c))

        #expect(state.notice == MailAction.archive.confirmation)
        #expect(state.unread.map(\.id) == ["c", "a"])
    }

    @Test func confirmationClosesWhenPointerHasLeft() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.hoverChanged(true))
            .applying(.performed(.delete, "a"))
            .applying(.hoverChanged(false))

        #expect(state.mode == .confirmation(MailAction.delete.confirmation))
        #expect(state.applying(.confirmationEnded).mode == .closed)
    }

    @Test(arguments: [true, false])
    func mailArrivingDuringConfirmationIsAnnounced(hovering: Bool) {
        let confirming = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.hoverChanged(true))
            .applying(.performed(.archive, "a"))
            .applying(.hoverChanged(hovering))

        let state = confirming.applying(.mailArrived(b))

        #expect(state.mode == .alert("b"))
        #expect(state.unread.map(\.id) == ["b"])
        // A fresh alert: hovering opens it and it times out on its own.
        #expect(!state.isHovering)
        #expect(state.applying(.hoverChanged(true)).mode == .expanded("b", from: .alert))
        #expect(state.applying(.alertTimedOut).mode == .closed)
    }

    @Test func leavingTheNotchDropsTheNotice() {
        let state = listOpened(on: "b")
            .applying(.performed(.archive, "b"))
            .applying(.hoverChanged(false))

        #expect(state.notice == nil)
        #expect(state.mode == .closed)
    }

    @Test func backIsIgnoredUnlessAMessageIsOpen() {
        let alerting = NotchState.initial.applying(.mailArrived(a))

        #expect(alerting.applying(.backToList) == alerting)
    }

    @Test func backReturnsFromMessageToList() {
        let state = NotchState.initial
            .applying(.mailArrived(a))
            .applying(.hoverChanged(true))
            .applying(.backToList)

        #expect(state.mode == .list)
    }

    @Test func applyingNeverMutatesTheOriginal() {
        let original = NotchState.initial
        _ = original.applying(.mailArrived(a))

        #expect(original == .initial)
    }

    /// Two unread messages, the list open, and `id` opened from it.
    private func listOpened(on id: MailMessage.ID) -> NotchState {
        NotchState.initial
            .applying(.mailArrived(a))
            .applying(.mailArrived(b))
            .applying(.alertTimedOut)
            .applying(.hoverChanged(true))
            .applying(.selected(id))
    }
}
