import Foundation
@testable import DriftCore
import Testing

/// Tier 0 — the key-value seam (#1108). Locks the string-encoding contract the
/// Android SQLite store (`DbKeyValueStore`) relies on, plus the `app_pref`
/// table helpers, so both are verified without an emulator.
@Suite struct KeyValueStoreTests {

    // MARK: - StringEncodedKeyValueStore round-trips (the Android encoding)

    @Test func scalarRoundTrips() {
        let kv = StringEncodedKeyValueStore()

        kv.set("kg", forKey: "unit")
        #expect(kv.string(forKey: "unit") == "kg")

        kv.set(true, forKey: "on")
        kv.set(false, forKey: "off")
        #expect(kv.bool(forKey: "on") == true)
        #expect(kv.bool(forKey: "off") == false)

        kv.set(2000.5, forKey: "goal")
        #expect(kv.double(forKey: "goal") == 2000.5)

        kv.set(-7, forKey: "n")
        #expect(kv.integer(forKey: "n") == -7)
    }

    @Test func dataRoundTripHandlesArbitraryBytes() {
        let kv = StringEncodedKeyValueStore()
        // Non-UTF8 bytes prove the base64 path, not a naive string cast.
        let bytes = Data([0x00, 0xFF, 0x10, 0x7F, 0x80, 0x01])
        kv.set(bytes, forKey: "blob")
        #expect(kv.data(forKey: "blob") == bytes)

        // A real JSON payload (the shape WeightGoal / TDEE config store) survives too.
        let json = try? JSONEncoder().encode(["target": 72.5, "start": 80.0])
        kv.set(json, forKey: "goalJSON")
        #expect(kv.data(forKey: "goalJSON") == json)
    }

    @Test func stringArrayRoundTripPreservesOrder() {
        let kv = StringEncodedKeyValueStore()
        let favs = ["Bench Press", "Squat", "Deadlift"]
        kv.set(favs, forKey: "favorites")
        #expect(kv.stringArray(forKey: "favorites") == favs)
    }

    @Test func absentKeysReturnDefaults() {
        let kv = StringEncodedKeyValueStore()
        #expect(kv.string(forKey: "missing") == nil)
        #expect(kv.bool(forKey: "missing") == false)
        #expect(kv.double(forKey: "missing") == 0)
        #expect(kv.integer(forKey: "missing") == 0)
        #expect(kv.data(forKey: "missing") == nil)
        #expect(kv.stringArray(forKey: "missing") == nil)
        #expect(kv.hasValue(forKey: "missing") == false)
        #expect(kv.boolOrNil(forKey: "missing") == nil)
    }

    @Test func hasValueAndBoolOrNilDistinguishUnsetFromFalse() {
        let kv = StringEncodedKeyValueStore()
        // The default-ON toggles depend on "unset" ≠ "explicit false".
        #expect(kv.boolOrNil(forKey: "flag") == nil)
        #expect(kv.hasValue(forKey: "flag") == false)
        kv.set(false, forKey: "flag")
        #expect(kv.boolOrNil(forKey: "flag") == false)
        #expect(kv.hasValue(forKey: "flag") == true)
    }

    @Test func removeObjectClearsValue() {
        let kv = StringEncodedKeyValueStore()
        kv.set("x", forKey: "k")
        #expect(kv.hasValue(forKey: "k") == true)
        kv.removeObject(forKey: "k")
        #expect(kv.hasValue(forKey: "k") == false)
        #expect(kv.string(forKey: "k") == nil)
    }

    /// The subclass persistence hook receives the ENCODED string — the exact
    /// value DbKeyValueStore writes to SQLite.
    @Test func persistHookReceivesEncodedStrings() {
        final class Recorder: StringEncodedKeyValueStore, @unchecked Sendable {
            let lock = NSLock()
            var writes: [(String, String?)] = []
            override func persist(_ value: String?, forKey key: String) {
                lock.lock(); writes.append((key, value)); lock.unlock()
            }
        }
        let kv = Recorder()
        kv.set(true, forKey: "b")
        kv.set(3.5, forKey: "d")
        kv.removeObject(forKey: "b")
        #expect(kv.writes.count == 3)
        #expect(kv.writes[0].0 == "b" && kv.writes[0].1 == "1")
        #expect(kv.writes[1].0 == "d" && kv.writes[1].1 == "3.5")
        #expect(kv.writes[2].0 == "b" && kv.writes[2].1 == nil)
    }

    /// loadCache + cacheSnapshot are the prime()/flush primitives DbKeyValueStore
    /// uses; a value loaded into the cache reads back, and snapshot round-trips.
    @Test func loadCacheAndSnapshot() {
        let kv = StringEncodedKeyValueStore()
        kv.loadCache(["weight_unit": "kg", "flag": "1"])
        #expect(kv.string(forKey: "weight_unit") == "kg")
        #expect(kv.bool(forKey: "flag") == true)
        kv.set("lbs", forKey: "weight_unit")
        #expect(kv.cacheSnapshot()["weight_unit"] == "lbs")
    }

    // MARK: - AppDatabase app_pref helpers (the SQLite backing)

    @Test func appPrefUpsertGetRemove() throws {
        let db = try AppDatabase.empty()
        #expect(db.appPrefValue(forKey: "k") == nil)

        db.setAppPrefValue("v1", forKey: "k")
        #expect(db.appPrefValue(forKey: "k") == "v1")

        // Upsert: same key, new value wins (no duplicate-row crash).
        db.setAppPrefValue("v2", forKey: "k")
        #expect(db.appPrefValue(forKey: "k") == "v2")

        db.removeAppPrefValue(forKey: "k")
        #expect(db.appPrefValue(forKey: "k") == nil)
    }

    @Test func appPrefAllReturnsEveryRow() throws {
        let db = try AppDatabase.empty()
        db.setAppPrefValue("kg", forKey: "weight_unit")
        db.setAppPrefValue("1", forKey: "drift_ai_enabled")
        let all = db.allAppPrefs()
        #expect(all["weight_unit"] == "kg")
        #expect(all["drift_ai_enabled"] == "1")
        #expect(all.count == 2)
    }

    /// End-to-end for the Android path: a StringEncodedKeyValueStore whose
    /// persist writes through to `app_pref`, re-primed from a fresh store, keeps
    /// its values — the "survives process death" contract, minus the emulator.
    @Test func writeThroughToAppPrefSurvivesReprime() throws {
        let db = try AppDatabase.empty()

        final class DBStore: StringEncodedKeyValueStore, @unchecked Sendable {
            let db: AppDatabase
            init(_ db: AppDatabase) { self.db = db; super.init() }
            override func persist(_ value: String?, forKey key: String) {
                if let value { db.setAppPrefValue(value, forKey: key) }
                else { db.removeAppPrefValue(forKey: key) }
            }
        }

        let first = DBStore(db)
        first.set("kg", forKey: "weight_unit")
        first.set(true, forKey: "drift_ai_enabled")
        first.set(72.5, forKey: "goal")

        // Simulate a new process: a fresh store primed from the same DB.
        let second = DBStore(db)
        second.loadCache(db.allAppPrefs())
        #expect(second.string(forKey: "weight_unit") == "kg")
        #expect(second.bool(forKey: "drift_ai_enabled") == true)
        #expect(second.double(forKey: "goal") == 72.5)
    }
}
