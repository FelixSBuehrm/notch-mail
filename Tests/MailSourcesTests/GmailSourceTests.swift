import Foundation
import NotchCore
import Testing
@testable import MailSources

@Suite("Gmail source")
struct GmailSourceTests {
    let account = MailAccount(id: "gmail", name: "Work", address: "me@example.com")
    let credentials = GoogleClientCredentials(clientID: "id", clientSecret: "secret")
    let tokenJSON = #"{"access_token":"tok","expires_in":3600}"#

    private func message(_ id: String) -> String {
        """
        {"id":"\(id)","internalDate":"1700000000000","labelIds":["INBOX","UNREAD"],
         "payload":{"mimeType":"text/plain","headers":[{"name":"Subject","value":"S \(id)"}],
                    "body":{"data":"\(base64URL("body"))"}}}
        """
    }

    private func source(_ replies: [StubTransport.Reply]) -> (GmailSource, StubTransport) {
        let transport = StubTransport(replies)
        let tokens = GoogleTokenProvider(credentials: credentials, refreshToken: "1//r", transport: transport)
        return (GmailSource(account: account, tokens: tokens, transport: transport), transport)
    }

    @Test func fetchesUnreadInboxAndCachesMessages() async throws {
        let (gmail, transport) = source([
            .json(tokenJSON),
            .json(#"{"messages":[{"id":"a"},{"id":"b"}]}"#),
            .json(message("a")), .json(message("b")),
            .json(#"{"messages":[{"id":"a"}]}"#),  // second check: only the list call
        ])

        let first = try await gmail.fetchUnread()
        let second = try await gmail.fetchUnread()

        #expect(Set(first.map(\.id)) == ["a", "b"])
        #expect(second.map(\.id) == ["a"])
        let urls = await transport.requests.map { $0.url!.absoluteString }
        #expect(urls.count == 5)
        #expect(urls[1].contains("messages?"))
        #expect(urls[1].contains("in%3Ainbox"))
        #expect(urls[1].contains("is%3Aunread"))
        let auth = await transport.requests[1].value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Bearer tok")
    }

    @Test func emptyInboxHasNoMessagesKey() async throws {
        let (gmail, _) = source([.json(tokenJSON), .json(#"{"resultSizeEstimate":0}"#)])

        #expect(try await gmail.fetchUnread().isEmpty)
    }

    @Test(arguments: [
        (MailAction.archive, "/modify", #"{"removeLabelIds":["INBOX"]}"#),
        (MailAction.markRead, "/modify", #"{"removeLabelIds":["UNREAD"]}"#),
        (MailAction.delete, "/trash", nil),
    ] as [(MailAction, String, String?)])
    func actionsMapToGmailCalls(action: MailAction, path: String, body: String?) async throws {
        let (gmail, transport) = source([.json(tokenJSON), .json("{}")])

        try await gmail.perform(action, on: "m1")

        let request = try #require(await transport.requests.last)
        #expect(request.httpMethod == "POST")
        #expect(request.url!.path.hasSuffix("/messages/m1\(path)"))
        if let body {
            #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == body)
        }
    }

    @Test func expiredAccessTokenIsRefreshedOnceAndRetried() async throws {
        let (gmail, transport) = source([
            .json(tokenJSON),
            .json(#"{"error":{"message":"Invalid Credentials"}}"#, status: 401),
            .json(#"{"access_token":"tok2","expires_in":3600}"#),
            .json("{}"),
        ])

        try await gmail.perform(.markRead, on: "m1")

        let auth = await transport.requests.last?.value(forHTTPHeaderField: "Authorization")
        #expect(auth == "Bearer tok2")
    }

    @Test func serverErrorsSurfaceWithStatusAndMessage() async throws {
        let (gmail, _) = source([.json(tokenJSON), .json(#"{"error":{"message":"Backend Error"}}"#, status: 503)])

        await #expect(throws: MailSourceError.http(status: 503, message: "Backend Error")) {
            try await gmail.perform(.archive, on: "m1")
        }
    }

    @Test func oneBrokenOrVanishedMessageDoesNotBlockTheRest() async throws {
        let (gmail, _) = source([
            .json(tokenJSON),
            .json(#"{"messages":[{"id":"gone"},{"id":"broken"},{"id":"ok"}]}"#),
            .json(#"{"error":{"message":"Not Found"}}"#, status: 404),
            .json(#"{"id":"broken","payload":{}}"#),  // no date
            .json(message("ok")),
        ])

        let messages = try await gmail.fetchUnread()

        #expect(messages.map(\.id) == ["ok"])
    }

    @Test func stillUnreadAsksForLabelsOnly() async throws {
        let (gmail, transport) = source([
            .json(tokenJSON),
            .json(#"{"id":"a","labelIds":["INBOX","UNREAD"]}"#),
            .json(#"{"id":"b","labelIds":["INBOX"]}"#),
            .json(#"{"error":{"message":"Not Found"}}"#, status: 404),
        ])

        let unread = try await gmail.stillUnread(["a", "b", "c"])

        #expect(unread == ["a"])
        let urls = await transport.requests.dropFirst().map { $0.url!.absoluteString }
        #expect(urls.allSatisfy { $0.contains("format=minimal") })
    }

    @Test func readMailIsNotBroughtBackByAReminder() async throws {
        let read = #"{"id":"a","internalDate":"1700000000000","labelIds":["INBOX"],"payload":{"mimeType":"text/plain","headers":[]}}"#
        let (gmail, _) = source([.json(tokenJSON), .json(read)])

        #expect(try await gmail.fetch(id: "a") == nil)
    }

    @Test func fetchingAReminderReturnsNilOnceItLeftTheInbox() async throws {
        let archived = #"{"id":"a","internalDate":"1700000000000","labelIds":["UNREAD"],"payload":{"mimeType":"text/plain","headers":[]}}"#
        let (gmail, _) = source([.json(tokenJSON), .json(archived)])

        #expect(try await gmail.fetch(id: "a") == nil)
    }

    @Test func deletedReminderReturnsNil() async throws {
        let (gmail, _) = source([.json(tokenJSON), .json(#"{"error":{"message":"Not Found"}}"#, status: 404)])

        #expect(try await gmail.fetch(id: "gone") == nil)
    }
}
