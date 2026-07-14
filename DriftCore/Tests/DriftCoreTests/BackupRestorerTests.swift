import XCTest
import GRDB
import ZIPFoundation
import CryptoKit
@testable import DriftCore

final class BackupRestorerTests: XCTestCase {
    private var workDir: URL!
    private var defaultsSuite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupRestorerTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defaultsSuite = "BackupRestorerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)!
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: workDir)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    // MARK: - Roundtrip

    func testRoundtripRestoresAllRowsAndAllowlistedDefaults() throws {
        // Real production keys per #700 — `drift.weightGoal` etc. were fictional.
        let backupURL = try makeBackup(
            seedRows: 100,
            schemaVersion: Migrations.currentVersion,
            withDefaults: [
                "weight_unit": "kg",
                "drift_water_goal_ml": 2500.0,
                "drift_health_nudges": true,
                "drift_not_allowlisted": "leaked", // must NOT round-trip
            ]
        )

        let dest = workDir.appendingPathComponent("restored-target.sqlite")
        // Pre-create a stub destination so atomic replace exercises replaceItem.
        try Data("stale".utf8).write(to: dest)

        let manifest = try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults,
            currentSchemaVersion: Migrations.currentVersion,
            scratchDir: workDir.appendingPathComponent("scratch", isDirectory: true)
        )

        XCTAssertEqual(manifest.schemaVersion, Migrations.currentVersion)

        let restored = try DatabaseQueue(path: dest.path)
        let count = try restored.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM seed_row")
        }
        XCTAssertEqual(count, 100)

        XCTAssertEqual(defaults.string(forKey: "weight_unit"), "kg")
        XCTAssertEqual(defaults.double(forKey: "drift_water_goal_ml"), 2500.0)
        XCTAssertTrue(defaults.bool(forKey: "drift_health_nudges"))
        XCTAssertNil(defaults.object(forKey: "drift_not_allowlisted"))
    }

    // #997: restore REPLACES allowlisted prefs — a key absent from the backup is cleared,
    // not left at the stale current-device value.
    func testRestoreClearsAllowlistedKeyAbsentFromBackup() throws {
        defaults.set("lbs", forKey: "weight_unit")  // stale current-device value
        let backupURL = try makeBackup(
            seedRows: 1, schemaVersion: Migrations.currentVersion,
            withDefaults: ["drift_health_nudges": true]  // NOTE: no weight_unit
        )
        let dest = workDir.appendingPathComponent("restored-997.sqlite")
        _ = try BackupRestorer().restore(
            from: backupURL, toDatabasePath: dest, userDefaults: defaults,
            currentSchemaVersion: Migrations.currentVersion,
            scratchDir: workDir.appendingPathComponent("scratch997", isDirectory: true)
        )
        XCTAssertNil(defaults.object(forKey: "weight_unit"),
                     "allowlisted key absent from the backup must be cleared, not left stale")
        XCTAssertTrue(defaults.bool(forKey: "drift_health_nudges"))
    }

    // MARK: - Corruption

    func testCorruptManifestChecksumReturnsCorrupted() throws {
        let backupURL = try makeBackup(seedRows: 5, schemaVersion: Migrations.currentVersion)
        try corruptDatabaseChecksum(in: backupURL)

        let dest = workDir.appendingPathComponent("restored.sqlite")
        let originalBytes = Data("original-db".utf8)
        try originalBytes.write(to: dest)

        XCTAssertThrowsError(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        )) { error in
            guard case .corrupted = error as? BackupError else {
                return XCTFail("expected .corrupted, got \(error)")
            }
        }

        // Original DB untouched.
        XCTAssertEqual(try Data(contentsOf: dest), originalBytes)
    }

    func testMissingManifestReturnsInvalidFormat() throws {
        let backupURL = workDir.appendingPathComponent("no-manifest.driftbackup")
        guard let archive = Archive(url: backupURL, accessMode: .create) else {
            return XCTFail("could not create archive")
        }
        let dummy = workDir.appendingPathComponent("dummy.sqlite")
        try Data("x".utf8).write(to: dummy)
        try archive.addEntry(with: "drift.sqlite", fileURL: dummy, compressionMethod: .deflate)

        let dest = workDir.appendingPathComponent("dest.sqlite")
        let originalBytes = Data("original".utf8)
        try originalBytes.write(to: dest)

        XCTAssertThrowsError(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        )) { error in
            guard case .invalidFormat = error as? BackupError else {
                return XCTFail("expected .invalidFormat, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: dest), originalBytes)
    }

    // MARK: - Schema version

    func testSchemaVersionTooNewReturnsUnsupportedAndLeavesDestAlone() throws {
        let backupURL = try makeBackup(
            seedRows: 1,
            schemaVersion: Migrations.currentVersion + 5
        )

        let dest = workDir.appendingPathComponent("dest.sqlite")
        let originalBytes = Data("untouched".utf8)
        try originalBytes.write(to: dest)

        XCTAssertThrowsError(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        )) { error in
            guard case .unsupportedSchemaVersion = error as? BackupError else {
                return XCTFail("expected .unsupportedSchemaVersion, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: dest), originalBytes)
    }

    func testOlderSchemaVersionRunsForwardMigrations() throws {
        // The packager stamps whatever schemaVersion the caller passes. We package
        // a DB at version 1, then restore claiming current = whatever Migrations
        // says — restorer should run forward migrations on the extracted DB before
        // swapping.
        let backupURL = try makeBackup(
            seedRows: 3,
            schemaVersion: 1,
            includeRealMigrations: true
        )

        let dest = workDir.appendingPathComponent("dest.sqlite")
        XCTAssertNoThrow(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        ))

        // After restore the DB must have all forward migrations applied — tables
        // from later migrations should exist.
        let queue = try DatabaseQueue(path: dest.path)
        let hasMedicationTable = try queue.read { db in
            try db.tableExists("daily_medication")
        }
        XCTAssertTrue(hasMedicationTable, "v37 migration should have run")

        let appliedCount = try queue.read { db -> Int in
            // grdb_migrations is the internal migration ledger.
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations") ?? 0
            return count
        }
        XCTAssertEqual(appliedCount, Migrations.currentVersion)
    }

    /// 2026-07-09 field bug: HealthKit query anchors are positions in the
    /// SOURCE device's HK change ledger. Restored onto a new phone they are
    /// foreign garbage — anchored weight syncs return 0 forever ("granted
    /// permissions, has Health data, sync does nothing"). Restore must clear
    /// the anchor table so the restored install re-imports from scratch.
    func testRestoreClearsHealthKitAnchors() throws {
        let backupURL = try makeBackup(
            seedRows: 1,
            schemaVersion: 1,
            includeRealMigrations: true,
            extraSQL: [
                // Pre-create the anchor table + stamp its migration as applied
                // (same pattern as weight_entry above) so the forward-migration
                // replay doesn't recreate an existing table.
                """
                CREATE TABLE hk_sync_anchor (
                    data_type TEXT NOT NULL PRIMARY KEY,
                    last_anchor BLOB
                )
                """,
                "INSERT INTO grdb_migrations VALUES('v5_hk_sync')",
                "INSERT INTO hk_sync_anchor VALUES('bodyMass', X'DEADBEEF')",
            ]
        )

        let dest = workDir.appendingPathComponent("dest-anchors.sqlite")
        XCTAssertNoThrow(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        ))

        let queue = try DatabaseQueue(path: dest.path)
        let anchorCount = try queue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM hk_sync_anchor") ?? -1
        }
        XCTAssertEqual(anchorCount, 0, "restore must clear foreign HealthKit anchors")
    }

    // MARK: - Crash defense: hand-crafted preferences

    /// Regression test for the crash audit (#687). JSON `null` deserializes
    /// to `NSNull`, which is NOT property-list compatible; calling
    /// `UserDefaults.set(NSNull(), forKey:)` raises an uncatchable Obj-C
    /// exception. The Restorer must filter such values rather than blindly
    /// forwarding them.
    func testApplyPreferencesIgnoresNullAndComplexValuesAndDoesNotCrash() throws {
        // Real production keys per #700; `drift_health_nudges_dict` etc. are
        // intentional non-allowlisted variants used to verify the filter.
        let backupURL = try makeBackupWithRawPreferencesJSON(
            seedRows: 1,
            schemaVersion: Migrations.currentVersion,
            rawPrefsJSON: """
            {
              "drift_water_goal_ml": null,
              "drift_health_nudges": true,
              "weight_unit": "kg",
              "drift_usda_api_key": "abc-123",
              "drift_chat_telemetry_enabled_dict": {"nested": "object"},
              "drift_meal_reminders_array": ["array", "value"],
              "drift_not_allowlisted": "leaked"
            }
            """
        )

        let dest = workDir.appendingPathComponent("dest.sqlite")
        // Restore must complete without throwing or raising an Obj-C exception.
        XCTAssertNoThrow(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        ))

        // Null + complex values dropped silently — Restorer must not crash on them.
        XCTAssertNil(defaults.object(forKey: "drift_water_goal_ml"))
        XCTAssertNil(defaults.object(forKey: "drift_chat_telemetry_enabled_dict"))
        XCTAssertNil(defaults.object(forKey: "drift_meal_reminders_array"))
        // Allowlist still enforced.
        XCTAssertNil(defaults.object(forKey: "drift_not_allowlisted"))
    }

    // MARK: - #701 Codable Data + array round-trips

    /// Round-trip the user's most-valuable state — the WeightGoal — through
    /// package + restore. `WeightGoal` is `Codable` but not `Equatable`, so we
    /// compare the raw `Data` (set via `defaults.set(_:Data, forKey:)`) which
    /// is what the restore must reproduce byte-for-byte.
    func testRoundtripRestoresWeightGoalData() throws {
        let goal = WeightGoal(
            targetWeightKg: 62,
            monthsToAchieve: 5,
            startDate: "2026-02-01",
            startWeightKg: 78,
            proteinTargetG: 140,
            dietPreference: .balanced,
            calorieTargetOverride: 1900,
            proteinGoal: 140
        )
        let goalData = try JSONEncoder().encode(goal)

        let backupURL = try makeBackup(
            seedRows: 1,
            schemaVersion: Migrations.currentVersion,
            withDefaults: ["drift_weight_goal": goalData]
        )

        let dest = workDir.appendingPathComponent("restored.sqlite")
        try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        )

        let restoredData = try XCTUnwrap(defaults.data(forKey: "drift_weight_goal"))
        XCTAssertEqual(restoredData, goalData, "WeightGoal Data must round-trip byte-identical")
        let restoredGoal = try JSONDecoder().decode(WeightGoal.self, from: restoredData)
        XCTAssertEqual(restoredGoal.targetWeightKg, 62)
        XCTAssertEqual(restoredGoal.monthsToAchieve, 5)
        XCTAssertEqual(restoredGoal.startDate, "2026-02-01")
        XCTAssertEqual(restoredGoal.startWeightKg, 78)
        XCTAssertEqual(restoredGoal.dietPreference, .balanced)
        XCTAssertEqual(restoredGoal.calorieTargetOverride, 1900)
    }

    /// `[String]` arrays are JSON-native — the round-trip is straightforward,
    /// but worth covering because `defaults.set(_:[String], forKey:)` is the
    /// production write path for `drift_exercise_favorites`.
    func testRoundtripRestoresStringArrayFavorites() throws {
        let favorites = ["bench_press", "deadlift", "back_squat", "overhead_press"]
        let backupURL = try makeBackup(
            seedRows: 1,
            schemaVersion: Migrations.currentVersion,
            withDefaults: ["drift_exercise_favorites": favorites]
        )

        let dest = workDir.appendingPathComponent("restored.sqlite")
        try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        )

        XCTAssertEqual(
            defaults.stringArray(forKey: "drift_exercise_favorites"),
            favorites
        )
    }

    /// Hand-crafted backup with a malformed base64 payload behind the
    /// `dataB64Prefix` sentinel must drop the entry silently — same defense
    /// posture as #687 NSNull / nested-dict / nested-array.
    func testApplyPreferencesDropsMalformedBase64WithoutCrashing() throws {
        let backupURL = try makeBackupWithRawPreferencesJSON(
            seedRows: 1,
            schemaVersion: Migrations.currentVersion,
            rawPrefsJSON: """
            {
              "drift_weight_goal": "\(BackupKeys.dataB64Prefix)not-base64-!!!",
              "weight_unit": "lb"
            }
            """
        )

        let dest = workDir.appendingPathComponent("dest.sqlite")
        XCTAssertNoThrow(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        ))

        XCTAssertNil(defaults.object(forKey: "drift_weight_goal"))
        XCTAssertEqual(defaults.string(forKey: "weight_unit"), "lb")
    }

    // MARK: - Atomic swap failure

    func testAtomicReplaceFailureLeavesOriginalDBIntact() throws {
        let backupURL = try makeBackup(seedRows: 2, schemaVersion: Migrations.currentVersion)

        // Force replaceItem to fail by making the destination's parent directory
        // read-only. POSIX semantics: removing/replacing a file requires write
        // permission on the parent, so replaceItemAt throws and our atomic swap
        // never overwrites the original.
        let parent = workDir.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let dest = parent.appendingPathComponent("dest.sqlite")
        let originalBytes = Data("untouched-original".utf8)
        try originalBytes.write(to: dest)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: parent.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: parent.path
            )
        }

        XCTAssertThrowsError(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults
        ))

        XCTAssertEqual(try Data(contentsOf: dest), originalBytes,
                       "original DB must be untouched after atomic swap failure")
    }

    // MARK: - Production-schema round-trip (issue #708 dogfood gate)

    /// Round-trip a fully-migrated production schema with at least one row in
    /// each major user-data domain. Catches accidental table drops in
    /// `VACUUM INTO`, missed forward migrations on restore, and silent loss
    /// of any single domain's data — the engine-level half of #708's
    /// "wipe-and-restore round-trips all major data domains losslessly"
    /// acceptance criterion. (Manual device dogfood still gated on #708's
    /// other criteria.)
    func testRoundtripPreservesProductionSchemaAndAllDomainRows() throws {
        // Arrange — file-backed source, run all production migrations.
        let sourceURL = workDir.appendingPathComponent("prod-source.sqlite")
        let sourceQueue = try DatabaseQueue(path: sourceURL.path)
        try AppDatabase.runMigrations(on: sourceQueue)

        // Snapshot the user-data table list (excluding sqlite + grdb internals).
        let originalTables: [String] = try sourceQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table'
                  AND name NOT LIKE 'sqlite_%'
                  AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """)
        }
        XCTAssertGreaterThan(originalTables.count, 5,
                             "real migrator must produce multiple production tables")

        // Insert one realistic row per major user-data domain. Rows are wrapped
        // in `tableExists` checks so the test stays robust if a future migration
        // renames or drops a table — the assertion is "every row we inserted
        // round-trips", not "exactly these tables exist".
        var insertedTables: [String] = []
        try sourceQueue.write { db in
            // Weight domain.
            if try db.tableExists("weight_entry") {
                try db.execute(sql: """
                    INSERT INTO weight_entry (date, weight_kg, source)
                    VALUES ('2026-05-10', 75.0, 'manual')
                    """)
                insertedTables.append("weight_entry")
            }
            // Food domain — meal_log + food_entry (food_entry FKs into meal_log).
            if try db.tableExists("meal_log"), try db.tableExists("food_entry") {
                try db.execute(sql: """
                    INSERT INTO meal_log (date, meal_type) VALUES ('2026-05-10', 'breakfast')
                    """)
                let mealLogId = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO food_entry
                        (meal_log_id, food_name, serving_size_g, servings, calories,
                         protein_g, carbs_g, fat_g, fiber_g)
                    VALUES (?, 'idli', 30.0, 2.0, 80.0, 2.0, 16.0, 0.5, 1.0)
                    """, arguments: [mealLogId])
                insertedTables.append("meal_log")
                insertedTables.append("food_entry")
            }
            // Supplement domain — supplement + supplement_log (FK).
            if try db.tableExists("supplement"), try db.tableExists("supplement_log") {
                try db.execute(sql: """
                    INSERT INTO supplement (name, dosage, unit) VALUES ('Vitamin D', '2000', 'IU')
                    """)
                let supplementId = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO supplement_log (supplement_id, date, taken)
                    VALUES (?, '2026-05-10', 1)
                    """, arguments: [supplementId])
                insertedTables.append("supplement")
                insertedTables.append("supplement_log")
            }
            // Workout domain — workout + workout_set (FK).
            if try db.tableExists("workout"), try db.tableExists("workout_set") {
                try db.execute(sql: """
                    INSERT INTO workout (name, date) VALUES ('Push Day', '2026-05-10')
                    """)
                let workoutId = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO workout_set
                        (workout_id, exercise_name, set_order, weight_lbs, reps)
                    VALUES (?, 'Bench Press', 1, 135.0, 8)
                    """, arguments: [workoutId])
                insertedTables.append("workout")
                insertedTables.append("workout_set")
            }
            // Biomarker domain — lab_report + biomarker_result (FK).
            if try db.tableExists("lab_report"), try db.tableExists("biomarker_result") {
                try db.execute(sql: """
                    INSERT INTO lab_report (report_date, file_name)
                    VALUES ('2026-05-01', 'labs.pdf')
                    """)
                let reportId = db.lastInsertedRowID
                try db.execute(sql: """
                    INSERT INTO biomarker_result
                        (report_id, biomarker_id, value, unit,
                         normalized_value, normalized_unit)
                    VALUES (?, 'ferritin', 45.0, 'ng/mL', 45.0, 'ng/mL')
                    """, arguments: [reportId])
                insertedTables.append("lab_report")
                insertedTables.append("biomarker_result")
            }
        }
        XCTAssertGreaterThanOrEqual(insertedTables.count, 5,
                                     "at least 5 domain rows must seed for meaningful coverage")

        // Act — package + restore.
        let backupURL = workDir.appendingPathComponent("prod.driftbackup")
        try BackupPackager().package(
            dbWriter: sourceQueue,
            userDefaults: defaults,
            appMetadata: .init(
                appBuild: "238",
                appVersion: "2.1.0",
                schemaVersion: Migrations.currentVersion
            ),
            destination: backupURL
        )
        let restoredURL = workDir.appendingPathComponent("prod-restored.sqlite")
        try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: restoredURL,
            userDefaults: defaults
        )

        // Assert — restored DB has the same table list and every seeded row.
        let restoredQueue = try DatabaseQueue(path: restoredURL.path)
        let restoredTables: [String] = try restoredQueue.read { db in
            try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type='table'
                  AND name NOT LIKE 'sqlite_%'
                  AND name NOT LIKE 'grdb_%'
                ORDER BY name
                """)
        }
        XCTAssertEqual(
            restoredTables, originalTables,
            "all production tables must round-trip; diff = \(Set(originalTables).symmetricDifference(Set(restoredTables)))"
        )

        for table in insertedTables {
            let count: Int = try restoredQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(table)") ?? 0
            }
            XCTAssertEqual(count, 1, "\(table) row must survive backup → restore")
        }
    }

    // MARK: - Helpers

    // MARK: - Progress photos in the archive (2026-07-14)

    func testPhotosRoundTripInBackup() throws {
        let photosSrc = workDir.appendingPathComponent("photos-src", isDirectory: true)
        try FileManager.default.createDirectory(at: photosSrc, withIntermediateDirectories: true)
        let jpgA = Data((0..<2048).map { UInt8($0 % 251) })
        let jpgB = Data((0..<1024).map { UInt8(($0 * 7) % 253) })
        try jpgA.write(to: photosSrc.appendingPathComponent("2026-07-01_front.jpg"))
        try jpgB.write(to: photosSrc.appendingPathComponent("2026-07-01_left.jpg"))
        try Data("not a photo".utf8).write(to: photosSrc.appendingPathComponent("notes.txt")) // non-jpg ignored

        let backupURL = try makeBackup(
            seedRows: 3, schemaVersion: Migrations.currentVersion, photosDir: photosSrc)

        let photosDest = workDir.appendingPathComponent("photos-dest", isDirectory: true)
        let dest = workDir.appendingPathComponent("restored-photos.sqlite")
        _ = try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults,
            currentSchemaVersion: Migrations.currentVersion,
            scratchDir: workDir.appendingPathComponent("scratch-photos", isDirectory: true),
            photosDirectory: photosDest
        )

        XCTAssertEqual(try Data(contentsOf: photosDest.appendingPathComponent("2026-07-01_front.jpg")), jpgA)
        XCTAssertEqual(try Data(contentsOf: photosDest.appendingPathComponent("2026-07-01_left.jpg")), jpgB)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photosDest.appendingPathComponent("notes.txt").path))
    }

    func testBackupWithoutPhotosRestoresCleanlyIntoPhotoDirectory() throws {
        // Older backups carry no photos/ entries — restoring with a photos
        // destination must be a silent no-op, not a failure.
        let backupURL = try makeBackup(seedRows: 2, schemaVersion: Migrations.currentVersion)
        let photosDest = workDir.appendingPathComponent("photos-empty-dest", isDirectory: true)
        let dest = workDir.appendingPathComponent("restored-nophotos.sqlite")
        XCTAssertNoThrow(try BackupRestorer().restore(
            from: backupURL,
            toDatabasePath: dest,
            userDefaults: defaults,
            currentSchemaVersion: Migrations.currentVersion,
            scratchDir: workDir.appendingPathComponent("scratch-nophotos", isDirectory: true),
            photosDirectory: photosDest
        ))
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: photosDest.path)) ?? []
        XCTAssertTrue(contents.isEmpty)
    }

    private func makeBackup(
        seedRows: Int,
        schemaVersion: Int,
        withDefaults extraDefaults: [String: Any] = [:],
        includeRealMigrations: Bool = false,
        extraSQL: [String] = [],
        photosDir: URL? = nil
    ) throws -> URL {
        let dbURL = workDir.appendingPathComponent("source-\(UUID().uuidString).sqlite")
        let dbQueue = try DatabaseQueue(path: dbURL.path)
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TABLE seed_row (id INTEGER PRIMARY KEY, value TEXT)")
            for i in 0..<seedRows {
                try db.execute(sql: "INSERT INTO seed_row(value) VALUES(?)", arguments: ["row-\(i)"])
            }
        }
        if includeRealMigrations {
            // Stamp a partial migration ledger so forward-migration test exercises
            // the migrator. Just record v1_weight as applied; later migrations will
            // run because grdb_migrations doesn't include them.
            try dbQueue.write { db in
                try db.execute(sql: "CREATE TABLE IF NOT EXISTS grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
                try db.execute(sql: "INSERT INTO grdb_migrations VALUES('v1_weight')")
                // The v1_weight migration creates weight_entry — pre-create so the
                // forward-migration replay doesn't try to recreate an existing table.
                try db.execute(sql: """
                    CREATE TABLE weight_entry (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        date TEXT NOT NULL UNIQUE,
                        weight_kg REAL NOT NULL,
                        source TEXT NOT NULL DEFAULT 'manual',
                        created_at TEXT NOT NULL DEFAULT (datetime('now')),
                        synced_from_hk INTEGER NOT NULL DEFAULT 0
                    )
                    """)
                try db.execute(sql: "CREATE INDEX idx_weight_entry_date ON weight_entry(date)")
            }
        }

        // Runs AFTER the migration-ledger block so extraSQL can stamp
        // additional migrations as applied (grdb_migrations exists by now).
        if !extraSQL.isEmpty {
            try dbQueue.write { db in
                for sql in extraSQL { try db.execute(sql: sql) }
            }
        }

        let suite = "BackupRestorerTestsBuild-\(UUID().uuidString)"
        let buildDefaults = UserDefaults(suiteName: suite)!
        for (k, v) in extraDefaults { buildDefaults.set(v, forKey: k) }
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let destination = workDir.appendingPathComponent("backup-\(UUID().uuidString).driftbackup")
        try BackupPackager().package(
            dbWriter: dbQueue,
            userDefaults: buildDefaults,
            appMetadata: .init(appBuild: "1042", appVersion: "2.1.0", schemaVersion: schemaVersion),
            destination: destination,
            photosDirectory: photosDir
        )
        return destination
    }

    /// Build a backup whose `preferences.json` is the literal `rawPrefsJSON`
    /// rather than the Packager's filtered output. Used by the crash-audit
    /// test (#687) to verify the Restorer doesn't crash on null / complex
    /// values that a hand-crafted backup could contain.
    ///
    /// We reuse the standard packager to produce a valid archive, then swap
    /// the prefs entry + recompute its manifest hash so integrity passes.
    private func makeBackupWithRawPreferencesJSON(
        seedRows: Int,
        schemaVersion: Int,
        rawPrefsJSON: String
    ) throws -> URL {
        let backupURL = try makeBackup(seedRows: seedRows, schemaVersion: schemaVersion)
        guard let archive = Archive(url: backupURL, accessMode: .update) else {
            throw NSError(domain: "test", code: 10)
        }
        // Swap the preferences entry for the raw JSON.
        if let oldPrefs = archive[BackupKeys.preferencesFileName] {
            try archive.remove(oldPrefs)
        }
        let prefsData = Data(rawPrefsJSON.utf8)
        try archive.addEntry(
            with: BackupKeys.preferencesFileName,
            type: .file,
            uncompressedSize: Int64(prefsData.count),
            compressionMethod: .deflate,
            provider: { position, size in
                prefsData.subdata(in: Int(position) ..< Int(position) + size)
            }
        )
        // Recompute the manifest's prefs entry so checksum validation passes.
        guard let manifestEntry = archive[BackupKeys.manifestFileName] else {
            throw NSError(domain: "test", code: 11)
        }
        var manifestData = Data()
        _ = try archive.extract(manifestEntry) { manifestData.append($0) }
        var manifest = try BackupManifest.decoder().decode(BackupManifest.self, from: manifestData)
        let newHash = SHA256.hash(data: prefsData).map { String(format: "%02x", $0) }.joined()
        manifest.files[BackupKeys.preferencesFileName] = .init(
            sha256: newHash,
            sizeBytes: Int64(prefsData.count)
        )
        let updated = try BackupManifest.encoder().encode(manifest)
        try archive.remove(manifestEntry)
        try archive.addEntry(
            with: BackupKeys.manifestFileName,
            type: .file,
            uncompressedSize: Int64(updated.count),
            compressionMethod: .deflate,
            provider: { position, size in
                updated.subdata(in: Int(position) ..< Int(position) + size)
            }
        )
        return backupURL
    }

    /// Recompose the archive with a deliberately-wrong manifest checksum for the
    /// DB entry, so integrity validation must reject it.
    private func corruptDatabaseChecksum(in backupURL: URL) throws {
        guard let archive = Archive(url: backupURL, accessMode: .update) else {
            throw NSError(domain: "test", code: 1)
        }
        guard let manifestEntry = archive[BackupKeys.manifestFileName] else {
            throw NSError(domain: "test", code: 2)
        }
        var manifestData = Data()
        _ = try archive.extract(manifestEntry) { manifestData.append($0) }
        var manifest = try BackupManifest.decoder().decode(BackupManifest.self, from: manifestData)
        if let dbEntry = manifest.files[BackupKeys.databaseFileName] {
            manifest.files[BackupKeys.databaseFileName] = .init(
                sha256: String(repeating: "0", count: 64),
                sizeBytes: dbEntry.sizeBytes
            )
        }
        let updated = try BackupManifest.encoder().encode(manifest)
        try archive.remove(manifestEntry)
        try archive.addEntry(
            with: BackupKeys.manifestFileName,
            type: .file,
            uncompressedSize: Int64(updated.count),
            compressionMethod: .deflate,
            provider: { position, size in
                updated.subdata(in: Int(position) ..< Int(position) + size)
            }
        )
    }
}
