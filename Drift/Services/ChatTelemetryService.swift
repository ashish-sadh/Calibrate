import Foundation
import CryptoKit

/// Opt-in, on-device only AI chat telemetry. Records turn metadata plus — when
/// opt-in is enabled — the raw user query and assistant response text so we
/// can audit real multi-turn failure transcripts. #261, raw-text capture v33.
///
/// - Disabled by default. All public entry points return early when the
///   `Preferences.chatTelemetryEnabled` gate is off.
/// - Ring buffer: caps `chat_turn` at `ringBufferLimit` rows.
/// - Network: zero. Raw text lives in the local SQLite DB and is only
///   transmitted when the user taps Export JSON + shares it themselves.
/// - Fingerprint is kept alongside raw text so aggregates that used it
///   (dedupe-by-query) still work after the schema change.
final class ChatTelemetryService: @unchecked Sendable {
    static let shared = ChatTelemetryService(db: AppDatabase.shared)

    /// Hard row cap. Chosen to fit ~months of heavy daily use (~100 turns/day)
    /// while keeping the table small on disk.
    static let ringBufferLimit = 5000
    /// Fingerprint length in hex characters. 12 hex = 48 bits of entropy —
    /// enough to distinguish distinct queries in aggregates, not enough to
    /// reverse to source text.
    static let fingerprintHexLength = 12

    private let db: AppDatabase
    private let serialQueue = DispatchQueue(label: "drift.chattelemetry", qos: .utility)

    init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Public API

    enum Outcome: String {
        case success
        case failed
        case clarified
        case timeout
    }

    enum IntentLabel: String {
        case toolCall = "tool_call"
        case text
        case clarification
        case timeout
        case ruleMatch = "rule_match"
    }

    /// Fire-and-forget record. Returns immediately; work happens on a utility
    /// queue. No-op when the opt-in gate is off.
    ///
    /// `response` is the final assistant-facing text. Stored verbatim alongside
    /// the query when opt-in is on so exported transcripts can drive multi-turn
    /// failure analysis. Both raw strings live only in the local DB.
    func record(
        query: String,
        response: String? = nil,
        intent: IntentLabel?,
        tool: String?,
        outcome: Outcome,
        latencyMs: Int,
        turnIndex: Int
    ) {
        guard Preferences.chatTelemetryEnabled else { return }
        let row = ChatTurnRow(
            timestamp: Self.iso8601.string(from: Date()),
            queryFingerprint: Self.fingerprint(for: query),
            intentLabel: intent?.rawValue,
            toolCalled: tool,
            outcome: outcome.rawValue,
            latencyMs: max(0, latencyMs),
            turnIndex: max(0, turnIndex),
            queryText: query,
            responseText: response
        )
        serialQueue.async { [db] in
            do {
                try db.insertChatTurn(row)
                try db.evictChatTurnsOver(cap: Self.ringBufferLimit)
            } catch {
                Log.app.error("ChatTelemetry insert failed: \(error.localizedDescription)")
            }
        }
    }

    /// Snapshot for the insights view. Safe to call regardless of opt-in state
    /// (returns empty when the table is empty).
    func fetchRecent(limit: Int = 5000) -> [ChatTurnRow] {
        (try? db.fetchChatTurns(limit: limit)) ?? []
    }

    func count() -> Int { (try? db.chatTurnCount()) ?? 0 }

    /// Wipe all stored telemetry. Called from Settings [Delete All] or when
    /// the user flips the opt-in toggle off.
    func deleteAll() {
        do {
            try db.deleteAllChatTurns()
        } catch {
            Log.app.error("ChatTelemetry deleteAll failed: \(error.localizedDescription)")
        }
    }

    /// Export as pretty-printed JSON. Returns nil if serialization fails or
    /// the table is empty.
    func exportJSON() -> Data? {
        let rows = fetchRecent()
        guard !rows.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(rows)
    }

    // MARK: - Fingerprinting

    /// SHA-256 of the normalized query, truncated to `fingerprintHexLength`.
    /// Normalization: lowercase, collapse whitespace, trim. Empty input yields
    /// the hash of an empty string (stable, consistent).
    static func fingerprint(for query: String) -> String {
        let normalized = query
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(fingerprintHexLength))
    }

    // MARK: - Private

    /// New formatter per call keeps the Sendable guarantees simple.
    /// ISO8601DateFormatter is non-Sendable; avoiding shared static state.
    private static var iso8601: ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }
}

// MARK: - Aggregates

extension ChatTelemetryService {
    struct ToolStat: Equatable {
        let tool: String
        let count: Int
        let failed: Int
    }

    struct LatencyStat: Equatable {
        let p50: Int
        let p95: Int
        let count: Int
    }

    /// Top-N tools by call count, with failure counts alongside.
    func topTools(limit: Int = 10) -> [ToolStat] {
        let rows = fetchRecent()
        var byTool: [String: (count: Int, failed: Int)] = [:]
        for row in rows {
            guard let t = row.toolCalled, !t.isEmpty else { continue }
            var bucket = byTool[t] ?? (0, 0)
            bucket.count += 1
            if row.outcome == Outcome.failed.rawValue || row.outcome == Outcome.timeout.rawValue {
                bucket.failed += 1
            }
            byTool[t] = bucket
        }
        return byTool
            .map { ToolStat(tool: $0.key, count: $0.value.count, failed: $0.value.failed) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    /// Top-N failure intents (tool or intent_label) — where users hit a wall.
    func topFailures(limit: Int = 10) -> [ToolStat] {
        let rows = fetchRecent().filter {
            $0.outcome == Outcome.failed.rawValue || $0.outcome == Outcome.timeout.rawValue
        }
        var byKey: [String: Int] = [:]
        for row in rows {
            let key = row.toolCalled ?? row.intentLabel ?? "unknown"
            byKey[key, default: 0] += 1
        }
        return byKey
            .map { ToolStat(tool: $0.key, count: $0.value, failed: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    /// Failure rollup over the last `hoursBack` hours — the aggregate the
    /// daily session summary surfaces so tool-call reliability regressions
    /// are visible without waiting for a user bug report. #281.
    ///
    /// Filters to `outcome ∈ {failed, timeout}` and groups by tool. Rows with
    /// no tool fall under `intent_label`, then `"unknown"`. Returns `[]` when
    /// opt-in is off (table is empty) or no failures in the window.
    func recentFailures(hoursBack: Int = 24, limit: Int = 10) -> [ToolStat] {
        let cutoff = Date().addingTimeInterval(-Double(max(0, hoursBack) * 3600))
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let rows = fetchRecent().filter { row in
            let isFailure = row.outcome == Outcome.failed.rawValue || row.outcome == Outcome.timeout.rawValue
            guard isFailure else { return false }
            guard let ts = parser.date(from: row.timestamp) else { return false }
            return ts >= cutoff
        }
        var byKey: [String: Int] = [:]
        for row in rows {
            let key = row.toolCalled ?? row.intentLabel ?? "unknown"
            byKey[key, default: 0] += 1
        }
        return byKey
            .map { ToolStat(tool: $0.key, count: $0.value, failed: $0.value) }
            .sorted { $0.count > $1.count }
            .prefix(limit)
            .map { $0 }
    }

    /// Latency percentiles over the recorded sample.
    func latency() -> LatencyStat {
        let rows = fetchRecent().map(\.latencyMs).sorted()
        guard !rows.isEmpty else { return LatencyStat(p50: 0, p95: 0, count: 0) }
        func percentile(_ p: Double) -> Int {
            let idx = max(0, min(rows.count - 1, Int((Double(rows.count) * p).rounded(.down))))
            return rows[idx]
        }
        return LatencyStat(p50: percentile(0.5), p95: percentile(0.95), count: rows.count)
    }
}
