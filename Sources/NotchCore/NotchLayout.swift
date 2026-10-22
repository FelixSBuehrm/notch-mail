import CoreGraphics

/// How big the black notch shape is in each mode. The views and the hover
/// tracking both read these numbers, so they always agree.
public enum NotchLayout {
    /// The transparent panel the shape grows inside. Every mode must fit.
    public static let panelSize = CGSize(width: 840, height: 660)

    /// Outward curve at the top corners, so the shape melts into the menu bar.
    public static let closedFlare: CGFloat = 6
    public static let openFlare: CGFloat = 14

    public static let maxListRows = 5
    public static let listRowHeight: CGFloat = 54

    /// `enlarged`: the reader asked for a bigger message or reply view.
    public static func contentSize(for state: NotchState, notch: CGSize, enlarged: Bool = false) -> CGSize {
        let width: CGFloat
        let below: CGFloat  // height below the hardware notch
        switch state.mode {
        case .closed:
            return CGSize(width: notch.width + 2 * closedFlare, height: notch.height)
        case .alert:
            (width, below) = (400, 66)
        case .list:
            let rows = min(state.unread.count, maxListRows)
            (width, below) = (420, rows == 0 ? 76 : 20 + CGFloat(rows) * listRowHeight)
        case .expanded:
            (width, below) = enlarged ? (800, 600) : (580, 380)
        case .confirmation:
            (width, below) = (300, 48)
        case .replying:
            (width, below) = enlarged ? (800, 600) : (600, 420)
        case .sending:
            (width, below) = (420, 56)
        }
        return CGSize(width: max(width, notch.width + 2 * openFlare), height: notch.height + below)
    }

    public static func flare(for mode: NotchMode) -> CGFloat {
        mode == .closed ? closedFlare : openFlare
    }
}
