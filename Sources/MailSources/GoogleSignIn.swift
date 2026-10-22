import Foundation

/// The browser sign-in: open Google's page, catch the redirect, swap the code for tokens.
public enum GoogleSignIn {
    /// - Parameter open: opens a URL in the browser (AppKit lives in the app).
    public static func run(
        credentials: GoogleClientCredentials,
        transport: any HTTPTransport,
        open: @Sendable (URL) -> Void
    ) async throws -> TokenResponse {
        let state = PKCE.generate().verifier
        let receiver = try LoopbackReceiver(expectedState: state)
        defer { receiver.stop() }
        let redirect = try await receiver.start()
        let pkce = PKCE.generate()

        open(GoogleOAuth.authorizationURL(credentials: credentials, redirectURI: redirect, pkce: pkce, state: state))
        let query = try await receiver.waitForRedirect()

        if let error = query["error"] {
            throw MailSourceError.signInFailed(error == "access_denied" ? "Access was denied" : error)
        }
        // The receiver only accepts our state; checked again here on purpose.
        guard query["state"] == state else { throw MailSourceError.signInFailed("State mismatch") }
        guard let code = query["code"], !code.isEmpty else { throw MailSourceError.signInFailed("No code") }

        let request = GoogleOAuth.tokenRequest(code: code, credentials: credentials, redirectURI: redirect, verifier: pkce.verifier)
        let (data, _) = try await transport.send(request)
        let token = try GoogleOAuth.parseTokenResponse(data, now: Date())
        guard token.refreshToken != nil else {
            throw MailSourceError.signInFailed("Google didn't return a refresh token")
        }
        guard token.grantsGmail else {
            throw MailSourceError.signInFailed("Gmail access wasn't allowed on Google's page")
        }
        return token
    }
}
