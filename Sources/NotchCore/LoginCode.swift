import Foundation

/// Finds a one-time login code ("Your verification code is 482913") in a mail.
/// Only mails that say they carry a code count, so order numbers, prices,
/// phone numbers and dates in ordinary mail are never mistaken for one.
public enum LoginCode {
    /// Codes sit near the top; a capped scan keeps huge mails cheap.
    static let scanLimit = 4_000
    /// How far after the phrase the code may appear.
    static let reach = 300

    /// Phrases that mark a code mail (lowercased; English and German, a few others).
    static let phrases = [
        "verification code", "security code", "login code", "log-in code", "sign-in code", "sign in code",
        "confirmation code", "authentication code", "one-time", "one time password", "otp", "passcode",
        "2fa", "two-factor", "your code", "code:", "verify your", "sign in to", "sign-in",
        "bestätigungscode", "anmeldecode", "sicherheitscode", "einmalcode", "einmalpasswort", "verifizierungscode",
        "dein code", "ihr code", "código", "code de vérification",
    ]

    private static let google = try! NSRegularExpression(pattern: #"\bG-(\d{6})\b"#)
    private static let digits = try! NSRegularExpression(
        pattern: #"(?<![\w.,:/+€$\-])(\d{3}[ -]\d{3}|\d{4,8})(?![\w%\-]|[.,:/]\d)"#
    )
    private static let mixed = try! NSRegularExpression(pattern: #"\b([A-Z0-9]{3}-[A-Z0-9]{3})\b"#)

    public static func detect(subject: String, body: String) -> String? {
        let text = subject + "\n" + String(body.prefix(scanLimit))
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)

        if let match = google.firstMatch(in: text, range: whole) {
            return ns.substring(with: match.range(at: 1))
        }
        let lowered = text.lowercased() as NSString
        let starts = phrases.compactMap { phrase -> Int? in
            let range = lowered.range(of: phrase)
            return range.location == NSNotFound ? nil : range.location
        }
        guard let first = starts.min() else { return nil }

        let candidates = (digits.matches(in: text, range: whole) + mixed.matches(in: text, range: whole))
            .map { (location: $0.range.location, code: ns.substring(with: $0.range(at: 1))) }
            .filter { isPlausible($0.code) }
            .sorted { $0.location < $1.location }
        // The first code after the phrase; else the closest one just before it (e.g. in the subject).
        if let after = candidates.first(where: { $0.location >= first && $0.location - first <= reach }) {
            return normalized(after.code)
        }
        return candidates.last(where: { $0.location < first && first - $0.location <= 120 }).map { normalized($0.code) }
    }

    private static func isPlausible(_ code: String) -> Bool {
        if code.contains(where: \.isLetter) {
            return code.contains(where: \.isNumber)
        }
        let plain = code.filter(\.isNumber)
        // Years (© 2026) are not codes.
        if plain.count == 4, let year = Int(plain), (1900...2099).contains(year) { return false }
        return true
    }

    private static func normalized(_ code: String) -> String {
        code.contains(where: \.isLetter) ? code : code.filter(\.isNumber)
    }
}
