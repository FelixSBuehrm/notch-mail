import Foundation
import NotchCore
import ServiceManagement
import os

/// Opening Notch Mail at login, through macOS's own Login Items list
/// (System Settings → General → Login Items), so it can be switched off there too.
@MainActor
enum LoginItem {
    private static let log = Logger(subsystem: AppIdentity.bundleID, category: "login-item")
    private static let enabledOnceKey = "loginItemEnabledOnce"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Turns it on the first time the app runs from /Applications. After that the
    /// user's choice wins, so switching it off stays off.
    static func enableOnFirstInstall() {
        let defaults = UserDefaults.standard
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/"),
              !defaults.bool(forKey: enabledOnceKey) else { return }
        if set(enabled: true) { defaults.set(true, forKey: enabledOnceKey) }
    }

    /// Returns whether the change went through; failures are logged.
    @discardableResult
    static func set(enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
            return false
        }
    }
}
