import Foundation
import Testing
@testable import NotchCore

@Suite("Formatting")
struct FormattingTests {
    @Test(arguments: [
        ("Anna Weber", "AW"),
        ("anna", "A"),
        ("Jean-Luc de la Cruz", "JC"),
        ("  ", "?"),
        ("", "?"),
    ])
    func initials(name: String, expected: String) {
        #expect(Formatting.initials(name) == expected)
    }

    @Test func paletteIndexIsStableAndInRange() {
        let first = Formatting.paletteIndex(for: "anna@example.com", count: 6)
        let again = Formatting.paletteIndex(for: "anna@example.com", count: 6)

        #expect(first == again)
        #expect((0..<6).contains(first))
        #expect(Formatting.paletteIndex(for: "x", count: 0) == 0)
    }

    @Test(arguments: [
        (10.0, "now"),
        (59.0, "now"),
        (60.0, "1m"),
        (3_599.0, "59m"),
        (3_600.0, "1h"),
        (86_400.0 * 2, "2d"),
        (-30.0, "now"),
    ])
    func shortAge(seconds: TimeInterval, expected: String) {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let then = now.addingTimeInterval(-seconds)

        #expect(Formatting.shortAge(from: then, to: now) == expected)
    }

    @Test func previewCollapsesWhitespaceAndTruncates() {
        let body = "Hi Alex,\n\n   the   deck is ready.\tSee you tomorrow."

        #expect(Formatting.preview(body, limit: 100) == "Hi Alex, the deck is ready. See you tomorrow.")
        #expect(Formatting.preview(body, limit: 11) == "Hi Alex, t…")
    }
}

@Suite("Code formatting")
struct CodeFormattingTests {
    @Test(arguments: [("482913", "482 913"), ("4458123", "4458123"), ("Q7X-4KD", "Q7X-4KD"), ("8812", "8812")])
    func sixDigitCodesAreSpaced(code: String, expected: String) {
        #expect(Formatting.spacedCode(code) == expected)
    }
}
