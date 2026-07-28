import Foundation

/// Platform-secure storage for the sharing auth session token, injected onto
/// `DriftPlatform.secureStore` from the app shells (iOS wraps Keychain, Android
/// wraps EncryptedSharedPreferences). Cross-platform sharing code in DriftCore
/// reaches secure storage only through this seam — mirrors `HealthDataProvider`.
///
/// The SQLite `sync_session` table is the durable floor that works with no
/// adapter registered (macOS/tests, or before an app wires Keychain); a
/// registered store is the more-protected upgrade. Keys are opaque strings.
public protocol SecureTokenStore: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
}
