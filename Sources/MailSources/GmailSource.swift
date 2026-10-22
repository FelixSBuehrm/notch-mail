import Foundation
import NotchCore
import os

/// One connected mailbox the notch can read and act on.
public protocol MailSource: Sendable {
    var account: MailAccount { get }
    /// The current unread inbox (recent mail only).
    func fetchUnread() async throws -> [MailMessage]
    /// One message by ID, or nil if it's gone, read, or no longer in the inbox.
    func fetch(id: MailMessage.ID) async throws -> MailMessage?
    /// Which of these are still unread in the inbox. Cheap: labels only.
    func stillUnread(_ ids: Set<MailMessage.ID>) async throws -> Set<MailMessage.ID>
    func perform(_ action: MailAction, on id: MailMessage.ID) async throws
    /// Who a reply goes to (Reply-To wins over From), the subject and threading headers.
    func replyContext(for id: MailMessage.ID) async throws -> ReplyContext
    /// Sends a plain-text reply with a context from `replyContext(for:)`.
    func sendReply(_ context: ReplyContext, body: String, fromName: String) async throws
}

/// Gmail through the Gmail REST API.
public actor GmailSource: MailSource {
    public nonisolated let account: MailAccount
    let googleRequester: APIRequester
    private let log = Logger(subsystem: AppIdentity.bundleID, category: "gmail")
    /// Messages never change, so each is downloaded once.
    private var cache: [MailMessage.ID: MailMessage] = [:]
    /// Messages that didn't parse; skipped instead of retried every check.
    private var unreadable: Set<MailMessage.ID> = []

    static let base = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/")!
    /// Unread, in the inbox, recent: what's worth a glance from the notch.
    static let query = "in:inbox is:unread newer_than:7d"
    static let lookback: TimeInterval = 7 * 24 * 3600
    /// The most the list can be set to show.
    static let maxMessages = 50

    public init(account: MailAccount, tokens: GoogleTokenProvider, transport: any HTTPTransport) {
        self.account = account
        self.googleRequester = APIRequester(tokens: tokens, transport: transport)
    }

    public func fetchUnread() async throws -> [MailMessage] {
        var components = URLComponents(url: Self.base.appending(path: "messages"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: Self.query),
            URLQueryItem(name: "maxResults", value: String(Self.maxMessages)),
        ]
        // ":" isn't escaped by URLComponents; Gmail accepts both, tests expect the escaped form.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: ":", with: "%3A")
        struct List: Decodable {
            struct Ref: Decodable { let id: String }
            let messages: [Ref]?
        }
        let list: List = try await get(components.url!)
        let ids = (list.messages ?? []).map(\.id).filter(GmailMessage.isSafeID)

        var messages: [MailMessage] = []
        for id in ids where !unreadable.contains(id) {
            if let message = try await cachedMessage(id) { messages.append(message) }
        }
        cache = cache.filter { ids.contains($0.key) }
        unreadable = unreadable.filter { ids.contains($0) }
        return messages
    }

    /// One bad or vanished message must not block the others; network and
    /// auth errors still fail the whole check.
    private func cachedMessage(_ id: MailMessage.ID) async throws -> MailMessage? {
        if let cached = cache[id] { return cached }
        do {
            let message = try GmailParser.mailMessage(from: try await get(messageURL(id, format: "full")), account: account)
            cache[id] = message
            return message
        } catch MailSourceError.http(status: 404, _) {
            return nil  // archived or deleted between the list and this call
        } catch let error as MailSourceError {
            guard case .invalidResponse = error else { throw error }
            log.error("Skipping a message that didn't parse: \(error.localizedDescription, privacy: .private)")
            unreadable.insert(id)
            return nil
        }
    }

    public func fetch(id: MailMessage.ID) async throws -> MailMessage? {
        guard GmailMessage.isSafeID(id) else { return nil }
        do {
            let raw: GmailMessage = try await get(messageURL(id, format: "full"))
            guard raw.isUnreadInInbox else { return nil }
            return try GmailParser.mailMessage(from: raw, account: account)
        } catch MailSourceError.http(status: 404, _) {
            return nil
        }
    }

    public func stillUnread(_ ids: Set<MailMessage.ID>) async throws -> Set<MailMessage.ID> {
        var unread: Set<MailMessage.ID> = []
        let oldest = Date().addingTimeInterval(-Self.lookback)
        for id in ids.sorted() where GmailMessage.isSafeID(id) {
            do {
                let raw: GmailMessage = try await get(messageURL(id, format: "minimal"))
                // Older than the list looks back counts as gone, so it isn't re-checked forever.
                let isRecent = raw.internalDate.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1_000) >= oldest } ?? true
                if raw.isUnreadInInbox, isRecent { unread.insert(id) }
            } catch MailSourceError.http(status: 404, _) {
                continue  // deleted
            }
        }
        return unread
    }

    public func perform(_ action: MailAction, on id: MailMessage.ID) async throws {
        guard GmailMessage.isSafeID(id) else { throw MailSourceError.invalidResponse("Unexpected message ID") }
        let url = Self.base.appending(path: "messages/\(id)")
        switch action {
        case .archive:
            try await post(url.appending(path: "modify"), json: #"{"removeLabelIds":["INBOX"]}"#)
        case .markRead:
            try await post(url.appending(path: "modify"), json: #"{"removeLabelIds":["UNREAD"]}"#)
        case .delete:
            // Trash, not permanent delete: recoverable for 30 days.
            try await post(url.appending(path: "trash"), json: nil)
        }
        cache[id] = nil
    }

    private func messageURL(_ id: String, format: String) -> URL {
        var components = URLComponents(url: Self.base.appending(path: "messages/\(id)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "format", value: format)]
        return components.url!
    }

    private func get<T: Decodable & Sendable>(_ url: URL) async throws -> T {
        try await googleRequester.get(url, what: url.lastPathComponent)
    }

    private func post(_ url: URL, json: String?) async throws {
        _ = try await googleRequester.post(url, json: json.map { Data($0.utf8) })
    }
}
