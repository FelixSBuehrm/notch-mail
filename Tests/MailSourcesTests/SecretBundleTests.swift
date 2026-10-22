import Foundation
import Testing
@testable import MailSources

@Suite("Secret bundle")
struct SecretBundleTests {
    private let user = NSUserName()

    @Test func importsOlderSingleItemsOnce() {
        var bundle = SecretBundle()
        let items = [
            "\(SecretBundle.Legacy.clientID)|\(user)": "id",
            "\(SecretBundle.Legacy.clientSecret)|\(user)": "secret",
            "\(SecretBundle.Legacy.anthropic)|\(user)": "sk",
            "\(SecretBundle.Legacy.refresh)|alex@example.com": "1//r",
        ]
        var reads = 0
        let read: (String, String) -> String? = { service, account in
            reads += 1
            return items["\(service)|\(account)"]
        }

        let added = bundle.importMissing(refreshFor: ["alex@example.com"], read: read)
        #expect(added)
        #expect(bundle.googleClientID == "id")
        #expect(bundle.anthropicKey == "sk")
        #expect(bundle.anthropicWorkspace == nil)
        #expect(bundle.refreshTokens == ["alex@example.com": "1//r"])

        reads = 0
        let addedAgain = bundle.importMissing(refreshFor: ["alex@example.com"], read: read)
        #expect(!addedAgain)
        #expect(reads == 2)  // only the still-missing workspace and Microsoft app ID are looked for again
    }

    @Test func decodesItemsSavedByOlderVersions() throws {
        let old = #"{"googleClientID":"id","anthropicKey":"sk","refreshTokens":{"a@example.com":"t"}}"#

        let bundle = try JSONDecoder().decode(SecretBundle.self, from: Data(old.utf8))

        #expect(bundle.googleClientID == "id")
        #expect(bundle.refreshTokens == ["a@example.com": "t"])
        #expect(bundle.microsoftRefreshTokens.isEmpty)
    }

    @Test func roundTripsAsJSON() throws {
        var bundle = SecretBundle()
        bundle.anthropicKey = "sk"
        bundle.refreshTokens = ["a@example.com": "t"]

        let decoded = try JSONDecoder().decode(SecretBundle.self, from: try JSONEncoder().encode(bundle))

        #expect(decoded == bundle)
    }
}
