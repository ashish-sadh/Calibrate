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
        photosDirectory: URL? = nil,
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

        var files: [String: BackupManifest.FileEntry] = [
            BackupKeys.databaseFileName: dbEntry,
            BackupKeys.preferencesFileName: prefsEntry,
        ]
        // Progress photos (operator 2026-07-14): included under photos/ so a
        // Drift-backup restore brings the physique photos back with the data.
        // Older builds simply ignore the extra entries (format version
        // unchanged); older backups without photos restore as before.
        var photoEntries: [(name: String, url: URL)] = []
        if let photosDirectory,
           let names = try? FileManager.default.contentsOfDirectory(atPath: photosDirectory.path) {
            for name in names.sorted() where name.lowercased().hasSuffix(".jpg") {
                let url = photosDirectory.appendingPathComponent(name)
                let key = BackupKeys.photosPrefix + name
                files[key] = try fileEntry(for: url)
                photoEntries.append((key, url))
            }
        }

        let manifest = BackupManifest(
            appBuild: appMetadata.appBuild,
            appVersion: appMetadata.appVersion,
            timestamp: timestamp,
            schemaVersion: appMetadata.schemaVersion,
            files: files
        )
        let manifestURL = workDir.appendingPathComponent(BackupKeys.manifestFileName)
        try BackupManifest.encoder().encode(manifest).write(to: manifestURL)

        let totalBytes = files.values.reduce(Int64(0)) { $0 + $1.sizeBytes }
        progress?(.compressing(bytes: totalBytes))
        var zipEntries: [(name: String, url: URL)] = [
            (BackupKeys.manifestFileName, manifestURL),
            (BackupKeys.databaseFileName, dbSnapshotURL),
            (BackupKeys.preferencesFileName, prefsURL),
        ]
        zipEntries.append(contentsOf: photoEntries)
        try writeZip(entries: zipEntries, to: destination)
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

    private func writeZip(entries: [(name: String, url: URL)], to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard let archive = Archive(url: destination, accessMode: .create) else {
            throw BackupPackagerError.zipCreateFailed(destination.path)
        }
        for entry in entries {
            do {
                // JPEGs are already compressed — store, don't deflate.
                let method: CompressionMethod = entry.name.hasPrefix(BackupKeys.photosPrefix) ? .none : .deflate
                try archive.addEntry(
                    with: entry.name,
                    fileURL: entry.url,
                    compressionMethod: method
                )
            } catch {
                throw BackupPackagerError.zipAddEntryFailed("\(entry.name): \(error)")
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
