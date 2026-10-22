import Foundation
import Testing
@testable import MailSources

@Suite("Reply MIME")
struct ReplyMIMETests {
    private let context = ReplyContext(
        threadID: "t1", toName: "Sam Rivera", toAddress: "sam@example.com", subject: "Re: Lunch",
        inReplyTo: "<abc@mail.example.com>", references: ["<old@mail.example.com>", "<abc@mail.example.com>"]
    )

    private func headers(_ raw: String) -> [String: String] {
        // Unfold continuation lines first, as a mail client would.
        let head = (raw.components(separatedBy: "\r\n\r\n").first ?? "").replacingOccurrences(of: "\r\n ", with: " ")
        var result: [String: String] = [:]
        for line in head.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            result[String(line[..<colon])] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private func body(_ raw: String) -> String {
        let encoded = raw.components(separatedBy: "\r\n\r\n").dropFirst().joined().replacingOccurrences(of: "\r\n", with: "")
        return String(decoding: Data(base64Encoded: encoded) ?? Data(), as: UTF8.self)
    }

    @Test func buildsAThreadedPlainTextReply() throws {
        let raw = try ReplyMIME.message(context: context, fromName: "Alex Morgan", fromAddress: "alex@example.com", body: "Sure!\nSee you.")
        let h = headers(raw)

        #expect(h["From"] == "\"Alex Morgan\" <alex@example.com>")
        #expect(h["To"] == "\"Sam Rivera\" <sam@example.com>")
        #expect(h["Subject"] == "Re: Lunch")
        #expect(h["In-Reply-To"] == "<abc@mail.example.com>")
        #expect(h["References"] == "<old@mail.example.com> <abc@mail.example.com>")
        #expect(h["Content-Type"] == "text/plain; charset=UTF-8")
        #expect(body(raw) == "Sure!\r\nSee you.")
    }

    @Test func lineBreaksInHeaderValuesCannotAddHeaders() throws {
        let hostile = ReplyContext(
            threadID: nil, toName: "Sam\r\nBcc: victim@example.com", toAddress: "sam@example.com",
            subject: "Re: Hi\nBcc: other@example.com", inReplyTo: nil, references: []
        )
        let raw = try ReplyMIME.message(context: hostile, fromName: "Alex", fromAddress: "alex@example.com", body: "x")

        #expect(headers(raw)["Bcc"] == nil)
        #expect(!raw.contains("\nBcc:"))
    }

    @Test func nonASCIINamesAndSubjectsAreEncoded() throws {
        let german = ReplyContext(
            threadID: nil, toName: "Jürgen Müller", toAddress: "j@example.com",
            subject: "Re: Übergabe – nächste Woche", inReplyTo: nil, references: []
        )
        let raw = try ReplyMIME.message(context: german, fromName: "Alex", fromAddress: "alex@example.com", body: "Grüße")
        let h = headers(raw)

        #expect(h["To"]?.hasPrefix("=?UTF-8?B?") == true)
        #expect(h["Subject"]?.hasPrefix("=?UTF-8?B?") == true)
        #expect(h["Subject"]!.split(separator: " ").allSatisfy { $0.count <= 75 })
        #expect(body(raw) == "Grüße")
    }

    @Test func rejectsInvalidAddresses() {
        let bad = ReplyContext(threadID: nil, toName: "x", toAddress: "a@b.com>\r\nBcc: c@d.com", subject: "Re:", inReplyTo: nil, references: [])

        #expect(throws: MailSourceError.self) {
            try ReplyMIME.message(context: bad, fromName: "Alex", fromAddress: "alex@example.com", body: "x")
        }
    }

    @Test func contextRepliesToReplyToAndKeepsTheThread() throws {
        let context = try ReplyContext.from(headers: [
            "from": "Sam <sam@example.com>",
            "reply-to": "Team <team@example.com>",
            "subject": "Lunch",
            "message-id": "<abc@mail.example.com>",
            "references": "<one@x.com> junk <two@x.com>",
        ], threadID: "t1")

        #expect(context.toAddress == "team@example.com")
        #expect(context.redirectedFrom == "sam@example.com")
        #expect(context.subject == "Re: Lunch")
        #expect(context.references == ["<one@x.com>", "<two@x.com>", "<abc@mail.example.com>"])
    }

    @Test func replyToTheSenderIsNotFlagged() throws {
        let context = try ReplyContext.from(headers: ["from": "Sam <sam@example.com>", "reply-to": "SAM@example.com"], threadID: nil)

        #expect(context.redirectedFrom == nil)
    }

    @Test func severalReplyToAddressesUseTheFirst() throws {
        let context = try ReplyContext.from(headers: ["from": "Sam <sam@example.com>", "reply-to": "a@example.com, b@example.com"], threadID: nil)

        #expect(context.toAddress == "a@example.com")
    }

    @Test func longHeadersAreFolded() throws {
        let ids = (1...20).map { "<\(String(repeating: "x", count: 60))\($0)@mail.example.com>" }
        let long = ReplyContext(threadID: nil, toName: "Sam", toAddress: "sam@example.com",
                                subject: "Re: " + String(repeating: "Übergabe ", count: 30), inReplyTo: ids.last, references: ids)
        let raw = try ReplyMIME.message(context: long, fromName: "Alex", fromAddress: "alex@example.com", body: "x")

        #expect(raw.components(separatedBy: "\r\n").allSatisfy { $0.count <= 998 })
    }

    @Test(arguments: [("Re: Lunch", "Re: Lunch"), ("AW: Termin", "AW: Termin"), ("Lunch", "Re: Lunch"), ("", "Re:")])
    func replySubjectIsNotDoubled(original: String, expected: String) {
        #expect(ReplyContext.replySubject(original) == expected)
    }
}
