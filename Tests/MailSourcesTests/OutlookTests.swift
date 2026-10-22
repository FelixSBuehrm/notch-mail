import Foundation
import NotchCore
import Testing
@testable import MailSources

@Suite("Microsoft sign-in")
struct MicrosoftAuthTests {
    private let deviceCode = #"{"device_code":"dc1","user_code":"ABCD-1234","verification_uri":"https://www.microsoft.com/link","expires_in":900,"interval":5}"#
    private let tokens = #"{"access_token":"at","refresh_token":"rt1","expires_in":3600}"#

    @Test func deviceCodeFlowWaitsUntilAllowed() async throws {
        let transport = StubTransport([
            .json(deviceCode),
            .json(#"{"error":"authorization_pending"}"#, status: 400),
            .json(#"{"error":"slow_down"}"#, status: 400),
            .json(tokens),
        ])
        let shown = LockedLines()
        let waits = LockedLines()

        let result = try await MicrosoftAuth.signIn(
            clientID: "client", transport: transport,
            show: { shown.append($0.userCode) },
            sleep: { waits.append(String(Int($0))) }
        )

        #expect(result.refreshToken == "rt1")
        #expect(shown.lines == ["ABCD-1234"])
        #expect(waits.lines == ["5", "5", "10"])  // slow_down adds 5 s
        let requests = await transport.requests
        #expect(requests[0].url?.absoluteString == "https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode")
        #expect(formFields(requests[0])["scope"]?.contains("Mail.Send") == true)
        #expect(formFields(requests[1])["grant_type"] == "urn:ietf:params:oauth:grant-type:device_code")
    }

    @Test func declinedSignInFails() async {
        let transport = StubTransport([.json(deviceCode), .json(#"{"error":"authorization_declined"}"#, status: 400)])

        await #expect(throws: MailSourceError.signInFailed("Access was denied")) {
            try await MicrosoftAuth.signIn(clientID: "c", transport: transport, show: { _ in }, sleep: { _ in })
        }
    }

    @Test(arguments: ["https://evil.example.com/link", "https://evilmicrosoft.com/link", "http://www.microsoft.com/link"])
    func verificationPageMustBeMicrosofts(url: String) {
        let fake = #"{"device_code":"d","user_code":"X","verification_uri":"\#(url)","expires_in":900}"#

        #expect(throws: MailSourceError.self) { try MicrosoftAuth.parseDeviceCode(Data(fake.utf8), now: .now) }
    }

    @Test func networkBlipWhileWaitingDoesNotAbortSignIn() async throws {
        let transport = FlakyOnceTransport(replies: [.json(deviceCode), .json(tokens)])

        let result = try await MicrosoftAuth.signIn(clientID: "c", transport: transport, show: { _ in }, sleep: { _ in })

        #expect(result.accessToken == "at")
    }

    @Test func renewalKeepsTheNewRefreshToken() async throws {
        let transport = StubTransport([.json(#"{"access_token":"at2","refresh_token":"rt2","expires_in":3600}"#)])
        let saved = LockedLines()
        let provider = MicrosoftTokenProvider(clientID: "c", refreshToken: "rt1", transport: transport, persist: { saved.append($0) })

        #expect(try await provider.accessToken() == "at2")
        #expect(saved.lines == ["rt2"])
        #expect(formFields(try #require(await transport.requests.first))["refresh_token"] == "rt1")
    }

    @Test func revokedSignInIsReportedAsSuch() async {
        let transport = StubTransport([.json(#"{"error":"invalid_grant","error_description":"expired"}"#, status: 400)])
        let provider = MicrosoftTokenProvider(clientID: "c", refreshToken: "rt1", transport: transport, persist: { _ in })

        await #expect(throws: MailSourceError.authorizationRevoked) { try await provider.accessToken() }
    }
}

@Suite("Outlook source")
struct OutlookSourceTests {
    let account = MailAccount(id: "outlook:alex@example.org", name: "Hotmail", address: "alex@example.org")
    let refresh = #"{"access_token":"at","refresh_token":"rt","expires_in":3600}"#

    private func source(_ replies: [StubTransport.Reply]) -> (OutlookSource, StubTransport) {
        let transport = StubTransport([.json(refresh)] + replies)
        let tokens = MicrosoftTokenProvider(clientID: "c", refreshToken: "rt", transport: transport, persist: { _ in })
        return (OutlookSource(account: account, tokens: tokens, transport: transport), transport)
    }

    private func message(_ id: String, html: Bool = true) -> String {
        let body = html ? #"{"contentType":"html","content":"<p>Your verification code is <b>482913</b></p>"}"#
                        : #"{"contentType":"text","content":"Plain\r\nbody"}"#
        return #"{"id":"\#(id)","subject":"Sign in","receivedDateTime":"2026-10-22T20:00:00Z","isRead":false,"from":{"emailAddress":{"name":"Contoso","address":"no-reply@example.com"}},"body":\#(body)}"#
    }

    @Test func fetchesUnreadInboxAndCachesBodies() async throws {
        let (outlook, transport) = source([
            .json(#"{"value":[{"id":"AAMk-1="},{"id":"bad/id"}]}"#),
            .json(message("AAMk-1=")),
            .json(#"{"value":[{"id":"AAMk-1="}]}"#),
        ])

        let first = try await outlook.fetchUnread()
        let second = try await outlook.fetchUnread()

        #expect(first.map(\.id) == ["AAMk-1="])
        #expect(first.first?.body == "Your verification code is 482913")
        #expect(first.first?.html?.contains("<b>482913</b>") == true)
        #expect(first.first?.loginCode == "482913")
        #expect(second.map(\.id) == ["AAMk-1="])
        let requests = await transport.requests
        #expect(requests.count == 4)  // token, list, one message, list
        let list = try #require(requests[1].url).query(percentEncoded: false) ?? ""
        #expect(list.contains("isRead eq false"))
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer at")
    }

    @Test func actionsUseGraphMoveAndPatch() async throws {
        let (outlook, transport) = source([.json("{}"), .json("{}"), .json("{}")])

        try await outlook.perform(.markRead, on: "m1")
        try await outlook.perform(.archive, on: "m1")
        try await outlook.perform(.delete, on: "m1")

        let requests = Array(await transport.requests.dropFirst())
        #expect(requests.map { $0.httpMethod ?? "" } == ["PATCH", "POST", "POST"])
        #expect(String(decoding: requests[1].httpBody ?? Data(), as: UTF8.self).contains("archive"))
        #expect(String(decoding: requests[2].httpBody ?? Data(), as: UTF8.self).contains("deleteditems"))
    }

    @Test func replyGoesThroughADraftToTheShownRecipient() async throws {
        let (outlook, transport) = source([
            .json(#"{"id":"m1","subject":"Lunch","from":{"emailAddress":{"name":"Sam","address":"sam@example.com"}},"replyTo":[{"emailAddress":{"name":"Team","address":"team@example.com"}}],"internetMessageId":"<a@x.com>","conversationId":"c1"}"#),
            .json(#"{"id":"draft1"}"#), .json("{}"), .json(""),
        ])

        let context = try await outlook.replyContext(for: "m1")
        try await outlook.sendReply(context, body: "Sure!", fromName: "Alex")

        #expect(context.toAddress == "team@example.com")
        #expect(context.redirectedFrom == "sam@example.com")
        let requests = await transport.requests
        #expect(requests[2].url?.path.hasSuffix("messages/m1/createReply") == true)
        #expect(requests[3].httpMethod == "PATCH")
        let patch = String(decoding: requests[3].httpBody ?? Data(), as: UTF8.self)
        #expect(patch.contains("team@example.com") && patch.contains("Sure!"))
        #expect(requests[4].url?.path.hasSuffix("messages/draft1/send") == true)
    }

    private let context = ReplyContext(threadID: nil, toName: "Sam", toAddress: "sam@example.com", subject: "Re: x",
                                       inReplyTo: nil, references: [], originalID: "m1")

    @Test func refusedSendDeletesTheDraft() async throws {
        let (outlook, transport) = source([.json(#"{"id":"draft1"}"#), .json("{}"), .json(#"{"error":{"message":"nope"}}"#, status: 400), .json("")])

        await #expect(throws: MailSourceError.self) { try await outlook.sendReply(context, body: "x", fromName: "Alex") }
        let last = try #require(await transport.requests.last)
        #expect(last.httpMethod == "DELETE")
        #expect(last.url?.path.hasSuffix("messages/draft1") == true)
    }

    @Test func serverErrorOnSendKeepsTheDraftAndSaysItMayHaveGone() async throws {
        let (outlook, transport) = source([.json(#"{"id":"draft1"}"#), .json("{}"), .json(#"{"error":{"message":"busy"}}"#, status: 503)])

        await #expect(throws: URLError.self) { try await outlook.sendReply(context, body: "x", fromName: "Alex") }
        #expect(await transport.requests.last?.httpMethod == "POST")  // no DELETE after the send
    }

    @Test func oneUnparsableMessageDoesNotBlockTheInbox() async throws {
        let broken = #"{"id":"m2","subject":"x","isRead":false}"#  // no date
        let (outlook, _) = source([.json(#"{"value":[{"id":"m1"},{"id":"m2"}]}"#), .json(message("m1")), .json(broken)])

        let messages = try await outlook.fetchUnread()

        #expect(messages.map(\.id) == ["m1"])
    }

    @Test func graphRequestsAskForImmutableIDs() async throws {
        let (outlook, transport) = source([.json("{}")])

        try await outlook.perform(.markRead, on: "m1")

        #expect(await transport.requests.last?.value(forHTTPHeaderField: "Prefer") == #"IdType="ImmutableId""#)
    }

    @Test func replyToNameWithACommaStillWorks() async throws {
        let (outlook, _) = source([
            .json(#"{"id":"m1","subject":"Hi","from":{"emailAddress":{"name":"Doe, John","address":"john@example.com"}},"conversationId":"c"}"#),
        ])

        let context = try await outlook.replyContext(for: "m1")

        #expect(context.toAddress == "john@example.com")
        #expect(context.toName == "Doe, John")
    }

    @Test func plainTextBodiesKeepTheirLines() throws {
        let raw = try JSONDecoder().decode(GraphMessage.self, from: Data(message("m2", html: false).utf8))

        let parsed = try raw.mailMessage(account: account)

        #expect(parsed.body == "Plain\nbody")
        #expect(parsed.html == nil)
    }

    @Test(arguments: ["../me", "a b", "a/b", "", String(repeating: "a", count: 600)])
    func unsafeIDsAreRejected(id: String) {
        #expect(!OutlookSource.isSafeID(id))
    }
}

/// Fails the second request with a network error, then answers from the script.
private actor FlakyOnceTransport: HTTPTransport {
    private var replies: [StubTransport.Reply]
    private var count = 0

    init(replies: [StubTransport.Reply]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        count += 1
        if count == 2 { throw URLError(.networkConnectionLost) }
        let reply = replies.removeFirst()
        return (reply.body, HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!)
    }
}
