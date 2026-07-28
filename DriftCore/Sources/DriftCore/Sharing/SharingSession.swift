import Foundation
import GRDB

/// The signed-in sharing account: the auth tokens plus the claimed identity.
/// Persisted so the friend/trainer link survives app restarts and reinstalls-
/// with-restore. Never contains anything shown to other users beyond `username`.
public struct SharingSession: Sendable, Equatable {
    public var userID: String
    public var username: String?
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?

    public init(userID: String, username: String?, accessToken: String,
                refreshToken: String?, expiresAt: Date?) {
        self.userID = userID
        self.username = username
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// True when the access token is within `skew` of expiring (refresh due).
    public func isExpired(now: Date = Date(), skew: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false }
        return now.addingTimeInterval(skew) >= expiresAt
    }
}

/// Durable store for the sharing auth session + the local↔server ID map.
///
/// State lives in SQLite (`sync_session`, `sync_map` — migration v47), NOT
/// UserDefaults: Android drops UserDefaults writes (#1108), and a session that
/// evaporates on restart would break the persistent trainer link. Mirrors the
/// `CloudUsageThrottle` single-writer pattern exactly.
///
/// The access token additionally shadows into `DriftPlatform.secureStore` when
/// an app registers one (iOS Keychain / Android EncryptedSharedPreferences) —
/// the SQLite row is the durable floor, the secure store the protected upgrade.
/// Reads prefer the secure store's token when present.
public enum SharingSessionStore {

    /// Single-row table: `sync_session.id` is pinned to 1.
    private static let rowID: Int64 = 1
    private static let secureTokenKey = "drift.sharing.accessToken"

    /// Persist (insert or replace) the current session. Fails soft — a write
    /// error must not crash a logging flow; the user simply re-authenticates.
    @MainActor
    public static func save(_ session: SharingSession, db: AppDatabase = .shared) {
        do {
            try db.writer.write { conn in
                try conn.execute(sql: """
                    INSERT INTO sync_session
                        (id, user_id, username, access_token, refresh_token, expires_at, updated_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        user_id = excluded.user_id,
                        username = excluded.username,
                        access_token = excluded.access_token,
                        refresh_token = excluded.refresh_token,
                        expires_at = excluded.expires_at,
                        updated_at = excluded.updated_at
                    """, arguments: [
                        rowID, session.userID, session.username,
                        session.accessToken, session.refreshToken,
                        session.expiresAt?.timeIntervalSince1970,
                        Date().timeIntervalSince1970,
                    ])
            }
        } catch {
            Log.app.error("SharingSessionStore.save failed: \(error.localizedDescription)")
        }
        DriftPlatform.secureStore?.set(session.accessToken, forKey: secureTokenKey)
    }

    /// The stored session, or nil when signed out. The access token is taken
    /// from the secure store when one is registered (more protected), falling
    /// back to the SQLite copy.
    @MainActor
    public static func load(db: AppDatabase = .shared) -> SharingSession? {
        let row = (try? db.reader.read { conn in
            try Row.fetchOne(conn, sql: """
                SELECT user_id, username, access_token, refresh_token, expires_at
                FROM sync_session WHERE id = ?
                """, arguments: [rowID])
        }) ?? nil
        guard let row else { return nil }
        let userID: String = row["user_id"]
        let dbToken: String = row["access_token"]
        let token = DriftPlatform.secureStore?.string(forKey: secureTokenKey) ?? dbToken
        let expires: Double? = row["expires_at"]
        return SharingSession(
            userID: userID,
            username: row["username"],
            accessToken: token,
            refreshToken: row["refresh_token"],
            expiresAt: expires.map { Date(timeIntervalSince1970: $0) })
    }

    /// True when a session is stored — cheap gate for "is the user sharing?".
    @MainActor
    public static func isSignedIn(db: AppDatabase = .shared) -> Bool {
        load(db: db) != nil
    }

    /// Wipe the session (sign out). Clears the secure-store shadow too.
    @MainActor
    public static func clear(db: AppDatabase = .shared) {
        try? db.writer.write { conn in
            try conn.execute(sql: "DELETE FROM sync_session WHERE id = ?", arguments: [rowID])
        }
        DriftPlatform.secureStore?.set(nil, forKey: secureTokenKey)
    }
}

/// The kind of local record a `sync_map` row bridges to a server UUID.
public enum SyncEntityType: String, Sendable {
    case template
    case workout
}

/// Local `Int64` ⇄ server `uuid` bridge. Local records predate the account and
/// only have autoincrement IDs; shares must translate at the boundary. Stored
/// in `sync_map` (v47), keyed by (entity_type, local_id).
public enum SyncMap {

    /// Remember that `localID` of `type` corresponds to server `uuid`.
    @MainActor
    public static func link(_ type: SyncEntityType, localID: Int64, serverUUID: String,
                            db: AppDatabase = .shared) {
        try? db.writer.write { conn in
            try conn.execute(sql: """
                INSERT INTO sync_map (entity_type, local_id, server_uuid) VALUES (?, ?, ?)
                ON CONFLICT(entity_type, local_id) DO UPDATE SET server_uuid = excluded.server_uuid
                """, arguments: [type.rawValue, localID, serverUUID])
        }
    }

    /// The server UUID for a local record, if it's been shared before.
    @MainActor
    public static func serverUUID(_ type: SyncEntityType, localID: Int64,
                                  db: AppDatabase = .shared) -> String? {
        (try? db.reader.read { conn in
            try String.fetchOne(conn, sql: """
                SELECT server_uuid FROM sync_map WHERE entity_type = ? AND local_id = ?
                """, arguments: [type.rawValue, localID])
        }) ?? nil
    }

    /// The local record ID for a server UUID, if we have it locally.
    @MainActor
    public static func localID(_ type: SyncEntityType, serverUUID: String,
                               db: AppDatabase = .shared) -> Int64? {
        (try? db.reader.read { conn in
            try Int64.fetchOne(conn, sql: """
                SELECT local_id FROM sync_map WHERE entity_type = ? AND server_uuid = ?
                """, arguments: [type.rawValue, serverUUID])
        }) ?? nil
    }
}
