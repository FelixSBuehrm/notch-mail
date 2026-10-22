import Foundation
import Security

/// Generic passwords in the login Keychain. Secrets never touch disk or logs otherwise.
public enum Keychain {
    public static func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status, action: "read \(service)")
        }
    }

    public static func write(_ value: String, service: String, account: String) throws {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        let status = SecItemUpdate(match as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = match
            item[kSecValueData as String] = data
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added, action: "save \(service)") }
        } else if status != errSecSuccess {
            throw KeychainError(status: status, action: "update \(service)")
        }
    }

    public static func delete(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status, action: "delete \(service)")
        }
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus
    public let action: String

    public var errorDescription: String? {
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "Keychain couldn't \(action): \(reason)"
    }
}
