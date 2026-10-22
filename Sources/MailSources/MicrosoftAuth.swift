import Foundation

/// Microsoft sign-in for personal accounts (Outlook.com, Hotmail, Live) with
/// the device-code flow: the user types a short code on microsoft.com once.
/// No redirect URI or client secret needed; the app registration only has to
/// allow public client flows.
public enum MicrosoftAuth {
    static let authority = URL(string: "https://login.microsoftonline.com/consumers/oauth2/v2.0/")!
    static let scopes = "offline_access openid email User.Read Mail.ReadWrite Mail.Send"

    public struct DeviceCode: Equatable, Sendable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURL: URL
        public let expiresAt: Date
        public let interval: TimeInterval
    }

    public struct Tokens: Equatable, Sendable {
        public let accessToken: String
        public let refreshToken: String
        public let expiresAt: Date
    }

    static func deviceCodeRequest(clientID: String) -> URLRequest {
        form(authority.appending(path: "devicecode"), ["client_id": clientID, "scope": scopes])
    }

    static func parseDeviceCode(_ data: Data, now: Date) throws -> DeviceCode {
        struct Body: Decodable {
            let device_code: String
            let user_code: String
            let verification_uri: String
            let expires_in: Double
            let interval: Double?
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data),
              let url = URL(string: body.verification_uri), url.scheme == "https",
              let host = url.host?.lowercased(),
              ["microsoft.com", "live.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else {
            throw MailSourceError.signInFailed(errorText(data) ?? "Microsoft didn't start the sign-in")
        }
        return DeviceCode(
            deviceCode: body.device_code, userCode: body.user_code, verificationURL: url,
            expiresAt: now.addingTimeInterval(body.expires_in), interval: max(body.interval ?? 5, 1)
        )
    }

    /// Waits until the user has entered the code and allowed access.
    public static func signIn(
        clientID: String,
        transport: any HTTPTransport,
        show: @Sendable (DeviceCode) async -> Void,
        sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        now: @Sendable () -> Date = { Date() }
    ) async throws -> Tokens {
        let (data, _) = try await transport.send(deviceCodeRequest(clientID: clientID))
        let code = try parseDeviceCode(data, now: now())
        await show(code)
        var interval = code.interval
        while now() < code.expiresAt {
            try await sleep(interval)
            let request = form(authority.appending(path: "token"), [
                "client_id": clientID,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "device_code": code.deviceCode,
            ])
            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await transport.send(request)
            } catch is URLError {
                continue  // a network blip; keep waiting until the code expires
            }
            if response.statusCode == 200 { return try parseTokens(data, now: now()) }
            switch errorCode(data) {
            case "authorization_pending": continue
            case "slow_down": interval += 5
            case "authorization_declined", "access_denied": throw MailSourceError.signInFailed("Access was denied")
            case "expired_token": throw MailSourceError.signInFailed("The code expired; try again")
            default: throw MailSourceError.signInFailed(errorText(data) ?? "Microsoft sign-in failed")
            }
        }
        throw MailSourceError.signInFailed("The code expired; try again")
    }

    static func refreshRequest(clientID: String, refreshToken: String) -> URLRequest {
        form(authority.appending(path: "token"), [
            "client_id": clientID, "grant_type": "refresh_token", "refresh_token": refreshToken, "scope": scopes,
        ])
    }

    static func parseTokens(_ data: Data, now: Date) throws -> Tokens {
        struct Body: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            // These all mean: sign in again.
            if ["invalid_grant", "interaction_required", "invalid_client", "unauthorized_client"].contains(errorCode(data) ?? "") {
                throw MailSourceError.authorizationRevoked
            }
            throw MailSourceError.invalidResponse(errorText(data) ?? "Microsoft token answer didn't parse")
        }
        guard let refresh = body.refresh_token else {
            throw MailSourceError.signInFailed("Microsoft didn't return a refresh token")
        }
        // A minute early, so a token never expires mid-request.
        return Tokens(accessToken: body.access_token, refreshToken: refresh, expiresAt: now.addingTimeInterval(body.expires_in - 60))
    }

    static func errorCode(_ data: Data) -> String? {
        (try? JSONDecoder().decode(JSONValue.self, from: data))?["error"]?.stringValue
    }

    static func errorText(_ data: Data) -> String? {
        (try? JSONDecoder().decode(JSONValue.self, from: data))?["error_description"]?.stringValue
            .map { String($0.split(separator: "\r\n").first ?? Substring($0)).prefix(200) }.map(String.init)
    }

    static func form(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(fields.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }.joined(separator: "&").utf8)
        return request
    }
}

/// Hands out access tokens for one Microsoft account. Microsoft replaces the
/// refresh token on every renewal, so each new one is handed to `persist`.
public actor MicrosoftTokenProvider {
    private let clientID: String
    private var refreshToken: String
    private let transport: any HTTPTransport
    private let persist: @Sendable (String) async -> Void
    private let now: @Sendable () -> Date
    private var current: (token: String, expiresAt: Date)?
    private var renewal: Task<String, Error>?

    public init(
        clientID: String, refreshToken: String, transport: any HTTPTransport,
        persist: @escaping @Sendable (String) async -> Void,
        current: (token: String, expiresAt: Date)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.current = current
        self.clientID = clientID
        self.refreshToken = refreshToken
        self.transport = transport
        self.persist = persist
        self.now = now
    }

    public func accessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let current, current.expiresAt > now() { return current.token }
        if let renewal { return try await renewal.value }
        let task = Task { try await renew() }
        renewal = task
        defer { renewal = nil }
        return try await task.value
    }

    private func renew() async throws -> String {
        let (data, _) = try await transport.send(MicrosoftAuth.refreshRequest(clientID: clientID, refreshToken: refreshToken))
        let tokens = try MicrosoftAuth.parseTokens(data, now: now())
        current = (tokens.accessToken, tokens.expiresAt)
        if tokens.refreshToken != refreshToken {
            refreshToken = tokens.refreshToken
            await persist(tokens.refreshToken)
        }
        return tokens.accessToken
    }
}
