import CoreGraphics
import Foundation
import Testing
@testable import NotchCore

@Suite("Hover dwell")
struct HoverDwellTests {
    let start = Date(timeIntervalSince1970: 1_000)

    @Test func restingInsideBecomesReadyAfterTheDuration() {
        var dwell = HoverDwell(duration: 0.4, radius: 12)

        let due = dwell.track(CGPoint(x: 100, y: 10), inside: true, at: start)

        #expect(due == start.addingTimeInterval(0.4))
        #expect(!dwell.isReady(at: start.addingTimeInterval(0.2)))
        #expect(dwell.isReady(at: start.addingTimeInterval(0.4)))
    }

    @Test func smallJitterKeepsTheTimer() {
        var dwell = HoverDwell(duration: 0.4, radius: 12)
        _ = dwell.track(CGPoint(x: 100, y: 10), inside: true, at: start)

        let due = dwell.track(CGPoint(x: 106, y: 14), inside: true, at: start.addingTimeInterval(0.3))

        #expect(due == start.addingTimeInterval(0.4))
    }

    @Test func movingAcrossRestartsTheTimer() {
        var dwell = HoverDwell(duration: 0.4, radius: 12)
        _ = dwell.track(CGPoint(x: 100, y: 10), inside: true, at: start)

        let due = dwell.track(CGPoint(x: 140, y: 10), inside: true, at: start.addingTimeInterval(0.3))

        #expect(abs((due ?? start).timeIntervalSince(start) - 0.7) < 0.0001)
        #expect(!dwell.isReady(at: start.addingTimeInterval(0.5)))
    }

    @Test func leavingResets() {
        var dwell = HoverDwell(duration: 0.4, radius: 12)
        _ = dwell.track(CGPoint(x: 100, y: 10), inside: true, at: start)

        #expect(dwell.track(CGPoint(x: 100, y: 200), inside: false, at: start.addingTimeInterval(0.1)) == nil)
        #expect(!dwell.isReady(at: start.addingTimeInterval(1)))
    }
}
