import NotchCore
import SwiftUI

/// Recent unread mail across all accounts, or "Inbox zero".
struct MessageListView: View {
    let messages: [MailMessage]
    /// How many the list shows; the notch stays five rows tall and scrolls.
    let limit: Int
    let onSelect: (MailMessage.ID) -> Void

    var body: some View {
        if messages.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Text("Inbox zero")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages.prefix(limit)) { message in
                        ListRowButton(message: message) { onSelect(message.id) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct ListRowButton: View {
    let message: MailMessage
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            MessageRow(message: message, style: .list)
                .padding(.horizontal, 8)
                .frame(height: NotchLayout.listRowHeight)
                .background(.white.opacity(isHovered ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
