import Foundation
import Security

/// Stores the GitHub user token in the Keychain.
/// - `WhenUnlockedThisDeviceOnly`: never synced to iCloud, never in backups,
///   unreadable while the device is locked.
nonisolated enum KeychainStore {
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        var errorDescription: String? {
            if case .unexpectedStatus(let status) = self { return "Keychain error \(status)" }
            return nil
        }
    }

    private static let service = "vaultreader.github"
    private static let account = "user-token"

    private static func baseQuery(dataProtection: Bool = true) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        #if os(macOS)
        if dataProtection { query[kSecUseDataProtectionKeychain as String] = true }
        #endif
        return query
    }

    static func save(_ token: String) throws {
        delete()
        var status = add(token, dataProtection: true)
        #if os(macOS)
        // Unsigned local builds lack the entitlement for the data protection keychain.
        if status == errSecMissingEntitlement { status = add(token, dataProtection: false) }
        #endif
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    private static func add(_ token: String, dataProtection: Bool) -> OSStatus {
        var query = baseQuery(dataProtection: dataProtection)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        query[kSecAttrSynchronizable as String] = kCFBooleanFalse
        return SecItemAdd(query as CFDictionary, nil)
    }

    static func load() -> String? {
        for dataProtection in [true, false] {
            var query = baseQuery(dataProtection: dataProtection)
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var item: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
               let data = item as? Data,
               let token = String(data: data, encoding: .utf8),
               GitHubToken.isWellFormed(token) {
                return token
            }
        }
        return nil
    }

    static func delete() {
        SecItemDelete(baseQuery(dataProtection: true) as CFDictionary)
        SecItemDelete(baseQuery(dataProtection: false) as CFDictionary)
    }
}

nonisolated enum GitHubToken {
    /// GitHub tokens are short ASCII strings like `ghu_…`. Rejecting anything else keeps
    /// garbage (or header-injection attempts such as CR/LF) out of the Authorization header.
    static func isWellFormed(_ token: String) -> Bool {
        (20...255).contains(token.utf8.count)
            && token.utf8.allSatisfy { c in
                (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F
            }
    }
}
