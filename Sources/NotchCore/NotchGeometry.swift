import CoreGraphics

/// Where the notch sits on a screen, in AppKit screen coordinates (origin bottom-left).
/// Built from plain values so it can be tested without a real `NSScreen`.
public struct NotchGeometry: Equatable, Sendable {
    /// Width used on screens without a notch, centred under the menu bar.
    public static let fallbackWidth: CGFloat = 190

    public let notchRect: CGRect
    public let hasNotch: Bool

    public var notchSize: CGSize { notchRect.size }

    /// - Parameters:
    ///   - auxiliaryLeft/Right: the menu bar areas left and right of the notch
    ///     (`NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`), nil without one.
    public static func make(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeft: CGRect?,
        auxiliaryRight: CGRect?,
        menuBarHeight: CGFloat
    ) -> NotchGeometry {
        if safeAreaTop > 0, let left = auxiliaryLeft, let right = auxiliaryRight, right.minX > left.maxX {
            let rect = CGRect(
                x: left.maxX,
                y: screenFrame.maxY - safeAreaTop,
                width: right.minX - left.maxX,
                height: safeAreaTop
            )
            return NotchGeometry(notchRect: rect, hasNotch: true)
        }
        let rect = CGRect(
            x: screenFrame.midX - fallbackWidth / 2,
            y: screenFrame.maxY - menuBarHeight,
            width: fallbackWidth,
            height: menuBarHeight
        )
        return NotchGeometry(notchRect: rect, hasNotch: false)
    }

    /// Frame for a panel of `size` hanging from the top edge, centred on the notch.
    public func panelFrame(size: CGSize) -> CGRect {
        CGRect(
            x: notchRect.midX - size.width / 2,
            y: notchRect.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// The area that counts as "pointer on the notch" for visible content of `contentSize`.
    /// Reaches slightly past the top edge: `CGRect.contains` excludes `maxY`,
    /// and a pointer thrown upwards sits exactly there.
    public func hotRect(contentSize: CGSize, slack: CGFloat) -> CGRect {
        let overhang: CGFloat = 2
        return CGRect(
            x: notchRect.midX - contentSize.width / 2 - slack,
            y: notchRect.maxY - contentSize.height - slack,
            width: contentSize.width + 2 * slack,
            height: contentSize.height + slack + overhang
        )
    }
}
