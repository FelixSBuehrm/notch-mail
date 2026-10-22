import AppKit
import NotchCore

/// Reads the notch position from the real screens.
@MainActor
enum ScreenGeometry {
    /// The built-in display with a notch if there is one, else the main screen.
    static var notchScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    static func current() -> NotchGeometry {
        guard let screen = notchScreen else {
            return .make(
                screenFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), safeAreaTop: 0,
                auxiliaryLeft: nil, auxiliaryRight: nil, menuBarHeight: NSStatusBar.system.thickness
            )
        }
        // visibleFrame excludes the menu bar; 0 when the menu bar auto-hides.
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return .make(
            screenFrame: screen.frame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeft: screen.auxiliaryTopLeftArea,
            auxiliaryRight: screen.auxiliaryTopRightArea,
            menuBarHeight: menuBar > 0 ? menuBar : NSStatusBar.system.thickness
        )
    }
}
