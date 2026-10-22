import NotchCore
import SwiftUI

/// One open message: header, scrollable body, actions.
struct MessageDetailView: View {
    let message: MailMessage
    let onAction: (MailAction) -> Void
    let onRemind: (RemindOption) -> Void
    let onReply: () -> Void
    let onBack: () -> Void
    var isEnlarged = false
    var onToggleSize: () -> Void = {}
    var onCopyCode: (String) -> Void = { _ in }

    @State private var choosingReminder = false
    @State private var showsQuoted = false
    @State private var loadsImages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(message.subject)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
            if let code = message.loginCode { codeBanner(code) }
            messageBody
            if choosingReminder { reminderChoices } else { actions }
        }
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.15), value: choosingReminder)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Back to the list")
            Avatar(name: message.senderName, key: message.senderAddress, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(message.senderName).font(.system(size: 13, weight: .semibold))
                    AccountBadge(account: message.account)
                }
                Text(message.senderAddress)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer()
            Text(Formatting.shortAge(from: message.receivedAt, to: .now))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            SizeToggle(isEnlarged: isEnlarged, action: onToggleSize)
        }
    }

    private func codeBanner(_ code: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 0.65))
            Text(Formatting.spacedCode(code))
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
            PillButton(title: "Copy code", symbol: "doc.on.doc", prominent: true) { onCopyCode(code) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    /// HTML mail with its own layout; plain text otherwise (or if the web view can't be locked down).
    @ViewBuilder private var messageBody: some View {
        if let html = message.html, let blocker = MailContentBlocker.ruleList {
            VStack(alignment: .leading, spacing: 6) {
                HTMLMailView(html: html, showsQuoted: showsQuoted, loadsImages: loadsImages, blocker: blocker, zoom: isEnlarged ? 1.15 : 1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                htmlOptions(html)
            }
        } else {
            ScrollView {
                MessageBodyView(content: MailBody(message.body), fontSize: isEnlarged ? 15.5 : 13.5)
                    .padding(.trailing, 6)
            }
            .scrollIndicators(.never)
        }
    }

    @ViewBuilder private func htmlOptions(_ html: String) -> some View {
        let quote = HTMLMailView.hasQuote(html)
        let images = HTMLMailView.hasRemoteImages(html)
        if quote || images {
            HStack(spacing: 8) {
                if quote {
                    SmallToggle(title: showsQuoted ? "Hide earlier messages" : "Show earlier messages",
                                symbol: showsQuoted ? "chevron.up" : "ellipsis") { showsQuoted.toggle() }
                }
                if images, !loadsImages {
                    SmallToggle(title: "Load images", symbol: "photo") { loadsImages = true }
                        .help("Pictures are off so senders can't see when you read their mail")
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            PillButton(title: "Reply", symbol: "arrowshape.turn.up.left.fill", prominent: true, action: onReply)
                .help("Write a reply, with a draft from Claude if you like")
            Spacer()
            PillButton(title: "Remind", symbol: "bell") { choosingReminder = true }
            PillButton(title: "Read", symbol: "envelope.open") { onAction(.markRead) }
            PillButton(title: "Archive", symbol: "archivebox") { onAction(.archive) }
            PillButton(title: "Delete", symbol: "trash", destructive: true) { onAction(.delete) }
        }
    }

    /// Replaces the action row: when should it come back?
    private var reminderChoices: some View {
        HStack(spacing: 8) {
            Image(systemName: "bell")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ForEach(RemindOption.allCases.filter { $0.isAvailable(at: .now) }, id: \.self) { option in
                PillButton(title: option.title, symbol: nil) { onRemind(option) }
            }
            Spacer()
            PillButton(title: "Cancel", symbol: nil) { choosingReminder = false }
        }
    }
}

struct PillButton: View {
    let title: String
    let symbol: String?
    var prominent = false
    var destructive = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(background, in: Capsule())
                .foregroundStyle(destructive && isHovered ? .red : .white)
                .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    @ViewBuilder private var label: some View {
        if let symbol { Label(title, systemImage: symbol) } else { Text(title) }
    }

    private var background: Color {
        let base = prominent ? Color.blue.opacity(0.55) : Color.white.opacity(0.1)
        return isHovered && isEnabled ? base.opacity(prominent ? 0.8 : 0.2) : base
    }
}

/// A small capsule button under the mail, e.g. "Load images".
struct SmallToggle: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

/// Makes the open message (or reply) bigger, and back.
struct SizeToggle: View {
    let isEnlarged: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isEnlarged ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(.white.opacity(0.1), in: Circle())
        }
        .buttonStyle(.plain)
        .help(isEnlarged ? "Smaller" : "Bigger, for reading")
    }
}
