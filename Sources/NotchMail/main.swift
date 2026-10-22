import AppKit

// Menu-bar app: no Dock icon, no main window. The notch panel is the UI.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
