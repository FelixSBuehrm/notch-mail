import Foundation

/// What a reply needs from the original message's headers.
public struct ReplyContext: Equatable, Sendable {
    public let threadID: String?
    public let toName: String
    public let toAddress: String
    /// "Re: …" (not doubled).
    public let subject: String
    /// The original's Message-ID, so mail apps thread the reply.
    public let inReplyTo: String?
    public let references: [String]
    /// The From address, when the reply goes somewhere else (Reply-To). Worth a warning.
    public let redirectedFrom: String?
    /// The provider's ID of the message being answered (Outlook replies through it).
    public let originalID: String?

    public init(threadID: String?, toName: String, toAddress: String, subject: String, inReplyTo: String?, references: [String], redirectedFrom: String? = nil, originalID: String? = nil) {
        self.redirectedFrom = redirectedFrom
        self.originalID = originalID
        self.threadID = threadID
        self.toName = toName
        self.toAddress = toAddress
        self.subject = subject
        self.inReplyTo = inReplyTo
        self.references = references
    }

    /// Builds the context from the original's headers. Replies go to Reply-To if set.
    static func from(headers: [String: String], threadID: String?, originalID: String? = nil) throws -> ReplyContext {
        let from = AddressParser.parse(headers["from"] ?? "")
        // Several Reply-To addresses: reply to the first, never silently to the last.
        let replyTo = headers["reply-to"].flatMap { $0.split(separator: ",").first.map(String.init) }
        let target = replyTo.map(AddressParser.parse) ?? from
        guard ReplyMIME.isValidAddress(target.address) else {
            throw MailSourceError.invalidResponse("The original has no address to reply to")
        }
        let original = (headers["subject"] ?? "").trimmingCharacters(in: .whitespaces)
        let messageID = headers["message-id"].flatMap(ReplyMIME.messageIDs).flatMap(\.first)
        let earlier = headers["references"].map(ReplyMIME.messageIDs) ?? []
        return ReplyContext(
            threadID: threadID,
            toName: target.name,
            toAddress: target.address,
            subject: replySubject(original),
            inReplyTo: messageID,
            references: Array((earlier + [messageID].compactMap { $0 }).suffix(20)),
            redirectedFrom: target.address.lowercased() == from.address.lowercased() ? nil : from.address,
            originalID: originalID
        )
    }

    static func replySubject(_ original: String) -> String {
        let lowered = original.lowercased()
        if lowered.hasPrefix("re:") || lowered.hasPrefix("aw:") { return original }
        return original.isEmpty ? "Re:" : "Re: \(original)"
    }
}

/// Writes a plain-text reply as an RFC 5322 message. Every header value is
/// stripped of line breaks (no header injection) and non-ASCII text is
/// encoded, so names and subjects in any language arrive intact.
public enum ReplyMIME {
    public static func message(
        context: ReplyContext,
        fromName: String,
        fromAddress: String,
        body: String,
        date: Date = Date()
    ) throws -> String {
        guard isValidAddress(fromAddress), isValidAddress(context.toAddress) else {
            throw MailSourceError.invalidResponse("Invalid address")
        }
        var headers = [
            "From: \(mailbox(fromName, fromAddress))",
            "To: \(mailbox(context.toName, context.toAddress))",
            "Subject: \(encodedWords(context.subject))",
            "Date: \(rfc5322Date(date))",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
        ]
        if let inReplyTo = context.inReplyTo { headers.append("In-Reply-To: \(inReplyTo)") }
        // Folded: one ID per line keeps every line far below the 998-character limit.
        if !context.references.isEmpty { headers.append("References: \(context.references.joined(separator: "\r\n "))") }

        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        let encoded = Data(normalized.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + encoded + "\r\n"
    }

    /// `name <address>`, quoted or encoded as needed.
    static func mailbox(_ name: String, _ address: String) -> String {
        let clean = singleLine(name)
        guard !clean.isEmpty, clean != address else { return "<\(address)>" }
        if clean.allSatisfy({ $0.isASCII && !$0.isNewline }) {
            let escaped = clean.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\" <\(address)>"
        }
        return "\(encodedWords(clean)) <\(address)>"
    }

    /// RFC 2047 encoded words (UTF-8, base64), each at most 75 characters.
    static func encodedWords(_ text: String) -> String {
        let clean = singleLine(text)
        guard !clean.allSatisfy({ $0.isASCII }) else { return clean }
        var words: [String] = []
        var chunk = ""
        for character in clean {
            // 45 bytes of UTF-8 → 60 base64 characters + 12 for "=?UTF-8?B?" and "?=".
            if chunk.utf8.count + String(character).utf8.count > 45 {
                words.append(chunk)
                chunk = ""
            }
            chunk.append(character)
        }
        if !chunk.isEmpty { words.append(chunk) }
        return words.map { "=?UTF-8?B?\(Data($0.utf8).base64EncodedString())?=" }.joined(separator: "\r\n ")
    }

    static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
            .filter { !($0.unicodeScalars.first?.properties.generalCategory == .control) }
            .trimmingCharacters(in: .whitespaces)
    }

    static func isValidAddress(_ address: String) -> Bool {
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && address.count <= 254
            && address.allSatisfy { $0.isASCII && !$0.isWhitespace && !"<>()[]\\,;:\"".contains($0) }
    }

    /// The `<…@…>` IDs in a Message-ID or References header; anything else is dropped.
    static func messageIDs(_ header: String) -> [String] {
        header.split(whereSeparator: { $0.isWhitespace || $0 == "," }).compactMap { token in
            let id = String(token)
            guard id.hasPrefix("<"), id.hasSuffix(">"), id.contains("@"), id.count <= 250,
                  id.dropFirst().dropLast().allSatisfy({ $0.isASCII && !$0.isWhitespace && $0 != "<" && $0 != ">" })
            else { return nil }
            return id
        }
    }

    static func rfc5322Date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }
}
