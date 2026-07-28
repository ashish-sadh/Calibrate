import Foundation
import GRDB

/// Per-device daily cap on cloud-AI calls (#1113) — protects the shared
/// Nebius team key from any one device exhausting the pool, by accident
/// (a retry loop) or on purpose. Caps are deliberately generous: a heavy
/// real user (coach chat + describe + photo logs all day) stays far under
/// them; only runaway automation trips.
///
/// Counters live in SQLite (v46), not UserDefaults — Android drops
/// UserDefaults writes (#1108), and a throttle that resets on app restart
/// is no throttle. One row per local-calendar day; old rows are pruned on
/// rollover. Enforced at `RemoteLLMBackend.respondStreamingCore`, the one
/// funnel every remote call (chat, describe, exercise text, photo scan)
/// flows through — denial surfaces as `.rateLimited`, so chat shows its
/// limit message and every extraction ladder falls back offline naturally.
public enum CloudUsageThrottle {

    /// Requests per device per local day. ~one call every 3 waking minutes.
    public static let maxRequestsPerDay = 300
    /// Approximate characters (prompt in + reply out) per device per day —
    /// a token proxy that also bounds many-small-calls abuse. Photo turns
    /// count a flat `photoCharEquivalent` on top of their text.
    public static let maxCharsPerDay = 600_000
    /// Char-equivalent charged per image attachment (vision turns cost far
    /// more provider-side than their prompt text suggests).
    public static let photoCharEquivalent = 8_000

    /// True when today's budget allows another call of `estimatedChars`;
    /// increments the counters when permitted. Fails OPEN on DB errors —
    /// a broken throttle must never take the product's showstopper down.
    @discardableResult
    public static func permit(estimatedChars: Int,
                              db: AppDatabase = .shared,
                              now: Date = Date()) -> Bool {
        let day = DateFormatters.dateOnly.string(from: now)
        do {
            return try db.writer.write { conn in
                let row = try Row.fetchOne(
                    conn, sql: "SELECT requests, chars FROM cloud_usage WHERE day = ?",
                    arguments: [day])
                let requests: Int = row?["requests"] ?? 0
                let chars: Int = row?["chars"] ?? 0
                guard requests + 1 <= maxRequestsPerDay,
                      chars + estimatedChars <= maxCharsPerDay else { return false }
                try conn.execute(sql: """
                    INSERT INTO cloud_usage (day, requests, chars) VALUES (?, 1, ?)
                    ON CONFLICT(day) DO UPDATE SET
                        requests = requests + 1,
                        chars = chars + excluded.chars
                    """, arguments: [day, estimatedChars])
                // Rollover prune — keeps the table one-to-few rows forever.
                try conn.execute(sql: "DELETE FROM cloud_usage WHERE day <> ?", arguments: [day])
                return true
            }
        } catch {
            Log.app.error("CloudUsageThrottle.permit failed open: \(error.localizedDescription)")
            return true
        }
    }

    /// Add the reply's size after a successful call (the request half was
    /// counted by `permit`). Never blocks — output of an already-permitted
    /// call is legitimate spend.
    public static func record(chars: Int, db: AppDatabase = .shared, now: Date = Date()) {
        guard chars > 0 else { return }
        let day = DateFormatters.dateOnly.string(from: now)
        try? db.writer.write { conn in
            try conn.execute(sql: """
                INSERT INTO cloud_usage (day, requests, chars) VALUES (?, 0, ?)
                ON CONFLICT(day) DO UPDATE SET chars = chars + excluded.chars
                """, arguments: [day, chars])
        }
    }

    /// Today's remaining budget — for a Settings/debug readout.
    public static func remainingToday(db: AppDatabase = .shared,
                                      now: Date = Date()) -> (requests: Int, chars: Int) {
        let day = DateFormatters.dateOnly.string(from: now)
        let row = (try? db.reader.read { conn in
            try Row.fetchOne(conn, sql: "SELECT requests, chars FROM cloud_usage WHERE day = ?",
                             arguments: [day])
        }) ?? nil
        let requests: Int = row?["requests"] ?? 0
        let chars: Int = row?["chars"] ?? 0
        return (max(0, maxRequestsPerDay - requests), max(0, maxCharsPerDay - chars))
    }
}
