import Foundation

/// Anything that hands out OAuth access tokens (Google, Microsoft).
public protocol AccessTokenProviding: Sendable {
    func accessToken(forceRefresh: Bool) async throws -> String
}

extension GoogleTokenProvider: AccessTokenProviding {}
extension MicrosoftTokenProvider: AccessTokenProviding {}

/// Sends API requests with the account's access token; on 401 it renews the
/// token once and retries.
public struct APIRequester: Sendable {
    let tokens: any AccessTokenProviding
    let transport: any HTTPTransport
    /// Sent with every request, e.g. Graph's `Prefer` header.
    let headers: [String: String]

    public init(tokens: any AccessTokenProviding, transport: any HTTPTransport, headers: [String: String] = [:]) {
        self.tokens = tokens
        self.transport = transport
        self.headers = headers
    }

    func send(_ request: URLRequest, isRetry: Bool = false) async throws -> Data {
        var authorized = request
        let token = try await tokens.accessToken(forceRefresh: isRetry)
        authorized.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        for (name, value) in headers where authorized.value(forHTTPHeaderField: name) == nil {
            authorized.setValue(value, forHTTPHeaderField: name)
        }

        let (data, response) = try await transport.send(authorized)
        switch response.statusCode {
        case 200..<300:
            return data
        case 401 where !isRetry:
            return try await send(request, isRetry: true)
        default:
            throw MailSourceError.http(status: response.statusCode, message: GoogleErrorBody.message(from: data))
        }
    }

    func get<T: Decodable & Sendable>(_ url: URL, what: String) async throws -> T {
        let data = try await send(URLRequest(url: url))
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MailSourceError.invalidResponse("Answer for \(what) didn't parse")
        }
    }

    func post(_ url: URL, json: Data?, method: String = "POST") async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = json
        }
        return try await send(request)
    }
}
