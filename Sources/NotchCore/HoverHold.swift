import CoreGraphics

/// Keeps the notch open while it shrinks under a still pointer.
///
/// Example: you archive from an open message and the notch goes back to the
/// shorter list, leaving the pointer below it. Without a hold that counts as
/// leaving and the notch snaps shut. With it, the old area still counts until
/// the pointer either reaches the new shape or leaves the old one.
public struct HoverHold: Equatable, Sendable {
    public let rect: CGRect?

    public static let none = HoverHold(rect: nil)

    public func holding(_ rect: CGRect) -> HoverHold {
        HoverHold(rect: rect)
    }

    /// Whether `point` is on the notch, and the hold to keep afterwards.
    public func evaluating(_ point: CGPoint, current: CGRect) -> (inside: Bool, next: HoverHold) {
        if current.contains(point) { return (true, .none) }
        if let rect, rect.contains(point) { return (true, self) }
        return (false, .none)
    }
}
