import AppKit

/// Opens web links in the default browser and brings it to the front. Notch Mail
/// is a menu-bar app that is never active itself, so macOS would otherwise open
/// the page behind whatever window you're in.
@MainActor
enum Browser {
    static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSApp.activate()
        if let browser = NSWorkspace.shared.urlForApplication(toOpen: url),
           let id = Bundle(url: browser)?.bundleIdentifier {
            NSApp.yieldActivation(toApplicationWithBundleIdentifier: id)
        }
        NSWorkspace.shared.open(url, configuration: configuration)
    }
}
