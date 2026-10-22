import Foundation

/// A message body split into what's new and the earlier thread quoted below it,
/// so a reply doesn't show the whole conversation again. Works on plain text,
/// line by line, in one pass.
public struct MailBody: Equatable, Sendable {
    /// The new part; the whole body when no quote was found.
    public let text: String
    /// "On … wrote:" and everything after it, if there was something before it.
    public let quoted: String?

    public init(_ raw: String) {
        let lines = raw.components(separatedBy: "\n")
        let tail = Self.trailingQuoteStart(lines)
        let cut = lines.indices.first { Self.isQuoteMarker(at: $0, in: lines) || $0 == tail }
        let text = cut.map { lines[..<$0].joined(separator: "\n") }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let cut, !text.isEmpty else {
            self.text = raw
            self.quoted = nil
            return
        }
        self.text = text
        self.quoted = lines[cut...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isQuoteMarker(at index: Int, in lines: [String]) -> Bool {
        let line = lines[index].trimmingCharacters(in: .whitespaces)
        let next = index + 1 < lines.count ? lines[index + 1].trimmingCharacters(in: .whitespaces) : ""
        let joined = line + " " + next
        if line.hasPrefix("On "), line.hasSuffix("wrote:") || joined.hasSuffix("wrote:") { return true }
        if line.hasPrefix("Am "), joined.contains("schrieb"), line.hasSuffix(":") || joined.hasSuffix(":") { return true }
        if line.hasPrefix("Le "), joined.contains("a écrit") { return true }
        if line.hasPrefix("-----"), line.contains("Original") || line.contains("Ursprüngliche") { return true }
        if line.count >= 10, line.allSatisfy({ $0 == "_" }), startsHeader(next, ["From:", "Von:"]) { return true }
        if startsHeader(line, ["From:", "Von:"]) {
            let following = lines[(index + 1)..<min(lines.count, index + 5)]
            return following.contains { startsHeader($0, ["Sent:", "Gesendet:", "Date:", "Datum:"]) }
        }
        return false
    }

    private static func startsHeader(_ line: String, _ names: [String]) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return names.contains { trimmed.hasPrefix($0) }
    }

    /// First line of a "> …" block that runs to the end (blank lines allowed).
    /// Inline replies, where new text follows a quote, never match.
    private static func trailingQuoteStart(_ lines: [String]) -> Int? {
        var start: Int?
        for index in lines.indices.reversed() {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard line.hasPrefix(">") else { break }
            start = index
        }
        return start
    }
}

/// Turns web addresses and mail addresses in plain text into links. Only
/// http(s) and mailto open; long addresses (tracking links) shrink to "↗ host",
/// so the place a link goes is always visible.
public enum MailLinks {
    static let maxShownLength = 50
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    public static func attributed(_ text: String) -> AttributedString {
        let ns = text as NSString
        var output = AttributedString()
        var cursor = 0
        let matches = detector?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? []
        for match in matches {
            guard let url = match.url, isAllowed(url), match.range.location >= cursor else { continue }
            var range = match.range
            let bracketed = range.location > 0 && NSMaxRange(range) < ns.length
                && ns.character(at: range.location - 1) == UInt16(UInt8(ascii: "<"))
                && ns.character(at: NSMaxRange(range)) == UInt16(UInt8(ascii: ">"))
            if bracketed { range = NSRange(location: range.location - 1, length: range.length + 2) }

            output += AttributedString(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            let shown = ns.substring(with: match.range)
            let label = bracketed || (url.scheme != "mailto" && shown.count > maxShownLength)
                ? "↗ " + (url.host ?? shown)
                : shown
            var link = AttributedString(label)
            link.link = url
            output += link
            cursor = NSMaxRange(range)
        }
        output += AttributedString(ns.substring(from: cursor))
        return output
    }

    private static func isAllowed(_ url: URL) -> Bool {
        ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "")
    }
}
