import Foundation
import NotchCore

/// Outlook.com / Hotmail through Microsoft Graph.
public actor OutlookSource: MailSource {
    public nonisolated let account: MailAccount
    let graph: APIRequester
    private var cache: [MailMessage.ID: MailMessage] = [:]
    /// Messages that didn't parse; skipped instead of failing every check.
    private var unreadable: Set<MailMessage.ID> = []
    private var inboxID: String?

    static let base = URL(string: "https://graph.microsoft.com/v1.0/me/")!
    static let maxMessages = 50
    static let lookback: TimeInterval = 7 * 24 * 3600
    static let searchLimit = 8
    static let readLimit = 12_000
    static let messageFields = "id,subject,from,receivedDateTime,isRead,body,bodyPreview"

    public init(account: MailAccount, tokens: MicrosoftTokenProvider, transport: any HTTPTransport) {
        self.account = account
        // Immutable IDs survive moves, so reminders still find their message.
        self.graph = APIRequester(tokens: tokens, transport: transport, headers: ["Prefer": #"IdType="ImmutableId""#])
    }

    /// The signed-in account's address.
    public static func address(tokens: MicrosoftTokenProvider, transport: any HTTPTransport) async throws -> String {
        struct Me: Decodable {
            let mail: String?
            let userPrincipalName: String?
        }
        let me: Me = try await APIRequester(tokens: tokens, transport: transport)
            .get(url("me", base: URL(string: "https://graph.microsoft.com/v1.0/")!, query: ["$select": "mail,userPrincipalName"]), what: "account")
        guard let address = (me.mail ?? me.userPrincipalName)?.lowercased(), address.contains("@") else {
            throw MailSourceError.signInFailed("Microsoft didn't say which account this is")
        }
        return address
    }

    // MARK: - MailSource

    public func fetchUnread() async throws -> [MailMessage] {
        let since = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Self.lookback))
        struct List: Decodable {
            struct Ref: Decodable { let id: String }
            let value: [Ref]
        }
        let list: List = try await graph.get(Self.url("mailFolders/inbox/messages", query: [
            "$filter": "receivedDateTime ge \(since) and isRead eq false",
            "$orderby": "receivedDateTime desc",
            "$top": String(Self.maxMessages),
            "$select": "id",
        ]), what: "inbox")
        let ids = list.value.map(\.id).filter(Self.isSafeID)
        var messages: [MailMessage] = []
        for id in ids where !unreadable.contains(id) {
            if let cached = cache[id] {
                messages.append(cached)
                continue
            }
            do {
                let message = try await message(id)
                cache[id] = message
                messages.append(message)
            } catch MailSourceError.http(status: 404, _) {
                continue
            } catch let error as MailSourceError {
                // One odd item must not block the inbox; network and auth errors still fail the check.
                guard case .invalidResponse = error else { throw error }
                unreadable.insert(id)
            }
        }
        cache = cache.filter { ids.contains($0.key) }
        unreadable = unreadable.filter { ids.contains($0) }
        return messages
    }

    public func fetch(id: MailMessage.ID) async throws -> MailMessage? {
        guard Self.isSafeID(id) else { return nil }
        do {
            let raw: GraphMessage = try await graph.get(Self.url("messages/\(id)", query: ["$select": Self.messageFields + ",parentFolderId"]), what: "message")
            guard raw.isRead == false, raw.parentFolderId == (try await inbox()) else { return nil }
            return try raw.mailMessage(account: account)
        } catch MailSourceError.http(status: 404, _) {
            return nil
        }
    }

    public func stillUnread(_ ids: Set<MailMessage.ID>) async throws -> Set<MailMessage.ID> {
        let inbox = try await inbox()
        let oldest = Date().addingTimeInterval(-Self.lookback)
        var unread: Set<MailMessage.ID> = []
        for id in ids.sorted() where Self.isSafeID(id) {
            do {
                let raw: GraphMessage = try await graph.get(Self.url("messages/\(id)", query: ["$select": "isRead,parentFolderId,receivedDateTime"]), what: "message")
                // Older than the list looks back counts as gone, so it isn't re-checked forever.
                let isRecent = raw.receivedDateTime.flatMap(GraphMessage.parseDate).map { $0 >= oldest } ?? true
                if raw.isRead == false, raw.parentFolderId == inbox, isRecent { unread.insert(id) }
            } catch MailSourceError.http(status: 404, _) {
                continue
            }
        }
        return unread
    }

    public func perform(_ action: MailAction, on id: MailMessage.ID) async throws {
        guard Self.isSafeID(id) else { throw MailSourceError.invalidResponse("Unexpected message ID") }
        switch action {
        case .markRead:
            _ = try await graph.post(Self.url("messages/\(id)"), json: Data(#"{"isRead":true}"#.utf8), method: "PATCH")
        case .archive:
            _ = try await graph.post(Self.url("messages/\(id)/move"), json: Data(#"{"destinationId":"archive"}"#.utf8))
        case .delete:
            // Deleted Items, not gone for good.
            _ = try await graph.post(Self.url("messages/\(id)/move"), json: Data(#"{"destinationId":"deleteditems"}"#.utf8))
        }
        cache[id] = nil
    }

    public func replyContext(for id: MailMessage.ID) async throws -> ReplyContext {
        guard Self.isSafeID(id) else { throw MailSourceError.invalidResponse("Unexpected message ID") }
        let raw: GraphMessage = try await graph.get(Self.url("messages/\(id)", query: [
            "$select": "from,replyTo,subject,internetMessageId,conversationId",
        ]), what: "message")
        let from = raw.from?.emailAddress
        let target = raw.replyTo?.first?.emailAddress ?? from
        guard let address = target?.address?.trimmingCharacters(in: .whitespaces), ReplyMIME.isValidAddress(address) else {
            throw MailSourceError.invalidResponse("The original has no address to reply to")
        }
        let fromAddress = from?.address?.lowercased()
        return ReplyContext(
            threadID: raw.conversationId,
            toName: HTMLText.cleanDisplayText(target?.name ?? ""),
            toAddress: address,
            subject: ReplyContext.replySubject(raw.subject ?? ""),
            inReplyTo: raw.internetMessageId.flatMap { ReplyMIME.messageIDs($0).first },
            references: [],
            redirectedFrom: fromAddress == nil || fromAddress == address.lowercased() ? nil : from?.address,
            originalID: id
        )
    }

    /// Graph's own reply keeps the thread; the draft gets our text and the recipient that was shown.
    public func sendReply(_ context: ReplyContext, body: String, fromName: String) async throws {
        guard let original = context.originalID, Self.isSafeID(original) else {
            throw MailSourceError.invalidResponse("Unexpected message ID")
        }
        struct Draft: Decodable { let id: String }
        let draft = try JSONDecoder().decode(Draft.self, from: try await graph.post(Self.url("messages/\(original)/createReply"), json: nil))
        guard Self.isSafeID(draft.id) else { throw MailSourceError.invalidResponse("Unexpected draft ID") }
        let patch: JSONValue = .object([
            "body": .object(["contentType": .string("Text"), "content": .string(body)]),
            "toRecipients": .array([.object(["emailAddress": .object([
                "address": .string(context.toAddress), "name": .string(context.toName),
            ])])]),
        ])
        do {
            _ = try await graph.post(Self.url("messages/\(draft.id)"), json: try JSONEncoder().encode(patch), method: "PATCH")
        } catch {
            _ = try? await graph.post(Self.url("messages/\(draft.id)"), json: nil, method: "DELETE")
            throw error
        }
        do {
            _ = try await graph.post(Self.url("messages/\(draft.id)/send"), json: nil)
        } catch MailSourceError.http(let status, let message) where (400..<500).contains(status) {
            // Refused outright: nothing went out, so the draft can go.
            _ = try? await graph.post(Self.url("messages/\(draft.id)"), json: nil, method: "DELETE")
            throw MailSourceError.http(status: status, message: message)
        } catch {
            // Timeout or server error: it may have gone out. Keep the draft and say so.
            throw URLError(.timedOut)
        }
    }

    // MARK: - Lookups for Claude

    public func search(_ query: String) async throws -> String {
        let clean = query.replacingOccurrences(of: "\"", with: " ")
        struct List: Decodable { let value: [GraphMessage] }
        let list: List = try await graph.get(Self.url("messages", query: [
            "$search": "\"\(clean)\"", "$top": String(Self.searchLimit),
            "$select": "id,subject,from,receivedDateTime,bodyPreview",
        ]), what: "search")
        let hits = list.value.filter { Self.isSafeID($0.id) }
        guard !hits.isEmpty else { return "No messages found." }
        return hits.map { raw in
            "id: \(raw.id) | from: \(raw.from?.emailAddress.header ?? "?") | date: \(raw.receivedDateTime ?? "?") | subject: \(raw.subject ?? "") | \(HTMLText.cleanDisplayText(raw.bodyPreview ?? ""))"
        }.joined(separator: "\n")
    }

    public func readMessage(_ id: String) async throws -> String {
        guard Self.isSafeID(id) else { throw MailSourceError.invalidResponse("Unexpected message ID") }
        let message = try await message(id)
        let text = "From: \(message.senderName) <\(message.senderAddress)>\nDate: \(message.receivedAt.formatted(.iso8601))\nSubject: \(message.subject)\n\n\(message.body)"
        return text.count > Self.readLimit ? String(text.prefix(Self.readLimit)) + "\n[cut]" : text
    }

    // MARK: - Helpers

    private func message(_ id: String) async throws -> MailMessage {
        let raw: GraphMessage = try await graph.get(Self.url("messages/\(id)", query: ["$select": Self.messageFields]), what: "message")
        return try raw.mailMessage(account: account)
    }

    private func inbox() async throws -> String {
        if let inboxID { return inboxID }
        struct Folder: Decodable { let id: String }
        let folder: Folder = try await graph.get(Self.url("mailFolders/inbox", query: ["$select": "id"]), what: "inbox")
        inboxID = folder.id
        return folder.id
    }

    static func url(_ path: String, base: URL = base, query: [String: String] = [:]) -> URL {
        var components = URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url!
    }

    /// Graph IDs are long URL-safe base64. Anything else never goes into a URL.
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 512 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-_=".contains($0)) }
    }
}

/// The parts of a Graph message the notch needs.
struct GraphMessage: Decodable {
    struct Address: Decodable {
        let name: String?
        let address: String?

        var header: String {
            let clean = HTMLText.cleanDisplayText(name ?? "").replacingOccurrences(of: "\"", with: "'")
            return clean.isEmpty ? (address ?? "") : "\"\(clean)\" <\(address ?? "")>"
        }
    }

    struct Recipient: Decodable { let emailAddress: Address }

    struct Body: Decodable {
        let contentType: String?
        let content: String?
    }

    let id: String
    let subject: String?
    let from: Recipient?
    let replyTo: [Recipient]?
    let receivedDateTime: String?
    let isRead: Bool?
    let body: Body?
    let bodyPreview: String?
    let parentFolderId: String?
    let internetMessageId: String?
    let conversationId: String?

    func mailMessage(account: MailAccount) throws -> MailMessage {
        guard OutlookSource.isSafeID(id) else { throw MailSourceError.invalidResponse("Message with an unexpected ID") }
        guard let date = receivedDateTime.flatMap(Self.parseDate) else {
            throw MailSourceError.invalidResponse("Message without a date")
        }
        let sender = AddressParser.parse(from?.emailAddress.header ?? "")
        let content = String((body?.content ?? "").prefix(HTMLText.maxInput))
        let isHTML = body?.contentType?.lowercased() == "html"
        var text = isHTML ? HTMLText.plain(content) : HTMLText.cleanDisplayText(content.replacingOccurrences(of: "\r\n", with: "\n"))
        if text.isEmpty { text = HTMLText.cleanDisplayText(bodyPreview ?? "") }
        let subject = HTMLText.cleanDisplayText(self.subject ?? "").trimmingCharacters(in: .whitespaces)
        return MailMessage(
            id: id, account: account, senderName: sender.name, senderAddress: sender.address,
            subject: subject.isEmpty ? "(no subject)" : subject,
            body: text.count > GmailParser.maxBodyLength ? String(text.prefix(GmailParser.maxBodyLength)) + "…" : text,
            html: isHTML && content.utf8.count <= GmailParser.maxHTMLLength && !content.isEmpty ? content : nil,
            receivedAt: date
        )
    }

    static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

/// Outlook lookups for Claude while it drafts. Read-only.
public struct OutlookDraftTools: DraftTools {
    private let outlook: OutlookSource

    public init(outlook: OutlookSource) {
        self.outlook = outlook
    }

    public var definitions: [ClaudeTool] {
        [
            Self.tool("search_mail", "Search this Outlook mailbox (sender, subject and text). Returns up to 8 messages with id, sender, date, subject and a preview.",
                      field: "query", about: "Words to search for"),
            Self.tool("read_email", "Read one email from this mailbox in full, by the id from search_mail.", field: "id", about: "Message id"),
        ]
    }

    public func run(_ call: ClaudeToolUse) async -> DraftToolResult {
        guard let value = call.input["query"]?.stringValue ?? call.input["id"]?.stringValue else {
            return DraftToolResult(text: "Missing input", isError: true)
        }
        do {
            switch call.name {
            case "search_mail": return DraftToolResult(text: try await outlook.search(value))
            case "read_email": return DraftToolResult(text: try await outlook.readMessage(value))
            default: return DraftToolResult(text: "Unknown tool \(call.name)", isError: true)
            }
        } catch {
            return DraftToolResult(text: "Failed: \(error.localizedDescription)", isError: true)
        }
    }

    public func describe(_ call: ClaudeToolUse) -> String {
        call.name == "search_mail" ? "Searching Outlook: \(call.input["query"]?.stringValue?.prefix(40) ?? "")" : "Reading an email"
    }

    static func tool(_ name: String, _ description: String, field: String, about: String) -> ClaudeTool {
        ClaudeTool(name: name, description: description, inputSchema: .object([
            "type": .string("object"),
            "properties": .object([field: .object(["type": .string("string"), "description": .string(about)])]),
            "required": .array([.string(field)]),
            "additionalProperties": .bool(false),
        ]))
    }
}
