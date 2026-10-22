import AppKit
import NotchCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var panel: NotchPanel?
    private var hoverTracker: HoverTracker?
    private var statusMenu: StatusMenu?
    private var demo: DemoMailSource?
    private var mail: MailCoordinator?
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = NotchController(geometry: ScreenGeometry.current())
        let panel = NotchPanel(controller: controller)
        panel.orderFrontRegardless()

        let mail = MailCoordinator(notch: controller)
        controller.onAction = { [weak mail] action, message in mail?.perform(action, on: message) }
        controller.onRemind = { [weak mail] message, option in mail?.remind(message, option) }
        let demoOnly = CommandLine.arguments.contains("--demo-only")
        controller.replyBackend = { [weak mail] message in
            guard !demoOnly, let mail else { return DemoReplyBackend() }
            return mail.replyBackend(for: message)
        }
        // A replied-to message is done: mark it read in the mailbox too.
        controller.onReplySent = { [weak mail] message in mail?.perform(.markRead, on: message) }
        let demo = DemoMailSource(
            deliver: { [weak controller] message in controller?.send(.mailArrived(message)) },
            remove: { [weak controller] ids in controller?.send(.mailRemoved(ids)) }
        )

        self.controller = controller
        self.panel = panel
        self.demo = demo
        self.mail = mail
        hoverTracker = HoverTracker { [weak controller] point in
            controller?.pointerMoved(to: point)
        }
        statusMenu = StatusMenu(demo: demo, mail: mail, notch: controller)
        Task { _ = await MailContentBlocker.prepare() }
        observe()

        LoginItem.enableOnFirstInstall()
        mail.onConnected = { [weak demo] in demo?.clear() }
        // UI checks and screenshots: demo mail only, no Keychain, no network.
        if !demoOnly {
            // All secrets in one read at launch: any Keychain question comes now, not mid-reply.
            _ = try? SecretStore.current()
            mail.start()
        }
        // Decided by what's set up, not by whether the Keychain answered yet.
        startDemo(demo, hasAccounts: !demoOnly && (AccountStore.gmailAddress != nil || AccountStore.outlookAddress != nil))
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        // Mail piles up while the lid is closed; check as soon as it opens.
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let mail = self?.mail else { return }
                Task { await mail.checkNow() }
            }
        })
    }

    /// Demo mail only when no real account is connected, or when asked for with `--demo N`.
    private func startDemo(_ demo: DemoMailSource, hasAccounts: Bool) {
        let args = CommandLine.arguments
        let requested = args.firstIndex(of: "--demo").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
        let count = requested ?? (hasAccounts ? 0 : 1)
        for index in 0..<max(0, min(count, 20)) {
            demo.sendOne(after: .seconds(1.5 + 0.2 * Double(index)))
        }
        controller?.isPinned = args.contains("--pin")
        if args.contains("--tour"), let controller {
            Task { await DemoTour.run(controller) }
            return
        }
        if args.contains("--open-list"), count > 0 {
            Task { [weak controller] in
                try? await Task.sleep(for: .seconds(2.5))
                controller?.send(.alertTimedOut)
                controller?.send(.hoverChanged(true))
            }
        }
        if args.contains("--open-first") || args.contains("--open-reply"), count > 0 {
            Task { [weak controller] in
                try? await Task.sleep(for: .seconds(2.5))
                let newest = "demo-\(min(count, 20))"
                controller?.send(.selected(newest))
                if args.contains("--enlarged") { controller?.toggleEnlarged() }
                guard args.contains("--open-reply"), let message = controller?.state.message(newest) else { return }
                controller?.startReply(message)
                if let index = args.firstIndex(of: "--auto-draft"), args.indices.contains(index + 1) {
                    controller?.composer?.instruction = args[index + 1]
                    controller?.composer?.writeDraft()
                }
                if args.contains("--long-draft") {
                    controller?.composer?.draft = (1...14).map { "Line \($0): a pasted paragraph that is long enough to wrap across the editor, to check scrolling and spacing." }.joined(separator: "\n\n")
                }
            }
        }
    }

    private func screensChanged() {
        controller?.geometry = ScreenGeometry.current()
        panel?.reposition()
    }
}
