import Foundation
import NotchCore

/// Replying, and the read-only lookups Claude uses while drafting.
extension GmailSource {
    static let searchLimit = 8
    static let readLimit = 12_000

    public func sendReply(_ context: ReplyContext, body: String, fromName: String) async throws {
        let raw = try ReplyMIME.message(context: context, fromName: fromName, fromAddress: account.address, body: body)
        var payload: [String: String] = ["raw": Data(raw.utf8).base64URLEncodedString()]
        if let thread = context.threadID, GmailMessage.isSafeID(thread) { payload["threadId"] = thread }
        _ = try await googleRequester.post(Self.base.appending(path: "messages/send"), json: try JSONEncoder().encode(payload))
    }

    public func replyContext(for id: MailMessage.ID) async throws -> ReplyContext {
        let raw = try await metadata(id, headers: ["From", "Reply-To", "Subject", "Message-ID", "References"])
        var headers: [String: String] = [:]
        for header in raw.payload?.headers ?? [] where headers[header.name.lowercased()] == nil {
            headers[header.name.lowercased()] = header.value
        }
        return try ReplyContext.from(headers: headers, threadID: raw.threadId)
    }

    /// Gmail search syntax, newest first: one line per hit.
    public func search(_ query: String) async throws -> String {
        var components = URLComponents(url: Self.base.appending(path: "messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "maxResults", value: String(Self.searchLimit)),
        ]
        // URLComponents leaves "+" alone, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        struct List: Decodable {
            struct Ref: Decodable { let id: String }
            let messages: [Ref]?
        }
        let list: List = try await googleRequester.get(components.url!, what: "search")
        let ids = (list.messages ?? []).map(\.id).filter(GmailMessage.isSafeID)
        guard !ids.isEmpty else { return "No messages found." }
        var lines: [String] = []
        for id in ids {
            let raw = try await metadata(id, headers: ["From", "Subject", "Date"])
            let headers = raw.payload?.headers ?? []
            func value(_ name: String) -> String {
                headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
            }
            let snippet = HTMLText.cleanDisplayText(HTMLText.decodeEntities(raw.snippet ?? ""))
            lines.append("id: \(id) | from: \(value("From")) | date: \(value("Date")) | subject: \(value("Subject")) | \(snippet)")
        }
        return lines.joined(separator: "\n")
    }

    /// Any message (read or not), as text.
    public func readMessage(_ id: String) async throws -> String {
        guard GmailMessage.isSafeID(id) else { throw MailSourceError.invalidResponse("Unexpected message ID") }
        var components = URLComponents(url: Self.base.appending(path: "messages/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "full")]
        let raw: GmailMessage = try await googleRequester.get(components.url!, what: "message")
        let message = try GmailParser.mailMessage(from: raw, account: account)
        let text = """
        From: \(message.senderName) <\(message.senderAddress)>
        Date: \(message.receivedAt.formatted(.iso8601))
        Subject: \(message.subject)

        \(message.body)
        """
        return text.count > Self.readLimit ? String(text.prefix(Self.readLimit)) + "\n[cut]" : text
    }

    private func metadata(_ id: String, headers: [String]) async throws -> GmailMessage {
        guard GmailMessage.isSafeID(id) else { throw MailSourceError.invalidResponse("Unexpected message ID") }
        var components = URLComponents(url: Self.base.appending(path: "messages/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: "metadata")]
            + headers.map { URLQueryItem(name: "metadataHeaders", value: $0) }
        return try await googleRequester.get(components.url!, what: "message")
    }
}
