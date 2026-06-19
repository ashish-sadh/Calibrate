import Foundation
import GRDB
import CryptoKit
import ZIPFoundation

public enum BackupPackagerError: Error, Equatable {
    case dbSnapshotFailed(String)
    case zipCreateFailed(String)
    case zipAddEntryFailed(String)
}

public struct BackupPackager {
    public struct AppMetadata: Sendable {
        public let appBuild: String
        public let appVersion: String
        public let schemaVersion: Int

        public init(appBuild: String, appVersion: String, schemaVersion: Int) {
            self.appBuild = appBuild
            self.appVersion = appVersion
            self.schemaVersion = schemaVersion
        }
    }

    public init() {}

    /// Build a `.driftbackup` file at `destination` from `dbWriter` and the
    /// allowlisted keys in `userDefaults`. Returns the manifest written.
    @discardableResult
    public func package(
        dbWriter: any DatabaseWriter,
        userDefaults: UserDefaults,
        appMetadata: AppMetadata,
        timestamp: Date = Date(),
        destination: URL,
        scratchDir: URL? = nil,
        progress: BackupProgressHandler? = nil
    ) throws -> BackupManifest {
        let workDir = scratchDir ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        progress?(.snapshotting)
        let dbSnapshotURL = workDir.appendingPathComponent(BackupKeys.databaseFileName)
        try snapshotDatabase(dbWriter: dbWriter, to: dbSnapshotURL)

        progress?(.savingSettings)
        let prefsURL = workDir.appendingPathComponent(BackupKeys.preferencesFileName)
        try writePreferences(userDefaults: userDefaults, to: prefsURL)

        let dbEntry = try fileEntry(for: dbSnapshotURL)
        let prefsEntry = try fileEntry(for: prefsURL)

        let manifest = BackupManifest(
            appBuild: appMetadata.appBuild,
            appVersion: appMetadata.appVersion,
            timestamp: timestamp,
            schemaVersion: appMetadata.schemaVersion,
            files: [
                BackupKeys.databaseFileName: dbEntry,
                BackupKeys.preferencesFileName: prefsEntry,
            ]
        )
        let manifestURL = workDir.appendingPathComponent(BackupKeys.manifestFileName)
        try BackupManifest.encoder().encode(manifest).write(to: manifestURL)

        progress?(.compressing(bytes: dbEntry.sizeBytes + prefsEntry.sizeBytes))
        try writeZip(
            entries: [manifestURL, dbSnapshotURL, prefsURL],
            to: destination
        )
        return manifest
    }

    private func snapshotDatabase(dbWriter: any DatabaseWriter, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        do {
            try dbWriter.writeWithoutTransaction { db in
                try db.execute(sql: "VACUUM INTO ?", arguments: [url.path])
            }
        } catch {
            throw BackupPackagerError.dbSnapshotFailed(String(describing: error))
        }
    }

    private func writePreferences(userDefaults: UserDefaults, to url: URL) throws {
        var dict: [String: Any] = [:]
        for key in BackupKeys.userDefaultsAllowlist {
            guard let value = userDefaults.object(forKey: key),
                  let safe = jsonSafeValue(value) else { continue }
            dict[key] = safe
        }
        let data = try JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url)
    }

    private func jsonSafeValue(_ value: Any) -> Any? {
        if let v = value as? Bool { return v }
        if let v = value as? Int { return v }
        if let v = value as? Double { return v }
        if let v = value as? String { return v }
        if let v = value as? Data { return BackupKeys.dataB64Prefix + v.base64EncodedString() }
        // Strict cast — any non-String element drops the whole array rather
        // than partially serializing. Mirrors the Restorer's strict acceptance.
        if let v = value as? [String] { return v }
        return nil
    }

    private func fileEntry(for url: URL) throws -> BackupManifest.FileEntry {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return BackupManifest.FileEntry(sha256: hex, sizeBytes: Int64(data.count))
    }

    private func writeZip(entries: [URL], to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard let archive = Archive(url: destination, accessMode: .create) else {
            throw BackupPackagerError.zipCreateFailed(destination.path)
        }
        for entry in entries {
            do {
                try archive.addEntry(
                    with: entry.lastPathComponent,
                    fileURL: entry,
                    compressionMethod: .deflate
                )
            } catch {
                throw BackupPackagerError.zipAddEntryFailed("\(entry.lastPathComponent): \(error)")
            }
        }
    }
}

extension BackupPackager {
    /// File-naming convention: `drift-backup-YYYY-MM-DDTHHMMSS.driftbackup` (UTC)
    public static func filename(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        return "drift-backup-\(f.string(from: date)).\(BackupKeys.backupFileExtension)"
    }

    /// Read the manifest from a `.driftbackup` archive without extracting any
    /// other entries. Used by the iOS BackupService to populate the restore
    /// picker cheaply (~one zip-directory read per file, no DB extract).
    public static func readManifest(from url: URL) throws -> BackupManifest {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw BackupError.invalidFormat("not a zip archive: \(url.lastPathComponent)")
        }
        guard let entry = archive[BackupKeys.manifestFileName] else {
            throw BackupError.invalidFormat("missing \(BackupKeys.manifestFileName)")
        }
        var data = Data()
        do {
            _ = try archive.extract(entry) { data.append($0) }
        } catch {
            throw BackupError.invalidFormat("failed to read manifest: \(error)")
        }
        do {
            return try BackupManifest.decoder().decode(BackupManifest.self, from: data)
        } catch {
            throw BackupError.invalidFormat("manifest decode failed: \(error)")
        }
    }
}
