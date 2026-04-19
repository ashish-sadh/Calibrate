import Foundation

/// Reads and writes `PersistedConversationState` to the app's Documents directory.
/// Survives app relaunch; expires after `maxAge` so stale mid-flows don't hijack the chat.
///
/// All IO serializes on the main actor because writers are all @MainActor VMs.
@MainActor
final class ConversationStatePersistence {
    static let shared = ConversationStatePersistence()

    /// Persisted state older than this is treated as expired and discarded on load.
    static let maxAge: TimeInterval = 60 * 60           // 60 min

    /// A non-idle state older than this shows a "picking up where we left off" banner on restore.
    static let resumeBannerMinAge: TimeInterval = 5 * 60 // 5 min

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = docs.appendingPathComponent("conversation_state.json")
        }
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    /// Atomically write the snapshot. Silently ignores write errors so a failing disk
    /// never breaks chat — worst case is losing the ability to restore.
    func save(_ snapshot: PersistedConversationState) {
        do {
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            Log.app.error("ConversationStatePersistence.save failed: \(error.localizedDescription)")
        }
    }

    /// Returns the persisted state if present AND not expired. Expired state is cleared.
    func loadIfFresh(now: Date = Date()) -> PersistedConversationState? {
        guard let snapshot = loadRaw() else { return nil }
        let age = now.timeIntervalSince(snapshot.savedAt)
        if age < 0 || age >= Self.maxAge {
            clear()
            return nil
        }
        return snapshot
    }

    /// True when a non-idle snapshot is old enough to warrant a visible "picking up" banner.
    func shouldShowResumeBanner(_ snapshot: PersistedConversationState, now: Date = Date()) -> Bool {
        guard snapshot.isMeaningful else { return false }
        return now.timeIntervalSince(snapshot.savedAt) >= Self.resumeBannerMinAge
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    // Exposed for tests that need to inspect raw-on-disk regardless of freshness.
    func loadRaw() -> PersistedConversationState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            return try decoder.decode(PersistedConversationState.self, from: data)
        } catch {
            Log.app.error("ConversationStatePersistence.load failed: \(error.localizedDescription)")
            return nil
        }
    }
}
