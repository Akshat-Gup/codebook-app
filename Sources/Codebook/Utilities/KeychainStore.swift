import Foundation
import Security

enum KeychainStore {
    private static let service = "com.codebook.mac"
    private static let legacyAccount = "openai-api-key"

    /// Thread-safe in-memory cache to avoid repeated Keychain reads.
    /// NSCache is inherently thread-safe; nonisolated(unsafe) suppresses the Sendable diagnostic.
    private nonisolated(unsafe) static let cache = NSCache<NSString, NSString>()

    private static func cachedValue(for account: String) -> String? {
        cache.object(forKey: account as NSString) as String?
    }

    private static func setCachedValue(_ value: String, for account: String) {
        cache.setObject(value as NSString, forKey: account as NSString)
    }

    static func loadAPIKey() -> String {
        loadValue(account: legacyAccount)
    }

    static func loadAPIKey(for provider: InsightsProvider) -> String {
        for account in [provider.keychainAccount] + provider.legacyKeychainAccounts {
            let value = loadValue(account: account)
            if !value.isEmpty {
                return value
            }
        }
        return ""
    }

    static func saveAPIKey(_ apiKey: String) {
        saveValue(apiKey, account: legacyAccount)
    }

    static func saveAPIKey(_ apiKey: String, for provider: InsightsProvider) {
        saveValue(apiKey, account: provider.keychainAccount)

        if provider.legacyKeychainAccounts.contains(legacyAccount) {
            saveValue(apiKey, account: legacyAccount)
        }
    }

    static func loadValue(account: String) -> String {
        if let cached = cachedValue(for: account) { return cached }
        let value = loadSecret(account: account)
        setCachedValue(value, for: account)
        return value
    }

    static func saveValue(_ value: String, account: String) {
        setCachedValue(value, for: account)
        saveSecret(value, account: account)
    }

    private static func loadSecret(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    private static func saveSecret(_ value: String, account: String) {
        guard !RuntimePolicy.shared.readOnly else { return }
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        guard !value.isEmpty else { return }

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
