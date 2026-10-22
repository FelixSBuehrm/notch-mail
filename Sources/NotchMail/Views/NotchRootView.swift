import NotchCore
import SwiftUI

/// The black shape and whatever the current mode shows inside it.
struct NotchRootView: View {
    let controller: NotchController

    private var state: NotchState { controller.state }
    private var isClosed: Bool { state.mode == .closed }

    var body: some View {
        let size = controller.contentSize
        let shape = NotchShape(
            flare: NotchLayout.flare(for: state.mode),
            bottomRadius: isClosed ? 10 : 24
        )
        // Without a hardware notch there is nothing to blend into, so the
        // closed state draws nothing; hovering the spot still opens it.
        let hidden = isClosed && !controller.geometry.hasNotch
        ZStack(alignment: .top) {
            shape.fill(.black.opacity(hidden ? 0 : 1))
            content
                .padding(.top, controller.geometry.notchSize.height + 6)
                .padding(.horizontal, NotchLayout.flare(for: state.mode) + 16)
                .padding(.bottom, 14)
            notice(width: size.width)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .shadow(color: .black.opacity(isClosed ? 0 : 0.4), radius: 14, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    /// "✓ Archived" in the black strip left of the camera, so the list doesn't move.
    @ViewBuilder private func notice(width: CGFloat) -> some View {
        if let notice = state.notice {
            let flare = NotchLayout.flare(for: state.mode)
            let notch = controller.geometry.notchSize
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .frame(width: max(0, (width - notch.width) / 2 - flare), height: notch.height)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, flare)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var content: some View {
        switch state.mode {
        case .closed:
            EmptyView()
        case .alert(let id):
            if let message = state.message(id) {
                MessageRow(message: message, style: .alert)
                    .transition(.opacity)
            }
        case .list:
            MessageListView(messages: state.unread, limit: controller.listLimit) { controller.send(.selected($0)) }
                .transition(.opacity)
        case .expanded(let id, _):
            if let message = state.message(id) {
                MessageDetailView(
                    message: message,
                    onAction: { controller.perform($0, on: message) },
                    onRemind: { controller.remind(message, $0) },
                    onReply: { controller.startReply(message) },
                    onBack: { controller.send(.backToList) },
                    isEnlarged: controller.isEnlarged,
                    onToggleSize: { controller.toggleEnlarged() },
                    onCopyCode: { controller.copyCode($0) }
                )
                .id(id)
                .transition(.opacity)
            }
        case .replying:
            if let composer = controller.composer {
                ReplyView(composer: composer, isEnlarged: controller.isEnlarged) { controller.toggleEnlarged() }
                    .transition(.opacity)
            }
        case .sending:
            if let composer = controller.composer {
                SendingView(composer: composer)
                    .transition(.opacity)
            }
        case .confirmation(let text):
            Label(text, systemImage: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .transition(.opacity)
        }
    }
}
