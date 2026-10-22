import AppKit
import NotchCore
import SwiftUI

/// A transparent, click-through window pinned over the notch. The black
/// shape inside grows and shrinks; the rest of the panel stays invisible.
@MainActor
final class NotchPanel: NSPanel {
    private let controller: NotchController

    init(controller: NotchController) {
        self.controller = controller
        super.init(
            contentRect: controller.geometry.panelFrame(size: NotchLayout.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the menu bar, so the shape can cover the notch area.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Keep mail out of screen sharing and recordings. `--capturable` turns
        // this off so the notch can be screenshotted while developing.
        let capturable = CommandLine.arguments.contains("--capturable")
        sharingType = capturable ? .readOnly : .none
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true

        let hosting = FirstClickHostingView(rootView: NotchRootView(controller: controller))
        hosting.onPointerMoved = { [weak controller] in
            controller?.pointerMoved(to: NSEvent.mouseLocation)
        }
        contentView = hosting
        controller.onKeyboardChange = { [weak self] in self?.keyboardChanged($0) }
    }

    func reposition() {
        setFrame(controller.geometry.panelFrame(size: NotchLayout.panelSize), display: true)
    }

    /// Only a reply takes the keyboard; otherwise the app you're in keeps it.
    override var canBecomeKey: Bool { controller.state.isReplying }
    override var canBecomeMain: Bool { false }

    func keyboardChanged(_ wanted: Bool) {
        if wanted {
            makeKey()
        } else if isKeyWindow {
            // Hand the keyboard back: re-showing the panel drops its key status,
            // and the app you were in gets its window back.
            orderOut(nil)
            orderFrontRegardless()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    /// A menu-bar app has no Edit menu, so ⌘X/C/V/A/Z are routed to the text
    /// being edited. SwiftUI shortcuts (⌘↩ Send, ⌘Z Undo send) go first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard firstResponder is NSText else { return false }
        if flags == .command || flags == [.command, .shift], let key = event.charactersIgnoringModifiers?.lowercased() {
            let action: Selector? = switch (key, flags.contains(.shift)) {
            case ("x", false): #selector(NSText.cut(_:))
            case ("c", false): #selector(NSText.copy(_:))
            case ("v", false): #selector(NSText.paste(_:))
            case ("a", false): #selector(NSText.selectAll(_:))
            case ("z", false): Selector(("undo:"))
            case ("z", true): Selector(("redo:"))
            default: nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        }
        return false
    }
}

/// Buttons react on the first click even though the panel never activates,
/// and pointer movement over the panel is reported (the global monitor
/// only sees movement over other apps).
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    var onPointerMoved: (() -> Void)?
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onPointerMoved?()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointerMoved?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointerMoved?()
    }
}
