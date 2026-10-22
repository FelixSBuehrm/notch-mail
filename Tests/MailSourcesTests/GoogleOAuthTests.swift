import Foundation
import Testing
@testable import MailSources

@Suite("Google sign-in")
struct GoogleOAuthTests {
    let credentials = GoogleClientCredentials(clientID: "id-123.apps.googleusercontent.com", clientSecret: "secret-xyz")
    let redirect = URL(string: "http://127.0.0.1:53682")!

    @Test func pkceChallengeMatchesTheRFCExample() {
        // RFC 7636, appendix B.
        #expect(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifiersAreLongAndUnique() {
        let a = PKCE.generate(), b = PKCE.generate()

        #expect(a.verifier.count >= 43 && a.verifier.count <= 128)
        #expect(a.verifier != b.verifier)
        #expect(a.challenge == PKCE.challenge(for: a.verifier))
    }

    @Test func authorizationURLAsksForOfflineGmailAccessWithPKCE() throws {
        let pkce = PKCE(verifier: "v", challenge: "c")
        let url = GoogleOAuth.authorizationURL(credentials: credentials, redirectURI: redirect, pkce: pkce, state: "s1")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })

        #expect(url.host == "accounts.google.com")
        #expect(query["client_id"] == credentials.clientID)
        #expect(query["redirect_uri"] == "http://127.0.0.1:53682")
        #expect(query["response_type"] == "code")
        #expect(query["code_challenge"] == "c")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["access_type"] == "offline")
        #expect(query["state"] == "s1")
        #expect(query["scope"]?.contains("https://www.googleapis.com/auth/gmail.modify") == true)
        #expect(query["client_secret"] == nil)
    }

    @Test func tokenRequestSendsCodeAndVerifier() {
        let request = GoogleOAuth.tokenRequest(code: "4/abc", credentials: credentials, redirectURI: redirect, verifier: "ver")
        let fields = formFields(request)

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(fields["grant_type"] == "authorization_code")
        #expect(fields["code"] == "4/abc")
        #expect(fields["code_verifier"] == "ver")
        #expect(fields["client_secret"] == "secret-xyz")
        #expect(fields["redirect_uri"] == "http://127.0.0.1:53682")
    }

    @Test func refreshRequestUsesTheRefreshToken() {
        let fields = formFields(GoogleOAuth.refreshRequest(refreshToken: "1//r", credentials: credentials))

        #expect(fields["grant_type"] == "refresh_token")
        #expect(fields["refresh_token"] == "1//r")
    }

    @Test func parsesATokenResponseWithEmailFromTheIDToken() throws {
        let payload = base64URL(#"{"email":"alex@example.com","email_verified":true}"#)
        let json = #"{"access_token":"ya29.a","expires_in":3599,"refresh_token":"1//r","id_token":"h.\#(payload).sig"}"#
        let now = Date(timeIntervalSince1970: 1_000)

        let token = try GoogleOAuth.parseTokenResponse(Data(json.utf8), now: now)

        #expect(token.accessToken == "ya29.a")
        #expect(token.refreshToken == "1//r")
        #expect(token.email == "alex@example.com")
        // Renews a minute early.
        #expect(token.expiresAt == now.addingTimeInterval(3_599 - 60))
    }

    @Test func reportsGrantedScopesAndLowercasesTheEmail() throws {
        let payload = base64URL(#"{"email":"Alex@Example.COM"}"#)
        let json = #"{"access_token":"a","expires_in":3600,"scope":"openid https://www.googleapis.com/auth/gmail.modify","id_token":"h.\#(payload).s"}"#

        let token = try GoogleOAuth.parseTokenResponse(Data(json.utf8), now: .now)

        #expect(token.email == "alex@example.com")
        #expect(token.grantsGmail)
    }

    @Test func missingGmailScopeIsDetected() throws {
        let json = #"{"access_token":"a","expires_in":3600,"scope":"openid email"}"#

        #expect(!(try GoogleOAuth.parseTokenResponse(Data(json.utf8), now: .now).grantsGmail))
    }

    @Test func revokeRequestPostsTheToken() {
        let request = GoogleOAuth.revokeRequest(token: "1//r")

        #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/revoke")
        #expect(formFields(request)["token"] == "1//r")
    }

    @Test func serverErrorBodiesAreNotEchoedRaw() {
        #expect(GoogleErrorBody.message(from: Data("<html>proxy page with secrets</html>".utf8)) == "no details")
    }

    @Test func revokedRefreshTokenIsReportedAsSuch() {
        let json = #"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#

        #expect(throws: MailSourceError.authorizationRevoked) {
            try GoogleOAuth.parseTokenResponse(Data(json.utf8), now: .now)
        }
    }

    @Test func redirectRequestLineYieldsCodeAndState() {
        let query = LoopbackReceiver.queryItems(fromRequest: "GET /?state=s1&code=4%2Fabc&scope=x HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")

        #expect(query?["code"] == "4/abc")
        #expect(query?["state"] == "s1")
        #expect(LoopbackReceiver.queryItems(fromRequest: "garbage") == nil)
    }
}
