import CoreGraphics
import Foundation

/// "Resting on the notch", not just passing over it: the pointer has to stay
/// inside, roughly still, for `duration` before the notch opens. Moving to a
/// screen above, or sliding across, never qualifies.
public struct HoverDwell: Equatable, Sendable {
    public let duration: TimeInterval
    /// How far the pointer may drift while resting.
    public let radius: CGFloat
    private var anchor: CGPoint?
    private var since: Date?

    public init(duration: TimeInterval, radius: CGFloat) {
        self.duration = duration
        self.radius = radius
    }

    /// Records a pointer position. Returns when it will count as resting if it
    /// stays put, or nil when it's outside.
    public mutating func track(_ point: CGPoint, inside: Bool, at now: Date) -> Date? {
        guard inside else {
            reset()
            return nil
        }
        if let anchor, let since, hypot(point.x - anchor.x, point.y - anchor.y) <= radius {
            return since.addingTimeInterval(duration)
        }
        anchor = point
        since = now
        return now.addingTimeInterval(duration)
    }

    public func isReady(at now: Date) -> Bool {
        guard let since else { return false }
        return now.timeIntervalSince(since) >= duration - 0.001
    }

    public mutating func reset() {
        anchor = nil
        since = nil
    }
}
