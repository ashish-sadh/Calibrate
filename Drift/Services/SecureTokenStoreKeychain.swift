import Foundation
import Security
import DriftCore

/// iOS Keychain implementation of DriftCore's `SecureTokenStore` seam, injected
/// on `DriftPlatform.secureStore` at launch. Backs the friends/trainer sharing
/// session token.
///
/// Unlike `CloudVisionKey` (biometric-gated BYOK keys), this is deliberately
/// NOT biometric-gated: the sharing token is read on every REST call, so a Face
/// ID prompt each time would be unusable. `kSecAttrAccessibleAfterFirstUnlock-
/// ThisDeviceOnly` keeps it off iCloud Keychain / device backups while staying
/// readable in the background after the first unlock. The SQLite `sync_session`
/// row remains the durable floor; this is the protected upgrade.
final class SecureTokenStoreKeychain: SecureTokenStore {

    private let service = "com.drift.health.sharing"

    func string(forKey key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String?, forKey key: String) {
        // Idempotent replace: delete then (if non-nil) add.
        SecItemDelete(baseQuery(key) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var attributes = baseQuery(key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}
