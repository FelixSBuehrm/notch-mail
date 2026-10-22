import NotchCore
import SwiftUI

/// The text of a message with clickable links. Earlier messages of the thread
/// stay folded away until asked for.
struct MessageBodyView: View {
    let content: MailBody
    var fontSize: CGFloat = 13.5

    @State private var showsQuoted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            styled(content.text, opacity: 0.85)
            if let quoted = content.quoted {
                Button { showsQuoted.toggle() } label: {
                    Label(showsQuoted ? "Hide earlier messages" : "Show earlier messages",
                          systemImage: showsQuoted ? "chevron.up" : "ellipsis")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                if showsQuoted { styled(quoted, opacity: 0.55) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            Browser.open(url)
            return .handled
        })
    }

    private func styled(_ text: String, opacity: Double) -> some View {
        Text(MailLinks.attributed(text))
            .font(.system(size: fontSize))
            .lineSpacing(fontSize * 0.3)
            .foregroundStyle(.white.opacity(opacity))
            .tint(Color(red: 0.55, green: 0.75, blue: 1))
            .textSelection(.enabled)
    }
}
