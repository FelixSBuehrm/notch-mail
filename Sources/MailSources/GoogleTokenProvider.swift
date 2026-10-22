import Foundation

/// Hands out a valid access token, renewing it with the refresh token when needed.
/// An actor, so parallel requests share one renewal.
public actor GoogleTokenProvider {
    private let credentials: GoogleClientCredentials
    private let refreshToken: String
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private var current: (token: String, expiresAt: Date)?
    private var renewal: Task<String, Error>?

    public init(
        credentials: GoogleClientCredentials,
        refreshToken: String,
        transport: any HTTPTransport,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.credentials = credentials
        self.refreshToken = refreshToken
        self.transport = transport
        self.now = now
    }

    /// `forceRefresh`: the server just rejected the current token.
    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let current, current.expiresAt > now() { return current.token }
        if let renewal { return try await renewal.value }

        let task = Task { try await renew() }
        renewal = task
        defer { renewal = nil }
        return try await task.value
    }

    private func renew() async throws -> String {
        let request = GoogleOAuth.refreshRequest(refreshToken: refreshToken, credentials: credentials)
        let (data, _) = try await transport.send(request)
        let response = try GoogleOAuth.parseTokenResponse(data, now: now())
        current = (response.accessToken, response.expiresAt)
        return response.accessToken
    }
}
