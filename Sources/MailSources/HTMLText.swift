import Foundation

/// Good-enough HTML → plain text for previews. Nothing is rendered, so no
/// remote content or scripts can load. Mail is hostile input: this is a single
/// linear pass (no regular expressions) over a size-capped string.
public enum HTMLText {
    /// Far more than a preview needs; keeps a multi-megabyte mail cheap.
    static let maxInput = 200_000
    private static let hiddenElements: Set<String> = ["head", "style", "script", "title"]
    private static let paragraphTags: Set<String> = ["p", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "table"]
    private static let lineTags: Set<String> = ["div", "tr", "li"]
    private static let cellTags: Set<String> = ["td", "th"]
    private static let maxHrefLength = 2_000

    public static func plain(_ html: String) -> String {
        let chars = Array(html.prefix(maxInput))
        // Where the last ">" is: a "<" after it can never close, so it's text.
        let lastClose = chars.lastIndex(of: ">") ?? -1
        var out = ""
        var index = 0
        var pendingSpace = false
        var link: (href: String, textStart: String.Index)?

        while index < chars.count {
            let char = chars[index]
            if char == "<", index < lastClose, let end = chars[index...].firstIndex(of: ">") {
                let inner = chars[(index + 1)..<end]
                let tag = tagName(inner)
                index = end + 1
                if hiddenElements.contains(tag.name), !tag.isClosing {
                    index = skipElement(tag.name, in: chars, from: index)
                }
                if tag.name == "a" {
                    if !tag.isClosing {
                        link = webHref(in: inner).map { ($0, out.endIndex) }
                    } else if let open = link {
                        out += linkTarget(open.href, after: out[open.textStart...])
                        link = nil
                    }
                }
                let lineBreak = breakFor(tag)
                out += lineBreak
                // Inline tags (<b>, <a>, <span>) keep the space around them.
                if !lineBreak.isEmpty { pendingSpace = false }
                if tag.isClosing, cellTags.contains(tag.name) { pendingSpace = true }
                continue
            }
            if char.isWhitespace {
                pendingSpace = true
            } else {
                if pendingSpace, let last = out.last, last != "\n" { out.append(" ") }
                pendingSpace = false
                out.append(char)
            }
            index += 1
        }
        return tidy(cleanDisplayText(decodeEntities(out)))
    }

    private static func tagName(_ inner: ArraySlice<Character>) -> (name: String, isClosing: Bool) {
        let isClosing = inner.first == "/"
        let name = inner.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }
        return (String(name).lowercased(), isClosing)
    }

    /// The http(s) target of `<a … href="…">`, if it has one.
    private static func webHref(in inner: ArraySlice<Character>) -> String? {
        let text = String(inner)
        guard let attribute = text.range(of: "href", options: .caseInsensitive) else { return nil }
        let rest = text[attribute.upperBound...].drop { $0 == " " }
        guard rest.first == "=" else { return nil }
        let value = rest.dropFirst().drop { $0 == " " }
        guard let quote = value.first, quote == "\"" || quote == "'" else { return nil }
        let href = String(value.dropFirst().prefix { $0 != quote })
        let lowered = href.lowercased()
        guard href.count <= maxHrefLength,
              lowered.hasPrefix("https://") || lowered.hasPrefix("http://"),
              !href.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" }) else { return nil }
        return href
    }

    /// " <href>" after a link's text, unless the text already is the address.
    private static func linkTarget(_ href: String, after text: Substring) -> String {
        let shown = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return decodeEntities(shown) == decodeEntities(href) ? "" : " <\(href)>"
    }

    private static func breakFor(_ tag: (name: String, isClosing: Bool)) -> String {
        if tag.name == "br" { return "\n" }
        guard tag.isClosing else { return "" }
        if paragraphTags.contains(tag.name) { return "\n\n" }
        if lineTags.contains(tag.name) { return "\n" }
        return ""
    }

    /// Index after `</name...>`, or the end if it never closes.
    private static func skipElement(_ name: String, in chars: [Character], from start: Int) -> Int {
        let closing = Array("</\(name)")
        var index = start
        while let open = chars[index...].firstIndex(of: "<") {
            let candidate = chars[open..<min(chars.count, open + closing.count)].map { Character($0.lowercased()) }
            if candidate == closing {
                return (chars[open...].firstIndex(of: ">") ?? chars.count - 1) + 1
            }
            index = open + 1
        }
        return chars.count
    }

    /// Decodes `&name;`, `&#123;` and `&#x1F;` in one pass, so "&amp;lt;" stays "&lt;".
    static func decodeEntities(_ text: String) -> String {
        let named: [String: Character] = ["nbsp": " ", "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
        let chars = Array(text)
        var out = ""
        var index = 0
        while index < chars.count {
            guard chars[index] == "&",
                  let semi = chars[index...].prefix(12).firstIndex(of: ";") else {
                out.append(chars[index])
                index += 1
                continue
            }
            let body = String(chars[(index + 1)..<semi])
            if let value = named[body] ?? numericEntity(body) {
                out.append(value)
                index = semi + 1
            } else {
                out.append(chars[index])
                index += 1
            }
        }
        return out
    }

    private static func numericEntity(_ body: String) -> Character? {
        guard body.hasPrefix("#") else { return nil }
        let digits = body.dropFirst()
        let isHex = digits.first == "x" || digits.first == "X"
        guard let code = UInt32(isHex ? String(digits.dropFirst()) : String(digits), radix: isHex ? 16 : 10),
              let scalar = Unicode.Scalar(code) else { return nil }
        return Character(scalar)
    }

    /// Removes control and bidi-override characters that could disguise text
    /// (e.g. "pay\u{202E}fdp.exe" displaying as "payexe.pdf"). Keeps newlines and tabs.
    public static func cleanDisplayText(_ text: String) -> String {
        let bidi: ClosedRange<UInt32> = 0x202A...0x202E
        let isolates: ClosedRange<UInt32> = 0x2066...0x2069
        let scalars = text.unicodeScalars.filter { scalar in
            if scalar == "\n" || scalar == "\t" { return true }
            if scalar.properties.generalCategory == .control { return false }
            return !bidi.contains(scalar.value) && !isolates.contains(scalar.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    /// Trims every line and allows at most one blank line in a row.
    private static func tidy(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        var output: [String] = []
        for line in lines where !(line.isEmpty && (output.last?.isEmpty ?? true)) {
            output.append(line)
        }
        return output.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
