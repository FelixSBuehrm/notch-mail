import NotchCore
import SwiftUI

/// Writing a reply: tell Claude what to say, edit the draft, send.
struct ReplyView: View {
    @Bindable var composer: ReplyComposer
    var isEnlarged = false
    var onToggleSize: () -> Void = {}

    @FocusState private var focus: Field?

    private enum Field { case instruction, draft }

    private var message: MailMessage { composer.message }
    private var isDrafting: Bool { composer.phase == .drafting }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            instructionRow
            if let original = composer.context?.redirectedFrom, let target = composer.context?.toAddress {
                Label("Replies go to \(target), not to the sender \(original).", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if let error = composer.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            draftEditor
            footer
        }
        .foregroundStyle(.white)
        .onAppear { focus = .instruction }
        // Esc only closes an empty reply; a written one needs Cancel, so it isn't lost by accident.
        .onExitCommand { if composer.draft.isEmpty { composer.cancel() } }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button { composer.cancel() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to the message")
            VStack(alignment: .leading, spacing: 1) {
                Text("Reply to \(message.senderName)")
                    .font(.system(size: 13, weight: .semibold))
                Text(message.subject)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer()
            AccountBadge(account: message.account)
            SizeToggle(isEnlarged: isEnlarged, action: onToggleSize)
        }
    }

    private var instructionRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField(composer.draft.isEmpty ? "What should the reply say?" : "How should Claude change it?", text: $composer.instruction)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focus, equals: .instruction)
                .onSubmit { composer.writeDraft() }
                .disabled(isDrafting)
            if isDrafting {
                ProgressView().controlSize(.small)
                PillButton(title: "Stop", symbol: nil) { composer.stopDrafting() }
            } else {
                PillButton(title: composer.draft.isEmpty ? "Write" : "Rewrite", symbol: nil, prominent: true) {
                    composer.writeDraft()
                }
                .disabled(!composer.canDraft)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var draftEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $composer.draft)
                .font(.system(size: isEnlarged ? 15 : 13.5))
                .lineSpacing(isEnlarged ? 5 : 4)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.automatic)
                .focused($focus, equals: .draft)
                .disabled(isDrafting)
                .opacity(isDrafting ? 0.4 : 1)
            if composer.draft.isEmpty {
                Text(isDrafting ? (composer.status ?? "Writing…") : "The draft appears here. You can also just type your reply.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            } else if isDrafting, let status = composer.status {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.7), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .frame(maxHeight: .infinity)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: composer.phase) { _, phase in
            if phase == .editing, !composer.draft.isEmpty { focus = .draft }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("To: \(composer.context.map { "\($0.toName) <\($0.toAddress)>" } ?? "…")")
                if !composer.consulted.isEmpty, composer.phase != .drafting {
                    Text("Claude looked at: \(composer.consulted.joined(separator: " · "))")
                        .help(composer.consulted.joined(separator: "\n"))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer()
            PillButton(title: "Cancel", symbol: nil) { composer.cancel() }
            PillButton(title: "Send", symbol: "paperplane.fill", prominent: true) { composer.send() }
                .disabled(!composer.canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (⌘↩). You get \(Int(ReplyComposer.undoWindow)) seconds to undo.")
        }
    }
}

/// After Send: a few seconds to change your mind.
struct SendingView: View {
    let composer: ReplyComposer

    private var recipient: String {
        let name = composer.context?.toName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? (composer.context?.toAddress ?? composer.message.senderAddress) : name
    }

    var body: some View {
        HStack(spacing: 10) {
            if composer.phase == .countdown, let sendsAt = composer.sendsAt {
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    let left = max(0, sendsAt.timeIntervalSince(context.date))
                    HStack(spacing: 10) {
                        ProgressView(value: left, total: ReplyComposer.undoWindow)
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                        // The seconds always stay visible; a long name gets cut instead.
                        Text("Sending in \(Int(left.rounded(.up)))")
                            .font(.system(size: 12.5, weight: .semibold))
                            .monospacedDigit()
                            .fixedSize()
                        Text("to \(recipient)")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer()
                PillButton(title: "Undo", symbol: "arrow.uturn.backward", prominent: true) { composer.undo() }
                    .keyboardShortcut("z", modifiers: .command)
            } else {
                ProgressView().controlSize(.small)
                Text("Sending…").font(.system(size: 12.5, weight: .medium))
                Spacer()
            }
        }
        .foregroundStyle(.white)
    }
}
