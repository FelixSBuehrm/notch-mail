import Foundation
import MailSources
import NotchCore
import Observation

/// One reply being written: the instruction for Claude, the editable draft,
/// and the undo countdown after Send. The notch's mode follows through events.
@MainActor
@Observable
final class ReplyComposer {
    enum Phase: Equatable {
        case editing
        case drafting
        /// Send pressed; it goes out at `sendsAt` unless undone.
        case countdown
        case sending
    }

    static let undoWindow: TimeInterval = 5

    let message: MailMessage
    var instruction = ""
    var draft = ""
    private(set) var phase = Phase.editing
    /// Who the reply really goes to; nil until looked up. Nothing can be sent before.
    private(set) var context: ReplyContext?
    /// What Claude is doing right now, e.g. "Searching Gmail: invoice".
    private(set) var status: String?
    /// Everything Claude looked at for the current draft, so you know what may be in it.
    private(set) var consulted: [String] = []
    private(set) var error: String?
    private(set) var sendsAt: Date?

    @ObservationIgnored private let backend: any ReplyBackend
    @ObservationIgnored private let myName: String
    @ObservationIgnored private var work: Task<Void, Never>?
    /// Identifies the newest draft request; results of older (stopped) ones are dropped.
    @ObservationIgnored private var draftToken = UUID()
    @ObservationIgnored var onEvent: ((NotchEvent) -> Void)?
    @ObservationIgnored var onSent: ((MailMessage) -> Void)?

    init(message: MailMessage, backend: any ReplyBackend, myName: String) {
        self.message = message
        self.backend = backend
        self.myName = myName
        Task { [weak self] in await self?.loadContext() }
    }

    var canDraft: Bool {
        phase == .editing && (draft.isBlank || !instruction.isBlank)
    }

    var canSend: Bool { phase == .editing && !draft.isBlank && context != nil }

    private func loadContext() async {
        do {
            context = try await backend.context(for: message)
        } catch {
            self.error = "Can't reply: \(error.localizedDescription)"
        }
    }

    func writeDraft() {
        guard canDraft else { return }
        error = nil
        phase = .drafting
        status = "Writing…"
        consulted = []
        let token = UUID()
        draftToken = token
        let request = DraftRequest(
            message: message, instruction: instruction.trimmed,
            currentDraft: draft.isBlank ? nil : draft, myName: myName, recipient: context?.toAddress
        )
        work = Task { [weak self, backend] in
            do {
                let text = try await backend.draft(request) { line in
                    Task { @MainActor in self?.progressed(line, token: token) }
                }
                self?.finishDraft(text, token: token)
            } catch {
                self?.failDraft(error, token: token)
            }
        }
    }

    private func progressed(_ line: String, token: UUID) {
        guard token == draftToken, phase == .drafting else { return }
        status = line
        consulted.append(line)
    }

    private func finishDraft(_ text: String, token: UUID) {
        guard token == draftToken, phase == .drafting else { return }
        draft = text
        instruction = ""
        phase = .editing
        status = nil
    }

    private func failDraft(_ error: Error, token: UUID) {
        guard token == draftToken, phase == .drafting else { return }
        if !(error is CancellationError) { self.error = error.localizedDescription }
        phase = .editing
        status = nil
    }

    func stopDrafting() {
        guard phase == .drafting else { return }
        draftToken = UUID()
        work?.cancel()
        phase = .editing
        status = nil
    }

    func send() {
        guard canSend, let context else { return }
        error = nil
        phase = .countdown
        sendsAt = Date().addingTimeInterval(Self.undoWindow)
        onEvent?(.replySending)
        let body = draft
        work = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.undoWindow))
            guard !Task.isCancelled, let self, self.phase == .countdown else { return }
            await self.transmit(body, context: context)
        }
    }

    private func transmit(_ body: String, context: ReplyContext) async {
        phase = .sending
        do {
            try await backend.send(body, context: context, as: myName)
            onEvent?(.replySent)
            onSent?(message)
        } catch {
            // A dropped connection may still have delivered it: don't invite a blind resend.
            self.error = error is URLError
                ? "Connection problem: it may or may not have been sent. Check your Sent folder before sending again."
                : "Not sent: \(error.localizedDescription)"
            phase = .editing
            onEvent?(.replyFailed)
        }
    }

    func undo() {
        guard phase == .countdown else { return }
        work?.cancel()
        phase = .editing
        sendsAt = nil
        onEvent?(.replyUndone)
    }

    /// Drops the reply. Not possible once it's on its way.
    func cancel() {
        guard phase != .sending else { return }
        if phase == .countdown { undo() }
        draftToken = UUID()
        work?.cancel()
        onEvent?(.replyCancelled)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var isBlank: Bool { trimmed.isEmpty }
}
