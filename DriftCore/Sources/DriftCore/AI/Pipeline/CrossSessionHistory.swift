import Foundation

/// Persists the last 5 conversation turns across app sessions so the AI
/// has continuity after a restart. Context older than 24 hours is discarded.
///
/// All storage is local — `UserDefaults.standard` as JSON. Nothing leaves the device.
public enum CrossSessionHistory {

    private struct Persisted: Codable {
        struct Turn: Codable {
            let role: String  // "user" | "assistant"
            let text: String
        }
        let turns: [Turn]
        let savedAt: Date
    }

    private static let key = "drift_cross_session_history"
    public static let maxTurns = 5
    public static let ttl: TimeInterval = 24 * 60 * 60

    /// Persist the last 5 turns. Call after each assistant response.
    public static func save(_ turns: [HistoryTurn]) {
        guard Preferences.conversationHistoryEnabled else { return }
        let kept = turns.suffix(maxTurns).map {
            Persisted.Turn(role: $0.role == .user ? "user" : "assistant", text: $0.text)
        }
        guard !kept.isEmpty,
              let data = try? JSONEncoder().encode(Persisted(turns: kept, savedAt: Date())) else { return }
        DriftPlatform.keyValueStore.set(data, forKey: key)
    }

    /// Load persisted turns if saved within the 24 h TTL, else return nil.
    public static func loadIfFresh(now: Date = Date()) -> [HistoryTurn]? {
        guard Preferences.conversationHistoryEnabled,
              let data = DriftPlatform.keyValueStore.data(forKey: key),
              let stored = try? JSONDecoder().decode(Persisted.self, from: data),
              now.timeIntervalSince(stored.savedAt) < ttl,
              !stored.turns.isEmpty else { return nil }
        return stored.turns.map {
            HistoryTurn(role: $0.role == "user" ? .user : .assistant, text: $0.text)
        }
    }

    public static func clear() {
        DriftPlatform.keyValueStore.removeObject(forKey: key)
    }
}
