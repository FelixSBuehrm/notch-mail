import Foundation
import NotchCore
import Testing
@testable import MailSources

@Suite("Gmail message parsing")
struct GmailParserTests {
    let account = MailAccount(id: "gmail", name: "Work", address: "me@example.com")

    private func decode(_ json: String) throws -> GmailMessage {
        try JSONDecoder().decode(GmailMessage.self, from: Data(json.utf8))
    }

    @Test func prefersThePlainTextPart() throws {
        let raw = try decode("""
        {"id":"m1","threadId":"t1","labelIds":["UNREAD","INBOX"],"snippet":"snip",
         "internalDate":"1700000000000",
         "payload":{"mimeType":"multipart/alternative",
           "headers":[{"name":"From","value":"\\"Weber, Anna\\" <anna@example.com>"},
                      {"name":"Subject","value":"Term sheet"}],
           "parts":[{"mimeType":"text/html","body":{"data":"\(base64URL("<p>HTML</p>"))"}},
                    {"mimeType":"text/plain","body":{"data":"\(base64URL("Hi Alex,\nplain body"))"}}]}}
        """)

        let message = try GmailParser.mailMessage(from: raw, account: account)

        #expect(message.id == "m1")
        #expect(message.senderName == "Weber, Anna")
        #expect(message.senderAddress == "anna@example.com")
        #expect(message.subject == "Term sheet")
        #expect(message.body == "Hi Alex,\nplain body")
        #expect(message.receivedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(message.account == account)
    }

    @Test func fallsBackToHTMLConvertedToText() throws {
        let html = "<html><head><style>p{}</style></head><body><p>Hello&nbsp;there</p><p>Line&amp;two</p></body></html>"
        let raw = try decode("""
        {"id":"m2","internalDate":"1700000000000",
         "payload":{"mimeType":"text/html","headers":[{"name":"From","value":"news@example.com"}],
           "body":{"data":"\(base64URL(html))"}}}
        """)

        let message = try GmailParser.mailMessage(from: raw, account: account)

        #expect(message.body == "Hello there\n\nLine&two")
        #expect(message.html == html)
        #expect(message.senderName == "news")
        #expect(message.subject == "(no subject)")
    }

    @Test func hugeHTMLFallsBackToText() throws {
        let html = "<p>" + String(repeating: "x", count: GmailParser.maxHTMLLength) + "</p>"
        let raw = try decode("""
        {"id":"m9","internalDate":"1700000000000",
         "payload":{"mimeType":"text/html","headers":[],"body":{"data":"\(base64URL(html))"}}}
        """)

        #expect(try GmailParser.mailMessage(from: raw, account: account).html == nil)
    }

    @Test func findsTextInsideNestedParts() throws {
        let raw = try decode("""
        {"id":"m3","internalDate":"1700000000000",
         "payload":{"mimeType":"multipart/mixed","headers":[],
           "parts":[{"mimeType":"multipart/alternative","parts":[
                      {"mimeType":"text/plain","body":{"data":"\(base64URL("nested"))"}}]},
                    {"mimeType":"text/plain","filename":"notes.txt","body":{"attachmentId":"x"}}]}}
        """)

        #expect(try GmailParser.mailMessage(from: raw, account: account).body == "nested")
    }

    @Test func usesTheSnippetWhenThereIsNoReadableBody() throws {
        let raw = try decode("""
        {"id":"m4","snippet":"Only a snippet","internalDate":"1700000000000",
         "payload":{"mimeType":"image/png","headers":[]}}
        """)

        #expect(try GmailParser.mailMessage(from: raw, account: account).body == "Only a snippet")
    }

    @Test func rejectsAMessageWithAnUnsafeID() throws {
        let raw = try decode(#"{"id":"../../profile","internalDate":"1700000000000","payload":{"mimeType":"text/plain","headers":[]}}"#)

        #expect(throws: MailSourceError.self) {
            try GmailParser.mailMessage(from: raw, account: account)
        }
    }

    @Test func rejectsAMessageWithoutDate() throws {
        let raw = try decode(#"{"id":"m5","payload":{"mimeType":"text/plain","headers":[]}}"#)

        #expect(throws: MailSourceError.self) {
            try GmailParser.mailMessage(from: raw, account: account)
        }
    }

    @Test func capsHugeBodies() throws {
        let huge = String(repeating: "a", count: GmailParser.maxBodyLength + 500)
        let raw = try decode("""
        {"id":"m6","internalDate":"1700000000000",
         "payload":{"mimeType":"text/plain","headers":[],"body":{"data":"\(base64URL(huge))"}}}
        """)

        #expect(try GmailParser.mailMessage(from: raw, account: account).body.count <= GmailParser.maxBodyLength + 1)
    }
}

@Suite("Address parsing")
struct AddressParserTests {
    @Test(arguments: [
        ("Anna Weber <anna@example.com>", "Anna Weber", "anna@example.com"),
        ("\"Weber, Anna\" <anna@example.com>", "Weber, Anna", "anna@example.com"),
        ("<anna@example.com>", "anna", "anna@example.com"),
        ("anna@example.com", "anna", "anna@example.com"),
        ("  Anna   <ANNA@Example.com> ", "Anna", "ANNA@Example.com"),
        ("", "Unknown sender", ""),
    ])
    func parses(raw: String, name: String, address: String) {
        let parsed = AddressParser.parse(raw)

        #expect(parsed.name == name)
        #expect(parsed.address == address)
    }
}

@Suite("HTML to text")
struct HTMLTextTests {
    @Test func dropsScriptsStylesAndTags() {
        let html = "<script>alert(1)</script><style>.a{}</style><div>One<br>Two</div><b>Bold</b>"

        #expect(HTMLText.plain(html) == "One\nTwo\nBold")
    }

    @Test func decodesEntities() {
        #expect(HTMLText.plain("&lt;tag&gt; &quot;q&quot; &#39;s&#39; &#8364; &#x41;") == "<tag> \"q\" 's' € A")
    }

    @Test func hostileMarkupStaysFast() {
        // Unclosed tags, endless "<" without ">", huge whitespace runs: all linear now.
        let hostile = String(repeating: "<head", count: 40_000)
            + String(repeating: "<", count: 200_000)
            + String(repeating: " ", count: 200_000) + "x"
        let clock = ContinuousClock()

        let elapsed = clock.measure { _ = HTMLText.plain(hostile) }

        #expect(elapsed < .seconds(1))
    }

    @Test func unclosedTagKeepsTheRestAsText() {
        #expect(HTMLText.plain("a < b and c") == "a < b and c")
    }

    @Test func unclosedStyleDropsTheRest() {
        #expect(HTMLText.plain("before<style>body{}") == "before")
    }

    @Test func stripsBidiOverridesAndControlCharacters() {
        #expect(HTMLText.plain("pay\u{202E}fdp.exe\u{0007}") == "payfdp.exe")
        #expect(HTMLText.plain("&#8238;x") == "x")
    }

    @Test func entitySplitAcrossOthersIsDecodedOnce() {
        #expect(HTMLText.plain("&amp;lt; &#38;amp;") == "&lt; &amp;")
    }

    @Test func collapsesBlankLines() {
        #expect(HTMLText.plain("<p>a</p>\n\n\n<p></p><p>b</p>") == "a\n\nb")
    }
}

@Suite("HTML links")
struct HTMLLinkTests {
    @Test func keepsTheLinkTargetAfterItsText() {
        let html = #"<p>Read <a class="x" href="https://example.com/r?a=1&amp;b=2">the report</a> now</p>"#

        #expect(HTMLText.plain(html) == "Read the report <https://example.com/r?a=1&b=2> now")
    }

    @Test func linkWhoseTextIsTheURLIsNotRepeated() {
        #expect(HTMLText.plain("<a href='https://example.com'>https://example.com</a>") == "https://example.com")
    }

    @Test func ignoresNonWebLinks() {
        #expect(HTMLText.plain(#"<a href="javascript:alert(1)">x</a> <a href="mailto:a@b.c">mail</a>"#) == "x mail")
    }
}

@Suite("HTML spacing")
struct HTMLSpacingTests {
    @Test func inlineTagsKeepTheirSpaces() {
        #expect(HTMLText.plain("Hello <b>Alex</b> and <span>Priya</span>!") == "Hello Alex and Priya!")
    }

    @Test func tableCellsAreSeparated() {
        #expect(HTMLText.plain("<table><tr><td>Amount</td><td>€ 40</td></tr></table>") == "Amount € 40")
    }
}
