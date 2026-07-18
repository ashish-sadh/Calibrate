import Foundation
import DriftCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Handles encrypted local storage of lab report files using CryptoKit + iOS Data Protection.
public enum LabReportStorage {

    private static let reportsDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LabReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Key stored in the Keychain with iOS Data Protection (thisDeviceOnly) on
    /// Apple platforms; in a 0600 key file on Android until the Keystore-backed
    /// secure-store adapter lands.
    private static var encryptionKey: SymmetricKey {
        if let existing = loadPersistedKey() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        persistKey(key)
        return key
    }

    // MARK: - Public API

    /// Encrypt and save file data locally. Returns the SHA256 hash identifier.
    public static func save(data: Data, fileName: String) throws -> String {
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        let encrypted = try encrypt(data: data)
        let fileURL = reportsDir.appendingPathComponent(hash)
        #if canImport(Darwin)
        try encrypted.write(to: fileURL, options: .completeFileProtection)
        #else
        try encrypted.write(to: fileURL, options: .atomic)
        #endif
        Log.biomarkers.info("Saved encrypted report: \(fileName) (\(data.count) bytes)")
        return hash
    }

    /// Load and decrypt a previously saved file.
    public static func load(hash: String) throws -> Data {
        let fileURL = reportsDir.appendingPathComponent(hash)
        let encrypted = try Data(contentsOf: fileURL)
        return try decrypt(data: encrypted)
    }

    /// Delete a saved file.
    public static func delete(hash: String) {
        let fileURL = reportsDir.appendingPathComponent(hash)
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Encryption

    private static func encrypt(data: Data) throws -> Data {
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey)
        guard let combined = sealedBox.combined else {
            throw StorageError.encryptionFailed
        }
        return combined
    }

    private static func decrypt(data: Data) throws -> Data {
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: encryptionKey)
    }

    // MARK: - Key persistence

    #if canImport(Security)
    private static let keychainAccount = "com.drift.health.labReportKey"

    private static func persistKey(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadPersistedKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return SymmetricKey(data: data)
    }
    #else
    private static var keyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("labreport.key")
    }

    private static func persistKey(_ key: SymmetricKey) {
        let keyData = key.withUnsafeBytes { Data($0) }
        try? FileManager.default.createDirectory(
            at: keyFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? keyData.write(to: keyFileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: keyFileURL.path)
    }

    private static func loadPersistedKey() -> SymmetricKey? {
        guard let data = try? Data(contentsOf: keyFileURL), data.count == 32 else { return nil }
        return SymmetricKey(data: data)
    }
    #endif

    enum StorageError: LocalizedError {
        case encryptionFailed
        var errorDescription: String? { "Failed to encrypt lab report" }
    }
}
