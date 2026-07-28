import Foundation
import DriftCore

/// Android durable key–value store, installed as `DriftPlatform.keyValueStore`.
///
/// Skip Fuse's SharedPreferences-backed `UserDefaults` never flushes to disk
/// (#1108): writes update the in-memory map, so reads work within a session,
/// but `defaults.xml` stays frozen at install time — every setting, the active
/// workout session (#1102), and sync anchors were lost on process death.
/// SQLite is proven durable on this build, so this store persists everything
/// into the `app_pref` table (v48).
///
/// The string encoding + the lock-guarded in-memory cache live in the DriftCore
/// base (`StringEncodedKeyValueStore`, Tier-0 tested). This subclass adds only:
///  - `persist`: write-through to `app_pref` — but ONLY after `prime()`, because
///    the first `AppDatabase.shared` touch runs migrations + the multi-MB food
///    seed, which must never happen on the launch main thread (the #1112 ANR).
///  - `prime()`: called off-main at warm-up, once the DB is open; loads the
///    durable rows into the cache, flushes any pre-prime writes, and runs the
///    one-time legacy migration.
///
/// Before priming, reads come from the (empty) cache → defaults, and writes
/// live only in the cache; `prime()` flushes them. In practice priming finishes
/// during warm-up, before real user interaction, so all durable writes persist.
final class DbKeyValueStore: StringEncodedKeyValueStore, @unchecked Sendable {
    private static let migratedMarkerKey = "__driftKVMigratedFromUserDefaults"

    private let primeLock = NSLock()
    private var primed = false
    /// Keys removed before priming — tracked so `prime()` doesn't resurrect a
    /// stale row from the DB when merging (a pre-prime write lives in the base
    /// cache and wins there, but a pre-prime remove leaves no cache trace).
    private var preprimeRemovals: Set<String> = []

    /// Write-through to SQLite. Skipped until primed — a pre-prime write would
    /// otherwise force `AppDatabase.shared`'s heavy first-open on the caller
    /// (possibly main) thread. Pre-prime writes stay in the cache and are
    /// flushed by `prime()`.
    override func persist(_ value: String?, forKey key: String) {
        primeLock.lock()
        if !primed {
            // Pre-prime: writes already live in the base cache (they flush at
            // prime); track removes so prime() honors them instead of merging
            // the stale DB row back in.
            if value == nil { preprimeRemovals.insert(key) } else { preprimeRemovals.remove(key) }
            primeLock.unlock()
            return
        }
        primeLock.unlock()
        if let value {
            AppDatabase.shared.setAppPrefValue(value, forKey: key)
        } else {
            AppDatabase.shared.removeAppPrefValue(forKey: key)
        }
    }

    /// Load durable state into the cache. MUST run off-main after warm-up has
    /// opened the shared DB (see `CoreResourcesBootstrap`). Idempotent.
    func prime() {
        primeLock.lock()
        if primed { primeLock.unlock(); return }
        let removals = preprimeRemovals
        primeLock.unlock()

        // Durable rows, with any pre-prime writes layered on top (they are newer
        // and win) and any pre-prime removes honored. Then mark primed and flush
        // those writes + deletes to disk.
        var merged = AppDatabase.shared.allAppPrefs()
        let pending = cacheSnapshot()
        for (key, value) in pending { merged[key] = value }
        for key in removals { merged[key] = nil }
        loadCache(merged)

        primeLock.lock(); primed = true; preprimeRemovals = []; primeLock.unlock()

        for (key, value) in pending { AppDatabase.shared.setAppPrefValue(value, forKey: key) }
        for key in removals { AppDatabase.shared.removeAppPrefValue(forKey: key) }
        migrateLegacyUserDefaultsIfNeeded()
    }

    /// One-time, guarded copy of the highest-value durable keys from the legacy
    /// (non-durable) UserDefaults into `app_pref`, so nothing legitimately
    /// seeded at install is dropped on the cutover. On this build UserDefaults
    /// usually holds only frozen install-seed values (the app now writes durable
    /// state through this store, not UserDefaults), so this rarely recovers
    /// anything — but it is safe and runs once.
    private func migrateLegacyUserDefaultsIfNeeded() {
        guard !hasValue(forKey: Self.migratedMarkerKey) else { return }
        let legacy = UserDefaults.standard

        if let unit = legacy.string(forKey: "weight_unit"), !hasValue(forKey: "weight_unit") {
            set(unit, forKey: "weight_unit")
        }
        if let session = legacy.string(forKey: "drift_active_workout_session"),
           !hasValue(forKey: "drift_active_workout_session") {
            set(session, forKey: "drift_active_workout_session")
        }
        let clearedAt = legacy.double(forKey: "drift_active_workout_session_cleared_at")
        if clearedAt > 0, !hasValue(forKey: "drift_active_workout_session_cleared_at") {
            set(clearedAt, forKey: "drift_active_workout_session_cleared_at")
        }
        let anchor = legacy.double(forKey: "hcWeightAnchorMillis")
        if anchor > 0, !hasValue(forKey: "hcWeightAnchorMillis") {
            set(anchor, forKey: "hcWeightAnchorMillis")
        }

        set("1", forKey: Self.migratedMarkerKey)
    }
}
