import Foundation
import DriftCore
import CryptoKit

/// Handles encrypted local storage of lab report files using CryptoKit + iOS Data Protection.
enum LabReportStorage {

    private static let reportsDir: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LabReports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Key stored in Keychain with iOS Data Protection (thisDeviceOnly).
    private static var encryptionKey: SymmetricKey {
        if let existing = loadKeyFromKeychain() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        saveKeyToKeychain(key)
        return key
    }

    // MARK: - Public API

    /// Encrypt and save file data locally. Returns the SHA256 hash identifier.
    static func save(data: Data, fileName: String) throws -> String {
        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        let encrypted = try encrypt(data: data)
        let fileURL = reportsDir.appendingPathComponent(hash)
        try encrypted.write(to: fileURL, options: .completeFileProtection)
        Log.biomarkers.info("Saved encrypted report: \(fileName) (\(data.count) bytes)")
        return hash
    }

    /// Load and decrypt a previously saved file.
    static func load(hash: String) throws -> Data {
        let fileURL = reportsDir.appendingPathComponent(hash)
        let encrypted = try Data(contentsOf: fileURL)
        return try decrypt(data: encrypted)
    }

    /// Delete a saved file.
    static func delete(hash: String) {
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

    // MARK: - Keychain

    private static let keychainAccount = "com.drift.health.labReportKey"

    private static func saveKeyToKeychain(_ key: SymmetricKey) {
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

    private static func loadKeyFromKeychain() -> SymmetricKey? {
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

    enum StorageError: LocalizedError {
        case encryptionFailed
        var errorDescription: String? { "Failed to encrypt lab report" }
    }
}
