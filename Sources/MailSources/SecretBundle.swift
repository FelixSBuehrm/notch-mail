import Foundation

/// Every secret Notch Mail uses, kept together in one Keychain item that the
/// app creates itself. macOS doesn't ask an app about items it created, so
/// there is at most one round of prompts: when older, separately stored items
/// are imported the first time.
public struct SecretBundle: Codable, Equatable, Sendable {
    public var googleClientID: String?
    public var googleClientSecret: String?
    public var anthropicKey: String?
    public var anthropicWorkspace: String?
    /// Google refresh tokens by account address.
    public var refreshTokens: [String: String] = [:]
    /// The Microsoft app registration (a public client: no secret).
    public var microsoftClientID: String?
    /// Microsoft refresh tokens by account address; replaced on every renewal.
    public var microsoftRefreshTokens: [String: String] = [:]

    public init() {}

    /// Every field optional, so items saved by older versions (fewer fields) still decode.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        googleClientID = try c.decodeIfPresent(String.self, forKey: .googleClientID)
        googleClientSecret = try c.decodeIfPresent(String.self, forKey: .googleClientSecret)
        anthropicKey = try c.decodeIfPresent(String.self, forKey: .anthropicKey)
        anthropicWorkspace = try c.decodeIfPresent(String.self, forKey: .anthropicWorkspace)
        refreshTokens = try c.decodeIfPresent([String: String].self, forKey: .refreshTokens) ?? [:]
        microsoftClientID = try c.decodeIfPresent(String.self, forKey: .microsoftClientID)
        microsoftRefreshTokens = try c.decodeIfPresent([String: String].self, forKey: .microsoftRefreshTokens) ?? [:]
    }

    /// Fills only what's missing, from `read` (e.g. older single items). True if anything was added.
    public mutating func importMissing(
        refreshFor addresses: [String],
        read: (_ service: String, _ account: String) -> String?
    ) -> Bool {
        let before = self
        let user = NSUserName()
        func fill(_ value: inout String?, _ service: String) {
            if value?.isEmpty ?? true, let found = read(service, user), !found.isEmpty { value = found }
        }
        fill(&googleClientID, SecretBundle.Legacy.clientID)
        fill(&googleClientSecret, SecretBundle.Legacy.clientSecret)
        fill(&anthropicKey, SecretBundle.Legacy.anthropic)
        fill(&anthropicWorkspace, SecretBundle.Legacy.anthropicWorkspace)
        fill(&microsoftClientID, SecretBundle.Legacy.microsoftClientID)
        for address in addresses where refreshTokens[address] == nil {
            if let token = read(SecretBundle.Legacy.refresh, address), !token.isEmpty { refreshTokens[address] = token }
        }
        return self != before
    }

    /// The single items people create with `security add-generic-password` (see docs/google-setup.md).
    public enum Legacy {
        public static let clientID = "notchmail.google.clientid"
        public static let clientSecret = "notchmail.google.secret"
        public static let refresh = "notchmail.google.refresh"
        public static let anthropic = "notchmail.anthropic"
        public static let anthropicWorkspace = "notchmail.anthropic.workspace"
        public static let microsoftClientID = "notchmail.microsoft.clientid"
    }
}
