import Foundation
import MailSources
import NotchCore

/// Drafts with Claude and sends through the message's mailbox.
@MainActor
protocol ReplyBackend {
    /// Who the reply really goes to, looked up before anything can be sent.
    func context(for message: MailMessage) async throws -> ReplyContext
    func draft(_ request: DraftRequest, progress: @escaping @Sendable (String) -> Void) async throws -> String
    func send(_ body: String, context: ReplyContext, as name: String) async throws
}

struct LiveReplyBackend: ReplyBackend {
    let source: any MailSource
    let tools: any DraftTools
    let transport: any HTTPTransport

    func context(for message: MailMessage) async throws -> ReplyContext {
        try await source.replyContext(for: message.id)
    }

    func draft(_ request: DraftRequest, progress: @escaping @Sendable (String) -> Void) async throws -> String {
        let client = ClaudeClient(credentials: try AccountStore.claudeCredentials(), transport: transport)
        return try await ReplyDrafter(client: client, tools: tools).draft(request, progress: progress)
    }

    func send(_ body: String, context: ReplyContext, as name: String) async throws {
        try await source.sendReply(context, body: body, fromName: name)
    }
}

/// Demo mail: a canned draft, and "sending" goes nowhere. Never touches the Keychain or network.
struct DemoReplyBackend: ReplyBackend {
    func context(for message: MailMessage) async throws -> ReplyContext {
        ReplyContext(threadID: nil, toName: message.senderName, toAddress: message.senderAddress,
                     subject: "Re: \(message.subject)", inReplyTo: nil, references: [])
    }

    func draft(_ request: DraftRequest, progress: @escaping @Sendable (String) -> Void) async throws -> String {
        progress("Searching Gmail: \(request.message.subject.prefix(30))")
        try await Task.sleep(for: .seconds(1.2))
        let first = request.myName.split(separator: " ").first.map(String.init) ?? request.myName
        let sender = request.message.senderName.split(separator: " ").first.map(String.init) ?? ""
        let gist = request.instruction.isEmpty ? "Thanks, that works for me." : request.instruction
        return "Hi \(sender),\n\n\(gist)\n\nBest,\n\(first)"
    }

    func send(_ body: String, context: ReplyContext, as name: String) async throws {
        try await Task.sleep(for: .seconds(0.6))
    }
}

/// A real message whose account is gone (disconnected meanwhile): nothing can be sent.
struct UnavailableReplyBackend: ReplyBackend {
    struct NotConnected: LocalizedError {
        var errorDescription: String? { "This account isn't connected any more" }
    }

    func context(for message: MailMessage) async throws -> ReplyContext { throw NotConnected() }
    func draft(_ request: DraftRequest, progress: @escaping @Sendable (String) -> Void) async throws -> String { throw NotConnected() }
    func send(_ body: String, context: ReplyContext, as name: String) async throws { throw NotConnected() }
}
