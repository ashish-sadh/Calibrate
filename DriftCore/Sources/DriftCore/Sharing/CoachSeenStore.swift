import Foundation

/// "What's new since I last looked at this client" — the coach's unread mark.
///
/// This is Drift's honest substitute for a push notification. Real push would
/// need APNs/FCM credentials and a server-side trigger on `live_workouts`,
/// none of which exists (privacy-first: there is no always-on server watching
/// a client's training). So instead of pretending, the coach's own app marks
/// what it has already shown and badges the rest on next open — a signal that
/// is accurate whenever the coach is actually looking.
///
/// Durable via `DriftPlatform.keyValueStore` (the SQLite seam), NOT
/// UserDefaults: no UserDefaults write survives Android process death (#1108).
public enum CoachSeenStore {

    static func key(for clientID: String) -> String { "coach_seen_at_\(clientID)" }

    /// When the coach last opened this client's page. Nil = never looked, in
    /// which case everything shared so far counts as new.
    public static func lastSeen(client clientID: String) -> Date? {
        let raw = DriftPlatform.keyValueStore.double(forKey: key(for: clientID))
        return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
    }

    public static func markSeen(client clientID: String, at date: Date = Date()) {
        DriftPlatform.keyValueStore.set(date.timeIntervalSince1970, forKey: key(for: clientID))
    }

    /// Completed sessions this coach hasn't seen yet, for one client.
    ///
    /// Counts COMPLETED sessions only: an abandoned session is not an
    /// achievement to announce, and a live one is still in progress (the hub
    /// already shows those with a live dot).
    public static func unseenCount(for clientID: String,
                                   sessions: [LiveWorkoutDTO]) -> Int {
        let since = lastSeen(client: clientID)
        return sessions.filter { session in
            guard session.clientId == clientID, session.status == .completed else { return false }
            guard let startedAt = session.startedAt,
                  let date = DateFormatters.iso8601.date(from: startedAt)
                    ?? ISO8601DateFormatter().date(from: startedAt) else {
                // No parseable timestamp: treat as seen rather than badging
                // forever on a row that can never clear.
                return false
            }
            guard let since else { return true }
            return date > since
        }.count
    }
}
