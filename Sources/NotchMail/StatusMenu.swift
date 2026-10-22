import AppKit
import NotchCore

/// The menu-bar icon: connected accounts, their status, demo controls, login item, quit.
/// Rebuilt each time it opens, so it always shows the current state.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let demo: DemoMailSource
    private let mail: MailCoordinator
    private let notch: NotchController
    private let menu = NSMenu()

    init(demo: DemoMailSource, mail: MailCoordinator, notch: NotchController) {
        self.demo = demo
        self.mail = mail
        self.notch = notch
        super.init()
        item.button?.image = NSImage(systemSymbolName: "envelope", accessibilityDescription: "Notch Mail")
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addCodesSection(to: menu)
        addGmailSection(to: menu)
        menu.addItem(.separator())
        addOutlookSection(to: menu)
        if mail.hasAccounts { menu.addItem(entry("Check now", #selector(checkNow))) }
        menu.addItem(.separator())
        menu.addItem(listSubmenu())
        menu.addItem(demoSubmenu())
        menu.addItem(.separator())
        let login = entry("Open at Login", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(entry("Quit Notch Mail", #selector(quit), key: "q"))
    }

    /// Login codes from the last 15 minutes; clicking one copies it.
    private func addCodesSection(to menu: NSMenu) {
        let codes = notch.recentCodes.current()
        guard !codes.isEmpty else { return }
        menu.addItem(info("Login codes"))
        for code in codes {
            let age = Formatting.shortAge(from: code.receivedAt, to: .now)
            let item = entry("\(Formatting.spacedCode(code.code))   \(code.sender) · \(age)", #selector(copyCode(_:)))
            item.representedObject = code.code
            item.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: "Login code")
            item.toolTip = "Click to copy"
            menu.addItem(item)
        }
        menu.addItem(.separator())
    }

    @objc private func copyCode(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        CodeClipboard.copy(code)
    }

    private func addGmailSection(to menu: NSMenu) {
        guard let status = mail.statuses[MailCoordinator.gmail], mail.isConnected(MailCoordinator.gmail) else {
            let title = mail.isConnecting ? "Waiting for Google in your browser…" : "Connect Gmail…"
            let connect = entry(title, #selector(connectGmail))
            connect.isEnabled = !mail.isConnecting
            menu.addItem(connect)
            if let error = mail.statuses[MailCoordinator.gmail]?.error { menu.addItem(warning(error)) }
            return
        }
        addStatus(status, to: menu)
        menu.addItem(entry("Disconnect Gmail", #selector(disconnectGmail)))
    }

    private func addOutlookSection(to menu: NSMenu) {
        guard let status = mail.statuses[MailCoordinator.outlook], mail.isConnected(MailCoordinator.outlook) else {
            switch mail.outlookSignIn {
            case .waiting(let code, let url)?:
                menu.addItem(info("Enter \(code) at \(url.host ?? "microsoft.com")"))
                let copy = entry("Copy code and open the page again", #selector(reopenOutlookPage(_:)))
                copy.representedObject = [code, url.absoluteString]
                menu.addItem(copy)
            case .starting?:
                menu.addItem(info("Starting Microsoft sign-in…"))
            case nil:
                menu.addItem(entry("Connect Outlook / Hotmail…", #selector(connectOutlook)))
                if let error = mail.statuses[MailCoordinator.outlook]?.error { menu.addItem(warning(error)) }
            }
            return
        }
        addStatus(status, to: menu)
        menu.addItem(entry("Disconnect \(status.account.name)", #selector(disconnectOutlook)))
    }

    private func addStatus(_ status: MailCoordinator.Status, to menu: NSMenu) {
        menu.addItem(info("\(status.account.name) · \(status.account.address)"))
        if let error = status.error {
            menu.addItem(warning(error))
        } else if let checked = status.lastChecked {
            menu.addItem(info("Checked \(checked.formatted(date: .omitted, time: .shortened))"))
        } else {
            menu.addItem(info("Checking…"))
        }
    }

    private func listSubmenu() -> NSMenuItem {
        let submenu = NSMenu()
        for limit in NotchController.listLimits {
            let item = entry("\(limit) messages", #selector(setListLimit(_:)))
            item.tag = limit
            item.state = notch.listLimit == limit ? .on : .off
            submenu.addItem(item)
        }
        let parent = NSMenuItem(title: "List shows", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    @objc private func setListLimit(_ sender: NSMenuItem) {
        notch.listLimit = sender.tag
    }

    private func demoSubmenu() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.addItem(entry("Simulate new mail", #selector(simulate)))
        let auto = entry("New demo mail every 20 s", #selector(toggleAutoDemo))
        auto.state = demo.isAutomatic ? .on : .off
        submenu.addItem(auto)
        let parent = NSMenuItem(title: "Demo", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func entry(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    private func warning(_ text: String) -> NSMenuItem {
        let item = info(text)
        item.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Problem")
        return item
    }

    private func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func connectGmail() {
        Task { await mail.connectGmail() }
    }

    @objc private func connectOutlook() {
        Task { await mail.connectOutlook() }
    }

    @objc private func disconnectOutlook() {
        mail.disconnectOutlook()
    }

    @objc private func reopenOutlookPage(_ sender: NSMenuItem) {
        guard let parts = sender.representedObject as? [String], parts.count == 2, let url = URL(string: parts[1]) else { return }
        CodeClipboard.copy(parts[0])
        Browser.open(url)
    }

    @objc private func disconnectGmail() {
        mail.disconnectGmail()
    }

    @objc private func checkNow() {
        Task { await mail.checkNow(force: true) }
    }

    @objc private func simulate() {
        demo.sendOne()
    }

    @objc private func toggleAutoDemo() {
        demo.isAutomatic.toggle()
    }

    @objc private func toggleLoginItem() {
        LoginItem.set(enabled: !LoginItem.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
