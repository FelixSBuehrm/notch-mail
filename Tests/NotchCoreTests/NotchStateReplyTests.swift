import Testing
@testable import NotchCore

@Suite("Notch state: replying")
struct NotchStateReplyTests {
    let a = Fixtures.message("a")
    let b = Fixtures.message("b")

    /// "a" open after hovering its alert.
    private var reading: NotchState {
        NotchState.initial.applying(.mailArrived(a)).applying(.hoverChanged(true))
    }

    /// "a" opened from the list, with "b" also unread.
    private var readingFromList: NotchState {
        NotchState.initial
            .applying(.mailLoaded([a, b]))
            .applying(.hoverChanged(true))
            .applying(.selected("a"))
    }

    @Test func replyOpensFromTheOpenMessage() {
        let state = reading.applying(.replyOpened("a"))

        #expect(state.mode == .replying(a, from: .alert))
        #expect(state.isReplying)
    }

    @Test func replyOnlyOpensForTheMessageThatIsOpen() {
        #expect(reading.applying(.replyOpened("b")) == reading)
        #expect(NotchState.initial.applying(.replyOpened("a")) == .initial)
    }

    @Test func leavingTheNotchKeepsTheReplyOpen() {
        let state = reading.applying(.replyOpened("a")).applying(.hoverChanged(false))

        #expect(state.mode == .replying(a, from: .alert))
        #expect(!state.isHovering)
    }

    @Test func newMailDoesNotInterruptAReply() {
        let state = reading.applying(.replyOpened("a")).applying(.mailArrived(b))

        #expect(state.mode == .replying(a, from: .alert))
        #expect(state.unread.map(\.id).contains("b"))
    }

    @Test func replyStaysOpenWhenTheMessageIsReadElsewhere() {
        let state = reading.applying(.replyOpened("a")).applying(.mailRemoved(["a"]))

        #expect(state.mode == .replying(a, from: .alert))
        #expect(state.unread.isEmpty)
    }

    @Test func cancellingGoesBackToTheMessage() {
        let state = reading.applying(.replyOpened("a")).applying(.replyCancelled)

        #expect(state.mode == .expanded("a", from: .alert))
    }

    @Test func cancellingAfterTheMessageVanishedCloses() {
        let state = reading
            .applying(.replyOpened("a"))
            .applying(.hoverChanged(false))
            .applying(.mailRemoved(["a"]))
            .applying(.replyCancelled)

        #expect(state.mode == .closed)
    }

    @Test func sendingCanBeUndone() {
        let replying = reading.applying(.replyOpened("a"))
        let sending = replying.applying(.replySending)

        #expect(sending.mode == .sending(a, from: .alert))
        #expect(sending.applying(.replyUndone) == replying)
    }

    @Test func sentReplyRemovesTheMessageAndConfirms() {
        let state = reading
            .applying(.replyOpened("a"))
            .applying(.replySending)
            .applying(.replySent)

        #expect(state.mode == .confirmation("Sent"))
        #expect(state.unread.isEmpty)
    }

    @Test func sentReplyFromTheListReturnsToTheList() {
        let state = readingFromList
            .applying(.replyOpened("a"))
            .applying(.replySending)
            .applying(.replySent)

        #expect(state.mode == .list)
        #expect(state.notice == "Sent")
        #expect(state.unread.map(\.id) == ["b"])
    }

    @Test func sentReplyFromTheListClosesWhenThePointerLeft() {
        let state = readingFromList
            .applying(.replyOpened("a"))
            .applying(.hoverChanged(false))
            .applying(.replySending)
            .applying(.replySent)

        #expect(state.mode == .confirmation("Sent"))
    }

    @Test func failedSendReturnsToTheReply() {
        let state = reading
            .applying(.replyOpened("a"))
            .applying(.replySending)
            .applying(.replyFailed)

        #expect(state.mode == .replying(a, from: .alert))
        #expect(state.unread.map(\.id) == ["a"])
    }

    @Test func sendEventsOutsideAReplyAreIgnored() {
        #expect(reading.applying(.replySending) == reading)
        #expect(reading.applying(.replySent) == reading)
        #expect(reading.applying(.replyCancelled) == reading)
    }
}
