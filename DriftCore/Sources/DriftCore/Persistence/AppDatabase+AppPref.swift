import Foundation
import GRDB

/// Durable key–value access over the `app_pref` table (v48, #1108). This is the
/// storage the Android `DbKeyValueStore` reads/writes through the
/// `DriftPlatform.keyValueStore` seam, because Skip Fuse's SharedPreferences
/// never flush to disk. iOS keeps using UserDefaults and never calls these.
///
/// All helpers are synchronous and fail-soft (`try?`) — a preference read or
/// write must never throw into a logging/UI flow. Writes are single-row
/// upserts on the (warm) pool, so they are sub-millisecond.
extension AppDatabase {
    /// One value, or nil when absent.
    public func appPrefValue(forKey key: String) -> String? {
        (try? reader.read { db in
            try String.fetchOne(db, sql: "SELECT value FROM app_pref WHERE key = ?", arguments: [key])
        }) ?? nil
    }

    /// Upsert one value.
    public func setAppPrefValue(_ value: String, forKey key: String) {
        try? writer.write { db in
            try db.execute(
                sql: "INSERT INTO app_pref (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key, value]
            )
        }
    }

    /// Delete one row (no-op when absent).
    public func removeAppPrefValue(forKey key: String) {
        try? writer.write { db in
            try db.execute(sql: "DELETE FROM app_pref WHERE key = ?", arguments: [key])
        }
    }

    /// The whole table as a dictionary — DbKeyValueStore primes its in-memory
    /// read cache from this once, off-main, after warm-up opens the DB.
    public func allAppPrefs() -> [String: String] {
        (try? reader.read { db -> [String: String] in
            var out: [String: String] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT key, value FROM app_pref") {
                let key: String = row["key"]
                let value: String = row["value"]
                out[key] = value
            }
            return out
        }) ?? [:]
    }
}
