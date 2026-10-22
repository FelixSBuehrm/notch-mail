import Foundation
import NotchCore

/// The parts of a Gmail API message (`format=full`) the notch needs.
public struct GmailMessage: Decodable, Sendable {
    public struct Header: Decodable, Sendable {
        let name: String
        let value: String
    }

    public struct Body: Decodable, Sendable {
        let data: String?
        let attachmentId: String?
    }

    public struct Part: Decodable, Sendable {
        let mimeType: String?
        let filename: String?
        let headers: [Header]?
        let body: Body?
        let parts: [Part]?
    }

    let id: String
    let threadId: String?
    let labelIds: [String]?
    let snippet: String?
    let internalDate: String?
    let payload: Part?

    var isInInbox: Bool { labelIds?.contains("INBOX") ?? false }
    var isUnreadInInbox: Bool { isInInbox && (labelIds?.contains("UNREAD") ?? false) }

    /// Gmail IDs are short alphanumeric strings. Anything else never goes into a URL.
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }
    }
}

/// Turns a Gmail API message into a `MailMessage`. Gmail content is external
/// input: anything missing gets a safe fallback, only a missing date is an error.
public enum GmailParser {
    /// The notch shows a preview, not a book.
    static let maxBodyLength = 20_000
    /// Bigger HTML falls back to the text version.
    static let maxHTMLLength = 600_000

    public static func mailMessage(from raw: GmailMessage, account: MailAccount) throws -> MailMessage {
        guard GmailMessage.isSafeID(raw.id) else {
            throw MailSourceError.invalidResponse("Message with an unexpected ID")
        }
        guard let millis = raw.internalDate.flatMap(Double.init) else {
            throw MailSourceError.invalidResponse("Message without a date")
        }
        let headers = raw.payload?.headers ?? []
        let from = AddressParser.parse(HTMLText.cleanDisplayText(header("From", in: headers) ?? ""))
        let subject = header("Subject", in: headers).map(HTMLText.cleanDisplayText)?
            .trimmingCharacters(in: .whitespaces)

        return MailMessage(
            id: raw.id,
            account: account,
            senderName: from.name,
            senderAddress: from.address,
            subject: subject.flatMap { $0.isEmpty ? nil : $0 } ?? "(no subject)",
            body: capped(body(of: raw)),
            html: html(of: raw),
            receivedAt: Date(timeIntervalSince1970: millis / 1_000)
        )
    }

    private static func header(_ name: String, in headers: [GmailMessage.Header]) -> String? {
        headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private static func body(of raw: GmailMessage) -> String {
        if let payload = raw.payload {
            if let plain = firstText(in: payload, mimeType: "text/plain"), !plain.isEmpty {
                return HTMLText.cleanDisplayText(String(plain.prefix(HTMLText.maxInput)))
            }
            if let html = firstText(in: payload, mimeType: "text/html") {
                let text = HTMLText.plain(html)
                if !text.isEmpty { return text }
            }
        }
        return raw.snippet.map { HTMLText.cleanDisplayText(HTMLText.decodeEntities($0)) } ?? ""
    }

    private static func html(of raw: GmailMessage) -> String? {
        guard let payload = raw.payload, let html = firstText(in: payload, mimeType: "text/html"),
              !html.isEmpty, html.utf8.count <= maxHTMLLength else { return nil }
        return html
    }

    /// Depth-first search for an inline (non-attachment) part of `mimeType`.
    private static func firstText(in part: GmailMessage.Part, mimeType: String) -> String? {
        let isAttachment = !(part.filename ?? "").isEmpty
        if part.mimeType?.lowercased() == mimeType, !isAttachment,
           let encoded = part.body?.data, let data = Data(base64URLEncoded: encoded) {
            return String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: "\r\n", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        for child in part.parts ?? [] {
            if let text = firstText(in: child, mimeType: mimeType) { return text }
        }
        return nil
    }

    private static func capped(_ text: String) -> String {
        text.count > maxBodyLength ? String(text.prefix(maxBodyLength)) + "…" : text
    }
}

/// Splits a From header into display name and address.
public enum AddressParser {
    public static func parse(_ raw: String) -> (name: String, address: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return ("Unknown sender", "") }

        if let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close {
            let address = String(trimmed[trimmed.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            let name = String(trimmed[..<open])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? localPart(address) : name, address)
        }
        return (localPart(trimmed), trimmed)
    }

    private static func localPart(_ address: String) -> String {
        address.split(separator: "@").first.map(String.init) ?? address
    }
}
