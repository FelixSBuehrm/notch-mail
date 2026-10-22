import Foundation

/// Small text helpers for the notch rows.
public enum Formatting {
    /// "482913" → "482 913", easier to read and type. Other shapes stay as they are.
    public static func spacedCode(_ code: String) -> String {
        guard code.count == 6, code.allSatisfy(\.isNumber) else { return code }
        return "\(code.prefix(3)) \(code.suffix(3))"
    }

    /// "Anna Weber" → "AW"; first and last word, "?" when empty.
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }

    /// Stable colour slot for a sender (FNV-1a; `hashValue` changes every launch).
    public static func paletteIndex(for key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.lowercased().utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        return Int(hash % UInt64(count))
    }

    /// "now", "5m", "3h", "2d".
    public static func shortAge(from date: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3_600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3_600)h"
        default: return "\(seconds / 86_400)d"
        }
    }

    /// One line of body text: whitespace collapsed, cut at `limit` characters with "…".
    public static func preview(_ body: String, limit: Int) -> String {
        let line = body.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard line.count > limit else { return line }
        return String(line.prefix(max(0, limit - 1))) + "…"
    }
}
