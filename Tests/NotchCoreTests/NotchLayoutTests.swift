import CoreGraphics
import Testing
@testable import NotchCore

@Suite("Notch layout")
struct NotchLayoutTests {
    let notch = CGSize(width: 185, height: 32)

    private func state(_ mode: NotchMode, unread count: Int = 0) -> NotchState {
        let unread = (0..<count).map { Fixtures.message("m\($0)") }
        return NotchState(unread: unread, mode: mode, isHovering: false)
    }

    @Test func closedMatchesTheHardwareNotch() {
        let size = NotchLayout.contentSize(for: state(.closed), notch: notch)

        #expect(size.height == notch.height)
        #expect(size.width == notch.width + 2 * NotchLayout.closedFlare)
    }

    @Test func listGrowsWithMessagesUpToTheCap() {
        let one = NotchLayout.contentSize(for: state(.list, unread: 1), notch: notch)
        let three = NotchLayout.contentSize(for: state(.list, unread: 3), notch: notch)
        let capped = NotchLayout.contentSize(for: state(.list, unread: NotchLayout.maxListRows), notch: notch)
        let many = NotchLayout.contentSize(for: state(.list, unread: 40), notch: notch)

        #expect(three.height > one.height)
        #expect(many == capped)
    }

    @Test func emptyListStillHasRoomForInboxZero() {
        let size = NotchLayout.contentSize(for: state(.list), notch: notch)

        #expect(size.height > notch.height + 40)
    }

    @Test func everyModeFitsInsideThePanel() {
        let message = Fixtures.message("m0")
        let modes: [NotchMode] = [
            .closed, .alert("m0"), .list, .expanded("m0", from: .list), .confirmation("Archived"),
            .replying(message, from: .list), .sending(message, from: .list),
        ]
        for mode in modes {
            for enlarged in [false, true] {
                let size = NotchLayout.contentSize(for: state(mode, unread: 40), notch: notch, enlarged: enlarged)
                #expect(size.width <= NotchLayout.panelSize.width, "\(mode) too wide")
                #expect(size.height <= NotchLayout.panelSize.height, "\(mode) too tall")
            }
        }
    }

    @Test func openStatesAreNeverNarrowerThanTheNotch() {
        let wide = CGSize(width: 400, height: 38)
        let size = NotchLayout.contentSize(for: state(.confirmation("Archived")), notch: wide)

        #expect(size.width >= wide.width)
    }
}
