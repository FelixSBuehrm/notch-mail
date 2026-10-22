import SwiftUI

/// The notch silhouette: full width along the top edge with small outward
/// curves (so it melts into the menu bar), rounded at the bottom.
struct NotchShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set { (flare, bottomRadius) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        let f = min(flare, rect.width / 4)
        let r = min(bottomRadius, (rect.width - 2 * f) / 2, rect.height - f)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + f, y: rect.minY + f),
            control: CGPoint(x: rect.minX + f, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + f, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + f + r, y: rect.maxY),
            control: CGPoint(x: rect.minX + f, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - f - r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - f, y: rect.maxY - r),
            control: CGPoint(x: rect.maxX - f, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY + f))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - f, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}
