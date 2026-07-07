import XCTest
import GRDB
import ZIPFoundation
import CryptoKit
@testable import DriftCore

/// Thread-safe sink for the @Sendable progress callback (so the test can
/// capture phases without a data-race warning).
private final class PhaseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var store: [BackupPhase] = []
    func append(_ p: BackupPhase) { lock.lock(); store.append(p); lock.unlock() }
    var phases: [BackupPhase] { lock.lock(); defer { lock.unlock() }; return store }
}

final class BackupPackagerTests: XCTestCase {
    private var workDir: URL!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupPackagerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        super.tearDown()
    }

    func testManifestEncodeDecodeRoundtrip() throws {
        let original = BackupManifest(
            appBuild: "1042",
            appVersion: "2.1.0",
            timestamp: Date(timeIntervalSince1970: 1714615212),
            schemaVersion: 14,
            files: [
                "drift.sqlite": .init(sha256: "a3f2c1", sizeBytes: 2_097_152),
                "preferences.json": .init(sha256: "b7e9d4", sizeBytes: 512),
            ]
        )
        let data = try BackupManifest.encoder().encode(original)
        let decoded = try BackupManifest.decoder().decode(BackupManifest.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testFilenamePattern() {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 5
        components.day = 2
        components.hour = 3
        components.minute = 0
        components.second = 12
        let name = BackupPackager.filename(for: components.date!)
        XCTAssertEqual(name, "drift-backup-2026-05-02T030012.driftbackup")
    }

    func testPackageRoundtrip() throws {
        let dbURL = workDir.appendingPathComponent("source.sqlite")
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE seed_row (id INTEGER PRIMARY KEY, value TEXT)")
            for i in 0..<100 {
                try db.execute(sql: "INSERT INTO seed_row(value) VALUES(?)", arguments: ["row-\(i)"])
            }
        }

        let suite = "BackupPackagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // Use REAL production keys (#700) — `drift.weightGoal` etc. are
        // fictional. Real keys come from Preferences.swift / WeightGoal.swift.
        defaults.set("kg", forKey: "weight_unit")
        defaults.set(2500.0, forKey: "drift_water_goal_ml")
        defaults.set(true, forKey: "drift_health_nudges")
        // A non-allowlisted key — must NOT be in the snapshot
        defaults.set("leaked", forKey: "drift_not_allowlisted")
        // A system-namespaced key — must NOT be in the snapshot
        defaults.set("apple", forKey: "AppleLanguages")

        let destination = workDir.appendingPathComponent("test.driftbackup")
        let packager = BackupPackager()
        let manifest = try packager.package(
            dbWriter: dbQueue,
            userDefaults: defaults,
            appMetadata: .init(appBuild: "1042", appVersion: "2.1.0", schemaVersion: 14),
            destination: destination
        )

        XCTAssertEqual(manifest.backupFormatVersion, 1)
        XCTAssertEqual(manifest.appBuild, "1042")
        XCTAssertEqual(manifest.schemaVersion, 14)
        XCTAssertEqual(Set(manifest.files.keys), ["drift.sqlite", "preferences.json"])
        XCTAssertGreaterThan(manifest.files["drift.sqlite"]?.sizeBytes ?? 0, 0)

        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
        let archive = try XCTUnwrap(Archive(url: destination, accessMode: .read))
        let names = Set(archive.map { $0.path })
        XCTAssertEqual(names, ["manifest.json", "drift.sqlite", "preferences.json"])

        // Extract and verify checksums match the manifest
        for (name, expected) in manifest.files {
            let entry = try XCTUnwrap(archive[name])
            var collected = Data()
            _ = try archive.extract(entry) { collected.append($0) }
            let digest = collected.sha256Hex()
            XCTAssertEqual(digest, expected.sha256, "checksum mismatch for \(name)")
            XCTAssertEqual(Int64(collected.count), expected.sizeBytes, "size mismatch for \(name)")
        }

        // Preferences allowlist behavior
        let prefsEntry = try XCTUnwrap(archive["preferences.json"])
        var prefsData = Data()
        _ = try archive.extract(prefsEntry) { prefsData.append($0) }
        let prefs = try JSONSerialization.jsonObject(with: prefsData) as? [String: Any] ?? [:]
        XCTAssertEqual(prefs["weight_unit"] as? String, "kg")
        XCTAssertEqual(prefs["drift_water_goal_ml"] as? Double, 2500.0)
        XCTAssertEqual(prefs["drift_health_nudges"] as? Bool, true)
        XCTAssertNil(prefs["drift_not_allowlisted"])
        XCTAssertNil(prefs["AppleLanguages"])

        // Restored DB has all 100 rows
        let restoredDB = workDir.appendingPathComponent("restored.sqlite")
        let dbEntry = try XCTUnwrap(archive["drift.sqlite"])
        var dbData = Data()
        _ = try archive.extract(dbEntry) { dbData.append($0) }
        try dbData.write(to: restoredDB)
        let restoredQueue = try DatabaseQueue(path: restoredDB.path)
        let count = try restoredQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM seed_row")
        }
        XCTAssertEqual(count, 100)

        UserDefaults().removePersistentDomain(forName: suite)
    }

    func testPackageOmitsAbsentKeys() throws {
        let dbURL = workDir.appendingPathComponent("source.sqlite")
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE x (id INTEGER PRIMARY KEY)")
        }

        let suite = "BackupPackagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        // Set only one allowlisted key (real key per #700)
        defaults.set(true, forKey: "drift_health_nudges")

        let destination = workDir.appendingPathComponent("absent.driftbackup")
        try BackupPackager().package(
            dbWriter: dbQueue,
            userDefaults: defaults,
            appMetadata: .init(appBuild: "1", appVersion: "0.1", schemaVersion: 1),
            destination: destination
        )

        let archive = try XCTUnwrap(Archive(url: destination, accessMode: .read))
        let prefsEntry = try XCTUnwrap(archive["preferences.json"])
        var data = Data()
        _ = try archive.extract(prefsEntry) { data.append($0) }
        let prefs = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        XCTAssertEqual(prefs.count, 1)
        XCTAssertEqual(prefs["drift_health_nudges"] as? Bool, true)
        // Confirm absent allowlisted keys are NOT serialized as null
        XCTAssertNil(prefs["drift_water_goal_ml"])
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("null"))

        UserDefaults().removePersistentDomain(forName: suite)
    }

    /// The progress callback fires the packaging phases in order — proves the
    /// granular status the UI shows ("Copying… → Saving… → Compressing X") is
    /// driven by real packaging steps, not a fake timer. #backup-progress
    func testPackageEmitsProgressPhasesInOrder() throws {
        let dbURL = workDir.appendingPathComponent("prog.sqlite")
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)")
            try db.execute(sql: "INSERT INTO t(v) VALUES('x')")
        }
        let suite = "BackupProgressTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(true, forKey: "drift_health_nudges")
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let collector = PhaseCollector()
        _ = try BackupPackager().package(
            dbWriter: dbQueue,
            userDefaults: defaults,
            appMetadata: .init(appBuild: "1", appVersion: "1.0", schemaVersion: 1),
            destination: workDir.appendingPathComponent("prog.driftbackup"),
            progress: { collector.append($0) }
        )

        let phases = collector.phases
        XCTAssertEqual(phases.count, 3)
        XCTAssertEqual(phases.first, .snapshotting)
        XCTAssertEqual(phases.dropFirst().first, .savingSettings)
        if case .compressing(let bytes) = phases.last {
            XCTAssertGreaterThan(bytes, 0)
        } else {
            XCTFail("expected compressing phase last, got \(String(describing: phases.last))")
        }
    }

    func testBackupPhaseMessages() {
        XCTAssertEqual(BackupPhase.snapshotting.message, "Copying your data…")
        XCTAssertEqual(BackupPhase.savingSettings.message, "Saving your settings…")
        XCTAssertEqual(BackupPhase.movingToCloud.message, "Moving to iCloud…")
        XCTAssertEqual(BackupPhase.uploading.message, "Uploading to iCloud…")
        let compressing = BackupPhase.compressing(bytes: 3_500_000).message
        XCTAssertTrue(compressing.hasPrefix("Compressing backup ("))
        XCTAssertTrue(compressing.contains("MB"))
    }

    /// Regression for #700 / #701 — allowlist must contain only real keys
    /// that the JSON pipeline can serialize (primitive / `[String]` / `Data`
    /// via `dataB64Prefix`). If you add a key, also add a writer in
    /// production code AND verify `Packager.jsonSafeValue` accepts the type.
    func testAllowlistContainsOnlyRealAndSerializableKeys() {
        let expected: Set<String> = [
            "weight_unit",
            "drift_cycle_fertile_window",
            "drift_ai_enabled",
            "drift_conversation_history_enabled",
            "drift_chat_telemetry_enabled",
            "drift_use_remote_model_on_wifi",
            "drift_preferred_ai_backend",
            // NOTE: `drift_photo_log_enabled` is intentionally absent — it is not
            // a real production key (no reader/writer; Photo Log enablement is
            // derived from a Keychain key, which is never backed up). Per the
            // #700 "real keys only" rule it must stay out of the allowlist.
            "drift_health_nudges",
            "drift_meal_reminders",
            "drift_medication_reminders",
            "drift_glp1_reminders",
            "drift_online_food_search",
            "drift_usda_api_key",
            "drift_water_goal_ml",
            "drift_weight_goal",
            "drift_tdee_config",
            "drift_algorithm_config",
            "drift_custom_exercises",
            "drift_exercise_favorites",
        ]
        XCTAssertEqual(Set(BackupKeys.userDefaultsAllowlist), expected)
        // No dotted-camelCase keys (the pre-#700 fictional set used these).
        for key in BackupKeys.userDefaultsAllowlist {
            XCTAssertFalse(
                key.contains(".") && key.starts(with: "drift."),
                "Allowlist key \(key) is dotted-camelCase — production code uses snake_case."
            )
        }
    }

    /// #701 — Codable `Data` blobs (WeightGoal, TDEEConfig, etc.) and
    /// `[String]` arrays are JSON-encoded into `preferences.json`. This test
    /// asserts the Packager-side encoding shape: `Data` becomes a single
    /// String prefixed with `dataB64Prefix`; `[String]` is a JSON array.
    func testPackageEncodesDataAndStringArrayShapes() throws {
        let dbURL = workDir.appendingPathComponent("source.sqlite")
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE x (id INTEGER PRIMARY KEY)")
        }

        let goal = WeightGoal(
            targetWeightKg: 65,
            monthsToAchieve: 6,
            startDate: "2026-01-01",
            startWeightKg: 75,
            proteinTargetG: 150,
            dietPreference: .highProtein,
            calorieTargetOverride: 2000,
            proteinGoal: 150
        )
        let goalData = try JSONEncoder().encode(goal)
        let favorites = ["bench_press", "deadlift", "back_squat"]

        let suite = "BackupPackagerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set(goalData, forKey: "drift_weight_goal")
        defaults.set(favorites, forKey: "drift_exercise_favorites")

        let destination = workDir.appendingPathComponent("shapes.driftbackup")
        try BackupPackager().package(
            dbWriter: dbQueue,
            userDefaults: defaults,
            appMetadata: .init(appBuild: "1", appVersion: "0.1", schemaVersion: 1),
            destination: destination
        )

        let archive = try XCTUnwrap(Archive(url: destination, accessMode: .read))
        let prefsEntry = try XCTUnwrap(archive["preferences.json"])
        var data = Data()
        _ = try archive.extract(prefsEntry) { data.append($0) }
        let prefs = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        let encodedGoal = try XCTUnwrap(prefs["drift_weight_goal"] as? String)
        XCTAssertTrue(encodedGoal.hasPrefix(BackupKeys.dataB64Prefix))
        let payload = String(encodedGoal.dropFirst(BackupKeys.dataB64Prefix.count))
        XCTAssertEqual(Data(base64Encoded: payload), goalData)

        XCTAssertEqual(prefs["drift_exercise_favorites"] as? [String], favorites)
    }
}

private extension Data {
    func sha256Hex() -> String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
