import Foundation
import GRDB
import CryptoKit
import ZIPFoundation

/// Atomic restore from a `.driftbackup` file produced by `BackupPackager`.
///
/// Sequence:
///   1. Open archive, read & decode manifest.
///   2. Validate `backupFormatVersion` and `schemaVersion` against this build.
///   3. Extract `drift.sqlite` + `preferences.json` into a scratch dir.
///   4. Verify SHA-256 of each file against the manifest.
///   5. Open extracted DB read-only and run `PRAGMA integrity_check`.
///   6. Run forward migrations on the extracted DB if its schema is older.
///   7. Atomically replace the destination DB file via `FileManager.replaceItem`.
///   8. Apply allowlisted preferences to `userDefaults`.
///
/// On any failure before step 7, the destination DB is untouched. After step 7,
/// preferences may not be applied (degraded but safe — data is restored).
public struct BackupRestorer {
    public init() {}

    /// Restore a `.driftbackup` file into the database at `databaseURL` and apply
    /// allowlisted preferences to `userDefaults`. Returns the restored manifest.
    @discardableResult
    public func restore(
        from backupURL: URL,
        toDatabasePath databaseURL: URL,
        userDefaults: UserDefaults,
        currentSchemaVersion: Int = Migrations.currentVersion,
        scratchDir: URL? = nil,
        photosDirectory: URL? = nil
    ) throws -> BackupManifest {
        let workDir = scratchDir ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("drift-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let manifest = try BackupPackager.readManifest(from: backupURL)
        guard let archive = Archive(url: backupURL, accessMode: .read) else {
            throw BackupError.invalidFormat("not a zip archive: \(backupURL.lastPathComponent)")
        }

        // Format / schema version gates — fail fast before touching any files.
        if manifest.backupFormatVersion > BackupManifest.currentFormatVersion {
            throw BackupError.unsupportedFormatVersion(
                backupVersion: manifest.backupFormatVersion,
                current: BackupManifest.currentFormatVersion
            )
        }
        if manifest.schemaVersion > currentSchemaVersion {
            throw BackupError.unsupportedSchemaVersion(
                backupVersion: manifest.schemaVersion,
                current: currentSchemaVersion
            )
        }

        let extractedDB = try extractAndVerify(
            archive: archive,
            entryName: BackupKeys.databaseFileName,
            manifest: manifest,
            into: workDir
        )
        let extractedPrefs = try extractAndVerify(
            archive: archive,
            entryName: BackupKeys.preferencesFileName,
            manifest: manifest,
            into: workDir
        )

        try runIntegrityCheck(on: extractedDB)

        if manifest.schemaVersion < currentSchemaVersion {
            try migrateForward(at: extractedDB)
        }

        try atomicReplace(source: extractedDB, destination: databaseURL)

        // #998: the restored DB carries the backup's (possibly older) curated food
        // catalog. Clear the seed fast-path so seedFoodsFromJSON() re-syncs foods from
        // the current bundle onto the restored DB on next launch, instead of skipping.
        AppDatabase.invalidateFoodSeedCache()

        try applyPreferences(from: extractedPrefs, to: userDefaults)

        // Progress photos (2026-07-14): best-effort AFTER the DB swap — a
        // corrupt photo must not abort a successful data restore. Each entry
        // is checksum-verified; failures are skipped (the gallery filters
        // rows whose file is missing).
        if let photosDirectory {
            restorePhotos(archive: archive, manifest: manifest, into: photosDirectory)
        }

        return manifest
    }

    /// Extract every `photos/` entry into `directory`, verifying checksums.
    /// Per-file failures are logged and skipped, never thrown.
    private func restorePhotos(archive: Archive, manifest: BackupManifest, into directory: URL) {
        let photoKeys = manifest.files.keys.filter { $0.hasPrefix(BackupKeys.photosPrefix) }
        guard !photoKeys.isEmpty else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for key in photoKeys.sorted() {
            guard let entry = archive[key], let expected = manifest.files[key] else { continue }
            var collected = Data()
            guard (try? archive.extract(entry) { collected.append($0) }) != nil else {
                Log.app.error("Backup restore: photo extract failed for \(key)")
                continue
            }
            let hash = SHA256.hash(data: collected).map { String(format: "%02x", $0) }.joined()
            guard hash == expected.sha256, Int64(collected.count) == expected.sizeBytes else {
                Log.app.error("Backup restore: photo checksum mismatch for \(key)")
                continue
            }
            let filename = String(key.dropFirst(BackupKeys.photosPrefix.count))
            try? collected.write(to: directory.appendingPathComponent(filename), options: .atomic)
        }
    }

    // MARK: - Steps

    private func extractAndVerify(
        archive: Archive,
        entryName: String,
        manifest: BackupManifest,
        into workDir: URL
    ) throws -> URL {
        guard let entry = archive[entryName] else {
            throw BackupError.invalidFormat("missing entry: \(entryName)")
        }
        guard let expected = manifest.files[entryName] else {
            throw BackupError.invalidFormat("manifest missing entry record: \(entryName)")
        }
        let dest = workDir.appendingPathComponent(entryName)
        var collected = Data()
        do {
            _ = try archive.extract(entry) { collected.append($0) }
        } catch {
            throw BackupError.corrupted("extraction failed for \(entryName): \(error)")
        }
        let actualHash = SHA256.hash(data: collected).map { String(format: "%02x", $0) }.joined()
        if actualHash != expected.sha256 {
            throw BackupError.corrupted("checksum mismatch for \(entryName)")
        }
        if Int64(collected.count) != expected.sizeBytes {
            throw BackupError.corrupted("size mismatch for \(entryName)")
        }
        try collected.write(to: dest)
        return dest
    }

    private func runIntegrityCheck(on dbURL: URL) throws {
        var config = Configuration()
        config.readonly = true
        do {
            let queue = try DatabaseQueue(path: dbURL.path, configuration: config)
            let result = try queue.read { db in
                try String.fetchOne(db, sql: "PRAGMA integrity_check")
            }
            guard result == "ok" else {
                throw BackupError.corrupted("PRAGMA integrity_check: \(result ?? "<nil>")")
            }
        } catch let err as BackupError {
            throw err
        } catch {
            throw BackupError.corrupted("PRAGMA integrity_check failed: \(error)")
        }
    }

    private func migrateForward(at dbURL: URL) throws {
        let queue = try DatabaseQueue(path: dbURL.path)
        try AppDatabase.runMigrations(on: queue)
        // HealthKit query anchors are positions in the SOURCE device's HK
        // change ledger — restored onto a different device (the common
        // new-phone flow) they are foreign garbage: anchored syncs start
        // "after" data that was never delivered here, so Apple Health weight
        // import silently returns 0 forever (field report 2026-07-09).
        // Restored installs must re-import from scratch.
        try queue.write { db in
            try db.execute(sql: "DELETE FROM hk_sync_anchor")
        }
    }

    private func atomicReplace(source: URL, destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fm.fileExists(atPath: destination.path) {
            // replaceItem requires the destination to exist; otherwise a plain move.
            _ = try fm.replaceItemAt(destination, withItemAt: source)
        } else {
            try fm.moveItem(at: source, to: destination)
        }
        // GRDB WAL/SHM sidecars from older sessions are stale after a swap. Removing
        // them forces SQLite to rebuild from the restored main file.
        try? fm.removeItem(at: URL(fileURLWithPath: destination.path + "-wal"))
        try? fm.removeItem(at: URL(fileURLWithPath: destination.path + "-shm"))
    }

    private func applyPreferences(from url: URL, to defaults: UserDefaults) throws {
        let data = try Data(contentsOf: url)
        let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        // #997: REPLACE (not merge) the allowlisted prefs. Iterating the allowlist and
        // clearing keys ABSENT from the backup means a stale current-device value (e.g.
        // a weight goal the backup didn't have) doesn't survive the restore.
        // primitiveValue() returns nil for NSNull, so a null/incompatible value also
        // clears the key rather than raising the uncatchable exception `defaults.set`
        // would throw (mirrors BackupPackager.jsonSafeValue).
        for key in BackupKeys.userDefaultsAllowlist {
            if let value = dict[key], let safe = primitiveValue(value) {
                defaults.set(safe, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func primitiveValue(_ value: Any) -> Any? {
        if value is NSNull { return nil }
        if let v = value as? Bool { return v }
        if let v = value as? Int { return v }
        if let v = value as? Double { return v }
        if let v = value as? String {
            // Sentinel-prefixed strings carry base64-encoded `Data` (Codable
            // blobs like WeightGoal). Bad base64 is dropped silently — the
            // alternative (crashing on a hand-crafted backup) was the #687
            // failure mode we already paid the price for once.
            if v.hasPrefix(BackupKeys.dataB64Prefix) {
                let payload = String(v.dropFirst(BackupKeys.dataB64Prefix.count))
                return Data(base64Encoded: payload)
            }
            return v
        }
        if let v = value as? [String] { return v }
        return nil
    }
}
