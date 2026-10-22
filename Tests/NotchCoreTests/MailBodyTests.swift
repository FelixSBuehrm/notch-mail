import Foundation
import Testing
@testable import NotchCore

@Suite("Mail body")
struct MailBodyTests {
    @Test func gmailReplyHidesTheQuotedThread() {
        let raw = """
        Sounds good, see you then.

        On Tue, Oct 21, 2026 at 3:14 PM Priya Shah <priya@example.com> wrote:
        > Can we meet on Friday?
        """
        let body = MailBody(raw)

        #expect(body.text == "Sounds good, see you then.")
        #expect(body.quoted?.hasPrefix("On Tue, Oct 21") == true)
    }

    @Test func gmailWrapsTheWroteLine() {
        let raw = "Yes.\n\nOn Tue, Oct 21, 2026 at 3:14 PM Priya Shah <\npriya@example.com> wrote:\n\n> Friday?"

        #expect(MailBody(raw).text == "Yes.")
    }

    @Test(arguments: [
        "Am Di., 21. Okt. 2026 um 15:14 Uhr schrieb Priya Shah <priya@example.com>:",
        "-----Original Message-----",
        "-----Ursprüngliche Nachricht-----",
        "________________________________\nFrom: Priya Shah",
        "From: Priya Shah <priya@example.com>\nSent: Tuesday, October 21, 2026 15:14",
        "Von: Priya Shah <priya@example.com>\nGesendet: Dienstag, 21. Oktober 2026 15:14",
    ])
    func otherClientsQuoteMarkers(marker: String) {
        let body = MailBody("Danke!\n\n\(marker)\nOld text")

        #expect(body.text == "Danke!")
        #expect(body.quoted != nil)
    }

    @Test func trailingQuoteBlockIsHidden() {
        let body = MailBody("Agreed.\n\n> earlier\n> more")

        #expect(body.text == "Agreed.")
        #expect(body.quoted == "> earlier\n> more")
    }

    @Test func inlineRepliesStayVisible() {
        let raw = "> Friday?\nYes.\n> Room?\nThe big one."

        #expect(MailBody(raw).text == raw)
        #expect(MailBody(raw).quoted == nil)
    }

    @Test func mailThatIsOnlyAQuoteIsShownWhole() {
        let raw = "On Tue, Oct 21, 2026 Priya wrote:\n> hi"

        #expect(MailBody(raw).text == raw)
    }

    @Test func plainMailIsUntouched() {
        #expect(MailBody("Hello\n\nFrom: the team").text == "Hello\n\nFrom: the team")
    }
}

@Suite("Mail links")
struct MailLinksTests {
    private func links(_ text: AttributedString) -> [(String, URL)] {
        text.runs.compactMap { run in run.link.map { (String(text[run.range].characters), $0) } }
    }

    @Test func bracketedLinkBecomesAShortHostLink() {
        let text = MailLinks.attributed("Read the report <https://docs.example.com/a/very/long/path?x=1>.")

        #expect(String(text.characters) == "Read the report ↗ docs.example.com.")
        #expect(links(text).map(\.1.absoluteString) == ["https://docs.example.com/a/very/long/path?x=1"])
    }

    @Test func shortBareLinkKeepsItsText() {
        let text = MailLinks.attributed("See https://example.com/x today")

        #expect(String(text.characters) == "See https://example.com/x today")
        #expect(links(text).first?.0 == "https://example.com/x")
    }

    @Test func longBareLinkIsShortened() {
        let url = "https://click.example.com/" + String(repeating: "a", count: 80)
        let text = MailLinks.attributed("Go \(url)")

        #expect(String(text.characters) == "Go ↗ click.example.com")
        #expect(links(text).first?.1.absoluteString == url)
    }

    @Test func mailAddressesBecomeMailtoLinks() {
        let text = MailLinks.attributed("Write to lena@example.com")

        #expect(links(text).first?.1.absoluteString == "mailto:lena@example.com")
    }

    @Test func otherSchemesStayPlainText() {
        let text = MailLinks.attributed("Run file:///etc/passwd or javascript:alert(1)")

        #expect(links(text).isEmpty)
    }
}
