import CryptoKit
import Foundation

/// The "Notch Mail" desktop client from the Google Cloud project.
public struct GoogleClientCredentials: Sendable, Equatable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

/// Proof Key for Code Exchange (RFC 7636), so an intercepted code is useless.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 48)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        let verifier = Data(bytes).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge(for: verifier))
    }

    public static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

public struct TokenResponse: Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date
    /// Only on the first exchange (and not always on refresh).
    public let refreshToken: String?
    /// From the ID token, lowercased; only when the `email` scope was granted.
    public let email: String?
    /// Google lets people untick permissions on the consent screen.
    public let grantedScopes: Set<String>

    public var grantsGmail: Bool { grantedScopes.contains(GoogleOAuth.gmailScope) }
}

/// Builds Google OAuth requests and reads the answers. No networking here.
public enum GoogleOAuth {
    static let authEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    static let gmailScope = "https://www.googleapis.com/auth/gmail.modify"
    /// Read, label, trash and (for replies later) send. Not permanent delete.
    /// Lets Claude find documents while drafting replies. Optional: Gmail works without it.
    static let driveScope = "https://www.googleapis.com/auth/drive.readonly"
    static let scopes = [gmailScope, driveScope, "openid", "email"]
    /// Renew a little before Google's expiry so a request never races it.
    static let expiryMargin: TimeInterval = 60

    public static func authorizationURL(
        credentials: GoogleClientCredentials, redirectURI: URL, pkce: PKCE, state: String
    ) -> URL {
        var components = URLComponents(url: authEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            // Always ask, so Google hands out a refresh token again after a reconnect.
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    public static func tokenRequest(
        code: String, credentials: GoogleClientCredentials, redirectURI: URL, verifier: String
    ) -> URLRequest {
        HTTPForm.post(tokenEndpoint, [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("client_id", credentials.clientID),
            ("client_secret", credentials.clientSecret),
            ("redirect_uri", redirectURI.absoluteString),
            ("code_verifier", verifier),
        ])
    }

    /// Ends the sign-in at Google, so the stored refresh token is worthless.
    public static func revokeRequest(token: String) -> URLRequest {
        HTTPForm.post(revokeEndpoint, [("token", token)])
    }

    public static func refreshRequest(refreshToken: String, credentials: GoogleClientCredentials) -> URLRequest {
        HTTPForm.post(tokenEndpoint, [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", credentials.clientID),
            ("client_secret", credentials.clientSecret),
        ])
    }

    private struct Body: Decodable {
        let access_token: String?
        let expires_in: Double?
        let refresh_token: String?
        let id_token: String?
        let scope: String?
        let error: String?
        let error_description: String?
    }

    public static func parseTokenResponse(_ data: Data, now: Date) throws -> TokenResponse {
        guard let body = try? JSONDecoder().decode(Body.self, from: data) else {
            throw MailSourceError.invalidResponse("Token response is not JSON")
        }
        if let error = body.error {
            if error == "invalid_grant" { throw MailSourceError.authorizationRevoked }
            throw MailSourceError.signInFailed(body.error_description ?? error)
        }
        guard let access = body.access_token, let expiresIn = body.expires_in else {
            throw MailSourceError.invalidResponse("Token response without access token")
        }
        return TokenResponse(
            accessToken: access,
            expiresAt: now.addingTimeInterval(max(0, expiresIn - expiryMargin)),
            refreshToken: body.refresh_token,
            email: body.id_token.flatMap(email(fromIDToken:))?.lowercased(),
            grantedScopes: Set((body.scope ?? "").split(separator: " ").map(String.init))
        )
    }

    /// Reads the `email` claim. The token comes straight from Google over TLS,
    /// so it's used for display only and not verified further.
    static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let data = Data(base64URLEncoded: String(parts[1])) else { return nil }
        let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return claims?["email"] as? String
    }
}
