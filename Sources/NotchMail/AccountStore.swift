import Foundation
import MailSources
import NotchCore

/// Where connected accounts and reminders are remembered. Secrets go to the
/// Keychain; UserDefaults only holds the address and reminder dates (no mail content).
@MainActor
enum AccountStore {
    private static let gmailKey = "gmail.address"
    private static let remindersPrefix = "reminders."
    private static let replyNameKey = "reply.name"

    /// Label in the notch for the Gmail account.
    static let gmailLabel = "Gmail"

    /// The Anthropic key; the workspace ID is only needed for keys not tied to one.
    static func claudeCredentials() throws -> ClaudeCredentials {
        let secrets = try SecretStore.current()
        guard let key = secrets.anthropicKey, !key.isEmpty else { throw ClaudeError.missingKey }
        return ClaudeCredentials(apiKey: key, workspaceID: secrets.anthropicWorkspace)
    }

    /// The name replies are sent and signed with: `defaults write … reply.name "…"`, else the Mac's user name.
    static var replyName: String {
        // Demo mode never shows your real name (screenshots, recordings).
        if CommandLine.arguments.contains("--demo-only") { return "Alex Morgan" }
        let stored = UserDefaults.standard.string(forKey: replyNameKey)?.trimmingCharacters(in: .whitespaces)
        return stored.flatMap { $0.isEmpty ? nil : $0 } ?? NSFullUserName()
    }

    static func googleCredentials() throws -> GoogleClientCredentials {
        let secrets = try SecretStore.current()
        guard let id = secrets.googleClientID, !id.isEmpty,
              let secret = secrets.googleClientSecret, !secret.isEmpty else {
            throw MailSourceError.missingClientCredentials
        }
        return GoogleClientCredentials(clientID: id, clientSecret: secret)
    }

    static var gmailAddress: String? {
        UserDefaults.standard.string(forKey: gmailKey)
    }

    static func saveGmail(address: String, refreshToken: String) throws {
        try SecretStore.update { $0.refreshTokens[address] = refreshToken }
        UserDefaults.standard.set(address, forKey: gmailKey)
    }

    static func gmailRefreshToken(for address: String) throws -> String? {
        try SecretStore.current().refreshTokens[address]
    }

    /// Always forgets the account; a Keychain failure is still reported.
    static func forgetGmail() throws {
        guard let address = gmailAddress else { return }
        defer {
            UserDefaults.standard.removeObject(forKey: remindersPrefix + gmailAccount(address).id)
            UserDefaults.standard.removeObject(forKey: gmailKey)
        }
        try SecretStore.update { $0.refreshTokens[address] = nil }
        // An older single item, if one is left: best effort, the token is revoked at Google anyway.
        try? Keychain.delete(service: SecretBundle.Legacy.refresh, account: address)
    }

    // MARK: Outlook / Hotmail

    private static let outlookKey = "outlook.address"

    static var outlookAddress: String? {
        UserDefaults.standard.string(forKey: outlookKey)
    }

    static func microsoftClientID() throws -> String {
        guard let id = try SecretStore.current().microsoftClientID, !id.isEmpty else {
            throw MailSourceError.signInFailed("Microsoft app ID missing from the Keychain (notchmail.microsoft.clientid)")
        }
        return id
    }

    static func saveOutlook(address: String, refreshToken: String) throws {
        try saveOutlookToken(refreshToken, for: address)
        UserDefaults.standard.set(address, forKey: outlookKey)
    }

    static func saveOutlookToken(_ token: String, for address: String) throws {
        try SecretStore.update { $0.microsoftRefreshTokens[address] = token }
    }

    /// Only while that account is still the connected one.
    static func saveRenewedOutlookToken(_ token: String, for address: String) throws {
        guard outlookAddress == address else { return }
        try saveOutlookToken(token, for: address)
    }

    static func outlookRefreshToken(for address: String) throws -> String? {
        try SecretStore.current().microsoftRefreshTokens[address]
    }

    static func forgetOutlook() throws {
        guard let address = outlookAddress else { return }
        defer {
            UserDefaults.standard.removeObject(forKey: remindersPrefix + outlookAccount(address).id)
            UserDefaults.standard.removeObject(forKey: outlookKey)
        }
        try SecretStore.update { $0.microsoftRefreshTokens[address] = nil }
    }

    /// "Hotmail" for hotmail/live/msn addresses, "Outlook" otherwise.
    static func outlookAccount(_ address: String) -> MailAccount {
        let domain = address.split(separator: "@").last?.lowercased() ?? ""
        let label = ["hotmail", "live", "msn"].contains { domain.hasPrefix($0) } ? "Hotmail" : "Outlook"
        return MailAccount(id: "outlook:\(address)", name: label, address: address)
    }

    static func gmailAccount(_ address: String) -> MailAccount {
        MailAccount(id: "gmail:\(address)", name: gmailLabel, address: address)
    }

    static func reminders(for accountID: String) -> [MailMessage.ID: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: remindersPrefix + accountID) as? [String: Double] ?? [:]
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    static func saveReminders(_ reminders: [MailMessage.ID: Date], for accountID: String) {
        let raw = reminders.mapValues(\.timeIntervalSince1970)
        UserDefaults.standard.set(raw, forKey: remindersPrefix + accountID)
    }
}

/// The one Keychain item with all secrets, read once per launch and kept in memory.
@MainActor
enum SecretStore {
    static let service = "notchmail.secrets"
    private static var cached: SecretBundle?

    /// Loads the bundle, importing any older single items that are still missing.
    static func current() throws -> SecretBundle {
        if let cached { return cached }
        var bundle = SecretBundle()
        if let json = try Keychain.read(service: service, account: NSUserName()) {
            // Unreadable means stop, never "start empty and save over it".
            bundle = try JSONDecoder().decode(SecretBundle.self, from: Data(json.utf8))
        }
        let addresses = [UserDefaults.standard.string(forKey: "gmail.address")].compactMap { $0 }
        if bundle.importMissing(refreshFor: addresses, read: { try? Keychain.read(service: $0, account: $1) }) {
            try save(bundle)
        }
        cached = bundle
        return bundle
    }

    static func update(_ change: (inout SecretBundle) -> Void) throws {
        var bundle = try current()
        change(&bundle)
        try save(bundle)
        cached = bundle
    }

    private static func save(_ bundle: SecretBundle) throws {
        let json = String(decoding: try JSONEncoder().encode(bundle), as: UTF8.self)
        try Keychain.write(json, service: service, account: NSUserName())
    }
}
