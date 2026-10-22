import Foundation
import NotchCore
import Testing
@testable import MailSources

@Suite("Gmail replies and lookups")
struct GmailReplyTests {
    let account = MailAccount(id: "gmail", name: "Gmail", address: "alex@example.com")
    let credentials = GoogleClientCredentials(clientID: "id", clientSecret: "secret")
    let tokenJSON = #"{"access_token":"tok","expires_in":3600}"#

    private func setUp(_ replies: [StubTransport.Reply]) -> (GmailSource, DriveClient, StubTransport) {
        let transport = StubTransport([.json(tokenJSON)] + replies)
        let tokens = GoogleTokenProvider(credentials: credentials, refreshToken: "1//r", transport: transport)
        return (GmailSource(account: account, tokens: tokens, transport: transport), DriveClient(tokens: tokens, transport: transport), transport)
    }

    private let metadata = #"""
    {"id":"m1","threadId":"t1","internalDate":"1700000000000","payload":{"headers":[
      {"name":"From","value":"Sam Rivera <sam@example.com>"},
      {"name":"Subject","value":"Lunch"},
      {"name":"Message-ID","value":"<abc@mail.example.com>"}]}}
    """#

    @Test func sendsAReplyInTheThread() async throws {
        let (gmail, _, transport) = setUp([.json(metadata), .json(#"{"id":"sent1"}"#)])

        let context = try await gmail.replyContext(for: "m1")
        try await gmail.sendReply(context, body: "Sure!", fromName: "Alex Morgan")

        let requests = await transport.requests
        #expect(requests[1].url?.query?.contains("format=metadata") == true)
        #expect(requests[2].url?.absoluteString == "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")
        let payload = try JSONDecoder().decode([String: String].self, from: requests[2].httpBody ?? Data())
        #expect(payload["threadId"] == "t1")
        let rawB64 = payload["raw"]!.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padded = rawB64 + String(repeating: "=", count: (4 - rawB64.count % 4) % 4)
        let raw = String(decoding: Data(base64Encoded: padded)!, as: UTF8.self)
        #expect(raw.contains("To: \"Sam Rivera\" <sam@example.com>"))
        #expect(raw.contains("Subject: Re: Lunch"))
        #expect(raw.contains("In-Reply-To: <abc@mail.example.com>"))
        #expect(raw.contains("From: \"Alex Morgan\" <alex@example.com>"))
    }

    @Test func searchListsHitsAsLines() async throws {
        let (gmail, _, transport) = setUp([.json(#"{"messages":[{"id":"m1"}]}"#), .json(metadata.replacingOccurrences(of: #""payload""#, with: #""snippet":"See &amp; you","payload""#))])

        let text = try await gmail.search("from:sam lunch")

        #expect(text.hasPrefix("id: m1 | from: Sam Rivera <sam@example.com>"))
        #expect(text.contains("See & you"))
        let url = try #require(await transport.requests[1].url?.absoluteString)
        #expect(url.contains("q=from:sam%20lunch") || url.contains("q=from%3Asam%20lunch"))
    }

    @Test func searchRejectsUnsafeIDsFromTheServer() async throws {
        let (gmail, _, _) = setUp([.json(#"{"messages":[{"id":"../../drafts"}]}"#)])

        #expect(try await gmail.search("x") == "No messages found.")
    }

    @Test func readingAnUnsafeIDFails() async {
        let (gmail, _, _) = setUp([])

        await #expect(throws: MailSourceError.self) { try await gmail.readMessage("a/b") }
    }

    @Test func driveSearchEscapesQuotes() async throws {
        let (_, drive, transport) = setUp([.json(#"{"files":[{"id":"f1","name":"Budget","mimeType":"application/vnd.google-apps.spreadsheet"}]}"#)])

        let text = try await drive.search("Sam's budget")

        #expect(text.contains("id: f1 | name: Budget | type: Google Sheet"))
        let query = try #require(await transport.requests[1].url).query(percentEncoded: false) ?? ""
        #expect(query.contains(#"fullText contains 'Sam\'s budget'"#))
    }

    @Test func driveReadsADocAsText() async throws {
        let (_, drive, transport) = setUp([
            .json(#"{"name":"Notes","mimeType":"application/vnd.google-apps.document"}"#),
            .json("Roadmap: ship reply in Q4"),
        ])

        let text = try await drive.read("doc1")

        #expect(text == "File: Notes\n\nRoadmap: ship reply in Q4")
        #expect(await transport.requests[2].url?.absoluteString.contains("doc1/export?mimeType=text/plain") == true)
    }

    @Test func driveSkipsBinaryFiles() async throws {
        let (_, drive, transport) = setUp([.json(#"{"name":"Scan","mimeType":"image/png"}"#)])

        let text = try await drive.read("img1")

        #expect(text.contains("only Docs, Sheets, Slides and text files"))
        #expect(await transport.requests.count == 2)
    }

    @Test func missingDriveAccessIsAGentleToolError() async {
        let (gmail, drive, _) = setUp([.json(#"{"error":{"message":"Insufficient Permission"}}"#, status: 403)])
        let tools = GoogleDraftTools(gmail: gmail, drive: drive)

        let result = await tools.run(ClaudeToolUse(id: "t", name: "search_drive", input: .object(["query": .string("x")])))

        #expect(result.isError)
        #expect(result.text.contains("Drive access isn't granted"))
    }
}
