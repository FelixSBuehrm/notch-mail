import Foundation

/// Sends HTTP requests. Swappable so tests never touch the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MailSourceError.invalidResponse("Not an HTTP response")
        }
        return (data, http)
    }
}

public enum MailSourceError: Error, Equatable, LocalizedError {
    /// Client ID / secret missing from the Keychain.
    case missingClientCredentials
    /// No stored sign-in for this account.
    case notConnected
    /// The sign-in was revoked or expired; the user has to connect again.
    case authorizationRevoked
    case http(status: Int, message: String)
    case invalidResponse(String)
    case signInFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingClientCredentials: "Google client ID or secret missing from the Keychain"
        case .notConnected: "Not connected"
        case .authorizationRevoked: "Sign-in expired, connect again"
        case .http(let status, let message): "Server error \(status): \(message)"
        case .invalidResponse(let detail): "Unexpected response: \(detail)"
        case .signInFailed(let detail): "Sign-in failed: \(detail)"
        }
    }
}

enum HTTPForm {
    /// `application/x-www-form-urlencoded` body; encodes everything but unreserved characters.
    static func encode(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let body = fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    static func post(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = encode(fields)
        return request
    }
}

enum GoogleErrorBody {
    private struct API: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail
    }

    /// The human message from a Google API error body. Never echoes the raw
    /// body: a proxy or captive portal could put anything in there.
    static func message(from data: Data) -> String {
        guard let api = try? JSONDecoder().decode(API.self, from: data), let message = api.error.message else {
            return "no details"
        }
        return String(message.prefix(120))
    }
}

extension Data {
    /// Decodes base64url (RFC 4648 §5), with or without padding.
    init?(base64URLEncoded text: String) {
        var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
