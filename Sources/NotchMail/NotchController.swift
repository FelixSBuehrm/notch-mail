import AppKit
import NotchCore
import Observation
import SwiftUI

/// Holds the notch state and turns time and pointer movement into events.
/// All decisions live in `NotchState.applying(_:)`; this class only schedules.
@MainActor
@Observable
final class NotchController {
    private(set) var state = NotchState.initial
    var geometry: NotchGeometry

    @ObservationIgnored private var alertTimer: Task<Void, Never>?
    @ObservationIgnored private var confirmationTimer: Task<Void, Never>?
    @ObservationIgnored private var noticeTimer: Task<Void, Never>?
    @ObservationIgnored private var hoverExit: Task<Void, Never>?
    @ObservationIgnored private var hold = HoverHold.none
    @ObservationIgnored private var dwell = HoverDwell(duration: 0, radius: NotchController.dwellRadius)
    @ObservationIgnored private var dwellTimer: Task<Void, Never>?
    @ObservationIgnored private var dwellDue: Date?

    static let alertDuration: Duration = .seconds(6)
    static let confirmationDuration: Duration = .seconds(1.2)
    static let noticeDuration: Duration = .seconds(1.6)
    /// Grace period so a pointer brushing past the edge doesn't snap the notch shut.
    static let hoverExitDelay: Duration = .milliseconds(350)
    /// Extra margin around the closed notch so it's easy to hit.
    static let closedSlack: CGFloat = 8
    /// The pointer has to rest on the closed notch this long before it opens,
    /// so passing over it (e.g. to a screen above) doesn't.
    static let closedDwell: TimeInterval = 0.4
    /// A popped-up mail is a deliberate target: it opens almost at once.
    static let alertDwell: TimeInterval = 0.15
    /// How far the pointer may drift while resting.
    static let dwellRadius: CGFloat = 12

    @ObservationIgnored private let pointerLocation: @MainActor () -> CGPoint
    /// Carries out a button press on the real mailbox (set by the app).
    @ObservationIgnored var onAction: ((MailAction, MailMessage) -> Void)?
    @ObservationIgnored var onRemind: ((MailMessage, RemindOption) -> Void)?
    /// How to draft and send a reply to this message (set by the app).
    @ObservationIgnored var replyBackend: ((MailMessage) -> any ReplyBackend)?
    @ObservationIgnored var onReplySent: ((MailMessage) -> Void)?
    /// The panel takes or gives up the keyboard when a reply opens or closes.
    @ObservationIgnored var onKeyboardChange: ((Bool) -> Void)?

    /// The reply being written, while the notch is replying or sending.
    private(set) var composer: ReplyComposer?

    static let listLimits = [10, 20, 50]
    /// How many unread messages the list scrolls through (menu setting).
    var listLimit = UserDefaults.standard.object(forKey: "list.limit") as? Int ?? 20 {
        didSet { UserDefaults.standard.set(listLimit, forKey: "list.limit") }
    }

    init(geometry: NotchGeometry, pointerLocation: @escaping @MainActor () -> CGPoint = { NSEvent.mouseLocation }) {
        self.geometry = geometry
        self.pointerLocation = pointerLocation
    }

    var contentSize: CGSize {
        NotchLayout.contentSize(for: state, notch: geometry.notchSize, enlarged: isEnlarged)
    }

    /// Login codes from the last 15 minutes (menu bar).
    private(set) var recentCodes = RecentCodes()

    /// Copies a code and says so in the notch.
    func copyCode(_ code: String) {
        CodeClipboard.copy(code)
        send(.notify("Code copied"))
    }

    /// Bigger message and reply views with larger text, until the notch closes.
    private(set) var isEnlarged = false

    func toggleEnlarged() {
        let previousRect = hotRect
        withAnimation(.spring(duration: 0.42, bounce: 0.15)) { isEnlarged.toggle() }
        hold = hold.holding(previousRect)
        pointerMoved(to: pointerLocation())
    }

    func send(_ event: NotchEvent) {
        switch event {
        case .mailArrived(let message): recentCodes.record([message])
        case .mailLoaded(let messages): recentCodes.record(messages)
        default: break
        }
        let previous = state.mode
        let wasReplying = state.isReplying
        let previousRect = hotRect
        withAnimation(.spring(duration: 0.42, bounce: 0.22)) {
            state = state.applying(event)
        }
        switch state.mode {
        case .expanded, .replying, .sending: break
        default: isEnlarged = false
        }
        if wasReplying != state.isReplying {
            if !state.isReplying { composer = nil }
            onKeyboardChange?(state.isReplying)
        }
        // A second "Archived" in a row is the same mode but still needs a fresh timer.
        let isAction = if case .performed = event { true } else { false }
        if isAction, state.notice != nil { scheduleNoticeTimer() }
        guard state.mode != previous || isAction else { return }
        scheduleTimers(for: state.mode)
        // The shape just changed size under a pointer that may not move again:
        // keep the old area counting until the pointer settles.
        hold = state.isHovering ? hold.holding(previousRect) : .none
        pointerMoved(to: pointerLocation())
    }

    /// A button in the open message: update the notch, then tell the mailbox.
    func perform(_ action: MailAction, on message: MailMessage) {
        send(.performed(action, message.id))
        onAction?(action, message)
    }

    func remind(_ message: MailMessage, _ option: RemindOption) {
        onRemind?(message, option)
    }

    /// Reply pressed in the open message.
    func startReply(_ message: MailMessage) {
        guard let backend = replyBackend?(message) else { return }
        let composer = ReplyComposer(message: message, backend: backend, myName: AccountStore.replyName)
        composer.onEvent = { [weak self] in self?.send($0) }
        composer.onSent = { [weak self] in self?.onReplySent?($0) }
        self.composer = composer
        send(.replyOpened(message.id))
        if !state.isReplying { self.composer = nil }
    }

    /// Screenshots: the pointer is ignored, so the notch stays as it was opened.
    var isPinned = false

    func pointerMoved(to point: CGPoint) {
        guard !isPinned else { return }
        let (inside, nextHold) = hold.evaluating(point, current: hotRect)
        hold = nextHold
        if inside {
            hoverExit?.cancel()
            hoverExit = nil
            if !state.isHovering { enterAfterDwell(at: point) }
        } else {
            cancelDwell()
        }
        if !inside, state.isHovering, hoverExit == nil {
            hoverExit = after(Self.hoverExitDelay) { controller in
                controller.hoverExit = nil
                controller.send(.hoverChanged(false))
            }
        }
    }

    /// Opens once the pointer has rested long enough; re-checked by a timer
    /// because a resting pointer sends no more movement.
    private func enterAfterDwell(at point: CGPoint) {
        let needed: TimeInterval = switch state.mode {
        case .closed: Self.closedDwell
        case .alert: Self.alertDwell
        default: 0
        }
        if dwell.duration != needed { dwell = HoverDwell(duration: needed, radius: Self.dwellRadius) }
        let now = Date()
        guard let due = dwell.track(point, inside: true, at: now) else { return }
        if dwell.isReady(at: now) {
            cancelDwell()
            send(.hoverChanged(true))
        } else if due != dwellDue {
            dwellDue = due
            dwellTimer?.cancel()
            dwellTimer = after(.seconds(due.timeIntervalSince(now))) { controller in
                controller.dwellTimer = nil
                controller.dwellDue = nil
                controller.pointerMoved(to: controller.pointerLocation())
            }
        }
    }

    private func cancelDwell() {
        dwell.reset()
        dwellTimer?.cancel()
        dwellTimer = nil
        dwellDue = nil
    }

    private var hotRect: CGRect {
        let slack = state.mode == .closed ? Self.closedSlack : 0
        return geometry.hotRect(contentSize: contentSize, slack: slack)
    }

    private func scheduleNoticeTimer() {
        noticeTimer?.cancel()
        noticeTimer = after(Self.noticeDuration) { $0.send(.noticeEnded) }
    }

    private func scheduleTimers(for mode: NotchMode) {
        // Leaving a mode cancels its timer, so a stale one can't cut the next one short.
        alertTimer?.cancel()
        alertTimer = nil
        confirmationTimer?.cancel()
        confirmationTimer = nil
        switch mode {
        case .alert:
            alertTimer = after(Self.alertDuration) { $0.send(.alertTimedOut) }
        case .confirmation:
            confirmationTimer = after(Self.confirmationDuration) { $0.send(.confirmationEnded) }
        case .closed, .list, .expanded, .replying, .sending:
            break
        }
    }

    private func after(_ delay: Duration, _ action: @escaping @MainActor (NotchController) -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            action(self)
        }
    }
}
