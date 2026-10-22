import NotchCore
import SwiftUI

/// Sender, subject and preview on one compact row. Used by the alert and the list.
struct MessageRow: View {
    enum Style { case alert, list }

    let message: MailMessage
    let style: Style

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: message.senderName, key: message.senderAddress, size: style == .alert ? 38 : 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(message.senderName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    AccountBadge(account: message.account)
                    Spacer(minLength: 4)
                    Text(Formatting.shortAge(from: message.receivedAt, to: .now))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(message.subject)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if let code = message.loginCode {
                    Label {
                        Text(Formatting.spacedCode(code))
                            .font(.system(size: style == .alert ? 17 : 13, weight: .bold, design: .monospaced))
                    } icon: {
                        Image(systemName: "key.fill").font(.system(size: 10))
                    }
                    .foregroundStyle(Color(red: 0.55, green: 0.85, blue: 0.65))
                } else {
                    Text(Formatting.preview(message.body, limit: 90))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
    }
}

/// "Work" / "Private" tag so a combined stream stays readable.
struct AccountBadge: View {
    let account: MailAccount

    var body: some View {
        Text(account.name)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Palette.color(for: account.id).opacity(0.28), in: Capsule())
            .foregroundStyle(Palette.color(for: account.id))
    }
}

struct Avatar: View {
    let name: String
    let key: String
    let size: CGFloat

    var body: some View {
        Text(Formatting.initials(name))
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Palette.color(for: key).gradient, in: Circle())
    }
}

enum Palette {
    static let colors: [Color] = [
        Color(red: 0.36, green: 0.55, blue: 0.95),
        Color(red: 0.93, green: 0.48, blue: 0.36),
        Color(red: 0.35, green: 0.75, blue: 0.55),
        Color(red: 0.72, green: 0.48, blue: 0.92),
        Color(red: 0.95, green: 0.70, blue: 0.30),
        Color(red: 0.30, green: 0.72, blue: 0.82),
    ]

    static func color(for key: String) -> Color {
        colors[Formatting.paletteIndex(for: key, count: colors.count)]
    }
}
