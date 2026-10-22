import CoreGraphics
import Testing
@testable import NotchCore

@Suite("Hover hold")
struct HoverHoldTests {
    let big = CGRect(x: 0, y: 0, width: 400, height: 300)    // e.g. the open message
    let small = CGRect(x: 50, y: 200, width: 300, height: 100) // the shorter list after it

    @Test func withoutAHoldOnlyTheCurrentShapeCounts() {
        let (inside, _) = HoverHold.none.evaluating(CGPoint(x: 10, y: 10), current: small)

        #expect(!inside)
    }

    @Test func pointerLeftBelowAShrunkShapeStillCountsAsOnTheNotch() {
        let hold = HoverHold.none.holding(big)

        let (inside, next) = hold.evaluating(CGPoint(x: 10, y: 10), current: small)

        #expect(inside)
        #expect(next == hold)
    }

    @Test func reachingTheNewShapeReleasesTheHold() {
        let hold = HoverHold.none.holding(big)

        let (inside, next) = hold.evaluating(CGPoint(x: 100, y: 250), current: small)

        #expect(inside)
        #expect(next == .none)
    }

    @Test func leavingTheOldShapeReleasesTheHold() {
        let hold = HoverHold.none.holding(big)

        let (inside, next) = hold.evaluating(CGPoint(x: 900, y: 900), current: small)

        #expect(!inside)
        #expect(next == .none)
    }

    @Test func onceReleasedTheOldAreaNoLongerCounts() {
        let (_, released) = HoverHold.none.holding(big)
            .evaluating(CGPoint(x: 100, y: 250), current: small)

        let (inside, _) = released.evaluating(CGPoint(x: 10, y: 10), current: small)

        #expect(!inside)
    }
}
