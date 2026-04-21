import Foundation
import Security
import LocalAuthentication

/// Which cloud vision provider a key belongs to. Stored as the Keychain
/// `kSecAttrAccount` value so two keys can coexist under one service.
enum CloudVisionProvider: String, CaseIterable, Codable, Sendable {
    case anthropic
    case openai
    case gemini

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai:    return "OpenAI (GPT-4o)"
        case .gemini:    return "Google (Gemini 2.5)"
        }
    }
}

/// Secure, biometric-gated storage for BYOK cloud vision API keys. #224 / #263.
///
/// Design:
/// - Keychain is the source of truth; we never write the key to UserDefaults,
///   plist, file, log, or crash report.
/// - `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` keeps the key off iCloud
///   Keychain backups and local-only.
/// - `SecAccessControl` with `.userPresence` forces a Face ID / passcode
///   prompt on every retrieval (biometry with passcode fallback), so a stolen
///   unlocked device still cannot exfiltrate the key unattended.
/// - `has(provider:)` uses a metadata-only query (`kSecReturnData: false`) so
///   we can gate UI without triggering biometrics.
/// - An in-memory actor cache (`KeyCache`) lets the same app session reuse the
///   key after one unlock. Cache is dropped on `clear()` and when the app
///   resigns active (see Photo Log service layer).
enum CloudVisionKey {
    static let service = "com.drift.photolog"

    enum StorageError: Error, Equatable {
        case notFound
        case biometricUnavailable
        case keychainStatus(OSStatus)
    }

    // MARK: - Public API

    /// Store a key for the given provider. Overwrites any existing value.
    static func set(_ key: String, for provider: CloudVisionProvider) throws {
        let access = try makeAccessControl()
        let data = Data(key.utf8)

        // Delete any existing item first — `SecItemUpdate` cannot change the
        // access control object, so we always rewrite.
        SecItemDelete(baseQuery(for: provider) as CFDictionary)

        var attributes = baseQuery(for: provider)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessControl as String] = access

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StorageError.keychainStatus(status)
        }
        KeyCache.shared.set(key, for: provider)
    }

    /// Fetch the stored key, triggering the biometric/passcode gate. Returns
    /// `nil` if no key is stored. Throws on keychain errors or when biometrics
    /// are unavailable or cancelled.
    static func get(for provider: CloudVisionProvider) async throws -> String? {
        if let cached = KeyCache.shared.get(for: provider) {
            return cached
        }
        let context = LAContext()
        context.localizedReason = "Unlock Photo Log key"

        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw StorageError.keychainStatus(status)
            }
            KeyCache.shared.set(key, for: provider)
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw StorageError.keychainStatus(status)
        }
    }

    /// Non-prompting existence check. Attaches an `LAContext` with
    /// `interactionNotAllowed = true` so `SecItemCopyMatching` returns
    /// `errSecInteractionNotAllowed` (instead of prompting Face ID /
    /// passcode) when the protected item exists. We treat that status as
    /// "exists" so UI gates can be computed on every body re-render without
    /// stacking passcode popups (#275).
    static func has(provider: CloudVisionProvider) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true

        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = false
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        // errSecSuccess: item exists and was returned without UI.
        // errSecInteractionNotAllowed: item exists but would need UI — still "exists".
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    /// Delete the stored key. Safe to call when no key exists.
    static func clear(for provider: CloudVisionProvider) throws {
        let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw StorageError.keychainStatus(status)
        }
        KeyCache.shared.clear(for: provider)
    }

    /// Force-drop all cached keys. Called from app-lifecycle hooks (resign
    /// active, memory warning) so a backgrounded session re-prompts.
    static func dropCache() {
        KeyCache.shared.dropAll()
    }

    // MARK: - Internals

    private static func baseQuery(for provider: CloudVisionProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }

    private static func makeAccessControl() throws -> SecAccessControl {
        var err: Unmanaged<CFError>?
        // .userPresence = biometry with passcode fallback. Keeps a user who
        // rotates Face ID / fingerprints from getting locked out of their
        // own key while still gating exfiltration on a stolen device.
        let flags: SecAccessControlCreateFlags = [.userPresence]
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            flags,
            &err
        ) else {
            if let err = err?.takeRetainedValue() {
                throw StorageError.keychainStatus(OSStatus(CFErrorGetCode(err)))
            }
            throw StorageError.biometricUnavailable
        }
        return access
    }

    // MARK: - In-memory cache

    /// Synchronized cache. Used by public static API that must stay sync
    /// (e.g. `set`/`clear` during auth flows). NSLock keeps mutations ordered
    /// so a rapid `set("a"); set("b")` pair can't race cache writes.
    private final class KeyCache: @unchecked Sendable {
        static let shared = KeyCache()
        private let lock = NSLock()
        private var values: [CloudVisionProvider: String] = [:]

        func get(for provider: CloudVisionProvider) -> String? {
            lock.lock(); defer { lock.unlock() }
            return values[provider]
        }

        func set(_ value: String, for provider: CloudVisionProvider) {
            lock.lock(); defer { lock.unlock() }
            values[provider] = value
        }

        func clear(for provider: CloudVisionProvider) {
            lock.lock(); defer { lock.unlock() }
            values.removeValue(forKey: provider)
        }

        func dropAll() {
            lock.lock(); defer { lock.unlock() }
            values.removeAll()
        }
    }
}
