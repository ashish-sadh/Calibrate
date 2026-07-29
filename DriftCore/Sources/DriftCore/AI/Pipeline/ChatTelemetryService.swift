import Foundation
import DriftCore
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

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
public final class ChatTelemetryService: @unchecked Sendable {
    public static let shared = ChatTelemetryService(db: AppDatabase.shared)

    /// Hard row cap. Chosen to fit ~months of heavy daily use (~100 turns/day)
    /// while keeping the table small on disk.
    public static let ringBufferLimit = 5000
    /// Fingerprint length in hex characters. 12 hex = 48 bits of entropy —
    /// enough to distinguish distinct queries in aggregates, not enough to
    /// reverse to source text.
    public static let fingerprintHexLength = 12

    private let db: AppDatabase
    private let serialQueue = DispatchQueue(label: "drift.chattelemetry", qos: .utility)

    init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Public API

    public enum Outcome: String {
        case success
        case failed
        case clarified
        case timeout
    }

    public enum IntentLabel: String {
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
    public func record(
        query: String,
        response: String? = nil,
        intent: IntentLabel?,
        tool: String?,
        outcome: Outcome,
        latencyMs: Int,
        turnIndex: Int
    ) {
        // Cloud mirror first, and on its OWN gate: the local ring buffer is a
        // debugging aid the user opts into separately, so a user who agreed to
        // share AI conversations shouldn't also have to enable local capture to
        // make that work (2026-07-28). Fire-and-forget — no latency here.
        TelemetryService.shared.aiTurn(
            surface: TelemetrySurface.coachChat,
            query: query,
            response: response,
            intent: intent?.rawValue,
            tool: tool,
            outcome: outcome.rawValue,
            latencyMS: max(0, latencyMs))

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
    public func fetchRecent(limit: Int = 5000) -> [ChatTurnRow] {
        (try? db.fetchChatTurns(limit: limit)) ?? []
    }

    public func count() -> Int { (try? db.chatTurnCount()) ?? 0 }

    /// Wipe all stored telemetry. Called from Settings [Delete All] or when
    /// the user flips the opt-in toggle off.
    public func deleteAll() {
        do {
            try db.deleteAllChatTurns()
        } catch {
            Log.app.error("ChatTelemetry deleteAll failed: \(error.localizedDescription)")
        }
    }

    /// Export as pretty-printed JSON. Returns nil if serialization fails or
    /// the table is empty.
    public func exportJSON() -> Data? {
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
    public static func fingerprint(for query: String) -> String {
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
    public struct ToolStat: Equatable {
        public let tool: String
        public let count: Int
        public let failed: Int

        public init(tool: String, count: Int, failed: Int) {
            self.tool = tool
            self.count = count
            self.failed = failed
        }
    }

    public struct LatencyStat: Equatable {
        public let p50: Int
        public let p95: Int
        public let count: Int

        public init(p50: Int, p95: Int, count: Int) {
            self.p50 = p50
            self.p95 = p95
            self.count = count
        }
    }

    /// Top-N tools by call count, with failure counts alongside.
    public func topTools(limit: Int = 10) -> [ToolStat] {
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
    public func topFailures(limit: Int = 10) -> [ToolStat] {
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
    public func recentFailures(hoursBack: Int = 24, limit: Int = 10) -> [ToolStat] {
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
    public func latency() -> LatencyStat {
        let rows = fetchRecent().map(\.latencyMs).sorted()
        guard !rows.isEmpty else { return LatencyStat(p50: 0, p95: 0, count: 0) }
        func percentile(_ p: Double) -> Int {
            let idx = max(0, min(rows.count - 1, Int((Double(rows.count) * p).rounded(.down))))
            return rows[idx]
        }
        return LatencyStat(p50: percentile(0.5), p95: percentile(0.95), count: rows.count)
    }
}
