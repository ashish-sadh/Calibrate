import Foundation
import GRDB

/// Product telemetry — what gets used, and (opt-in) what users actually ask the
/// AI. Drift's first analytics pipeline; adjudicated against tenets 2 and 5 in
/// `Docs/decisions.md` (2026-07-28).
///
/// **Fire-and-forget by construction.** `record` does one cheap local INSERT
/// into `telemetry_outbox` and returns; nothing about a user action ever waits
/// on the network. A background flusher drains the outbox to Supabase in
/// batches. If the device is offline, rows queue; if a row keeps failing it is
/// dropped after `maxAttempts` rather than retried forever. A telemetry failure
/// is never surfaced and never propagates — the app must behave identically
/// with the backend unreachable.
///
/// **Two independent gates** (`Preferences`):
/// - `usageTelemetryEnabled` — anonymous counts, ON by default, opt-out.
/// - `aiCaptureEnabled` — raw AI query/response text, OFF by default, opt-in,
///   because those carry health content.
///
/// Rows are keyed by an anonymous install UUID, never `auth.uid()` and never
/// the sharing @username: telemetry works signed-out and must not be joinable
/// to an identity.
public final class TelemetryService: @unchecked Sendable {
    public static let shared = TelemetryService(db: AppDatabase.shared, client: SyncClient())

    /// Rows per flush request. Small enough that one failure costs little,
    /// large enough that a chatty session doesn't make a request per tap.
    static let batchSize = 50
    /// A row failing this many flushes is dropped — telemetry is best-effort
    /// and must not grow the DB unboundedly on a persistent 4xx.
    static let maxAttempts = 5
    /// Hard cap on queued rows. Protects a long-offline device: oldest wins,
    /// because a stale count matters less than the DB staying small.
    static let outboxLimit = 2000

    private let db: AppDatabase
    private let client: SyncClient
    private let queue = DispatchQueue(label: "drift.telemetry", qos: .utility)
    /// Guards against two flushes racing the same rows.
    private let flushing = NSLock()
    private var isFlushing = false

    init(db: AppDatabase, client: SyncClient) {
        self.db = db
        self.client = client
    }

    // MARK: - Recording (never blocks, never throws)

    /// A user-visible action. `name` is a closed vocabulary (see `Event`);
    /// `props` must hold small enum-ish values only — no free text, no health
    /// data, nothing user-authored.
    public func event(_ name: String, props: [String: String] = [:]) {
        guard AppConfig.syncConfigured, Preferences.usageTelemetryEnabled else { return }
        let payload: [String: Any] = [
            "install_id": Preferences.telemetryInstallID,
            "name": name,
            "props": props,
            "platform": Self.platform,
            "app_version": Self.appVersion,
            "occurred_at": Self.timestamp(),
        ]
        enqueue(kind: "event", payload: payload)
    }

    /// One AI turn. `query`/`response` are only persisted when the AI-capture
    /// opt-in is on; with it off we still record the SHAPE of the turn
    /// (surface, intent, tool, outcome, latency) under the usage gate, which is
    /// what answers "is Describe routing correctly" without shipping content.
    public func aiTurn(
        surface: String,
        query: String?,
        response: String?,
        intent: String? = nil,
        tool: String? = nil,
        model: String? = nil,
        outcome: String,
        latencyMS: Int?
    ) {
        guard AppConfig.syncConfigured else { return }
        let captureText = Preferences.aiCaptureEnabled
        guard captureText || Preferences.usageTelemetryEnabled else { return }

        var payload: [String: Any] = [
            "install_id": Preferences.telemetryInstallID,
            "surface": surface,
            "outcome": outcome,
            "platform": Self.platform,
            "occurred_at": Self.timestamp(),
        ]
        if let v = Self.appVersion { payload["app_version"] = v }
        if let intent { payload["intent"] = intent }
        if let tool { payload["tool"] = tool }
        if let model { payload["model"] = model }
        if let latencyMS { payload["latency_ms"] = latencyMS }
        if captureText {
            // Bounded: a pathological paste shouldn't put 100KB on the wire.
            if let query { payload["query"] = String(query.prefix(4000)) }
            if let response { payload["response"] = String(response.prefix(8000)) }
        }
        enqueue(kind: "ai_turn", payload: payload)
    }

    // MARK: - Outbox

    private func enqueue(kind: String, payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        // Hop off the caller immediately — even a fast INSERT shouldn't sit in
        // a tap handler or a view body.
        queue.async { [db] in
            try? db.writer.write { conn in
                try conn.execute(sql: """
                    INSERT INTO telemetry_outbox (kind, payload, created_at, attempts)
                    VALUES (?, ?, ?, 0)
                    """, arguments: [kind, json, Self.timestamp()])
                // Trim oldest beyond the cap.
                try conn.execute(sql: """
                    DELETE FROM telemetry_outbox WHERE id NOT IN (
                        SELECT id FROM telemetry_outbox ORDER BY id DESC LIMIT ?
                    )
                    """, arguments: [Self.outboxLimit])
            }
        }
    }

    /// Drain the outbox. Safe to call often (app foreground/background, after a
    /// log) — it no-ops when another flush is in flight or the queue is empty.
    /// Errors are swallowed by design.
    public func flush() {
        guard AppConfig.syncConfigured else { return }
        flushing.lock()
        if isFlushing { flushing.unlock(); return }
        isFlushing = true
        flushing.unlock()

        Task.detached(priority: .background) { [weak self] in
            await self?.drain()
            self?.flushing.lock()
            self?.isFlushing = false
            self?.flushing.unlock()
        }
    }

    /// Pending rows. Non-async on purpose: inside an `async` function GRDB
    /// resolves `write`/`read` to its async overloads, which would suspend the
    /// flusher on the DB actor for every batch.
    private func pendingRows() -> [Row] {
        (try? db.writer.read { conn in
            try Row.fetchAll(conn, sql: """
                SELECT id, kind, payload, attempts FROM telemetry_outbox
                ORDER BY id ASC LIMIT ?
                """, arguments: [Self.batchSize])
        }) ?? []
    }

    /// Settle a finished batch: drop what landed, count a strike against what
    /// didn't, and evict rows that have exhausted their retries.
    private func settle(sent: [Int64], failed: [Int64]) {
        try? db.writer.write { conn in
            for id in sent {
                try conn.execute(sql: "DELETE FROM telemetry_outbox WHERE id = ?", arguments: [id])
            }
            for id in failed {
                try conn.execute(sql: """
                    UPDATE telemetry_outbox SET attempts = attempts + 1 WHERE id = ?
                    """, arguments: [id])
            }
            try conn.execute(sql: "DELETE FROM telemetry_outbox WHERE attempts >= ?",
                             arguments: [Self.maxAttempts])
        }
    }

    private func drain() async {
        while true {
            let rows = pendingRows()
            guard !rows.isEmpty else { return }

            var sent: [Int64] = []
            var failed: [Int64] = []
            for kind in ["event", "ai_turn"] {
                let group = rows.filter { ($0["kind"] as String?) == kind }
                guard !group.isEmpty else { continue }
                let ids = group.compactMap { $0["id"] as Int64? }
                let objects = group.compactMap { row -> Any? in
                    guard let json = row["payload"] as String?,
                          let data = json.data(using: .utf8) else { return nil }
                    return try? JSONSerialization.jsonObject(with: data)
                }
                let table = kind == "event" ? "telemetry_events" : "ai_turns"
                if await post(table: table, objects: objects) {
                    sent.append(contentsOf: ids)
                } else {
                    failed.append(contentsOf: ids)
                }
            }

            settle(sent: sent, failed: failed)
            // A failed batch means the backend is unhappy or unreachable — stop
            // now and let the next flush retry, rather than hammering it.
            if !failed.isEmpty { return }
            if rows.count < Self.batchSize { return }
        }
    }

    /// Bulk INSERT. Telemetry is write-only server-side (RLS grants INSERT and
    /// nothing else), so no representation is requested back.
    private func post(table: String, objects: [Any]) async -> Bool {
        guard !objects.isEmpty,
              let body = try? JSONSerialization.data(withJSONObject: objects) else { return false }
        do {
            try await client.restInsertRaw(path: table, body: body)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Environment

    static var platform: String {
        #if os(Android)
        return "android"
        #else
        return "ios"
        #endif
    }

    static var appVersion: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    static func timestamp(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

// MARK: - Event vocabulary

/// The closed set of telemetry event names. A constant here (rather than a
/// string at the call site) keeps the server-side vocabulary greppable and
/// stops two surfaces inventing different names for the same action.
public enum TelemetryEvent {
    public static let appOpen = "app_open"
    public static let foodLogged = "food_logged"
    public static let describeUsed = "describe_used"
    public static let searchUsed = "food_search_used"
    public static let aiRowTapped = "search_ai_row_tapped"
    public static let snapUsed = "snap_used"
    public static let barcodeUsed = "barcode_used"
    public static let weightLogged = "weight_logged"
    public static let workoutStarted = "workout_started"
    public static let workoutFinished = "workout_finished"
    public static let coachChatTurn = "coach_chat_turn"
    public static let supplementTaken = "supplement_taken"
    public static let screenView = "screen_view"
    public static let quickAdd = "quick_add"
    public static let workoutShared = "workout_shared"
    public static let templateShared = "template_shared"
}

/// Where an AI turn came from. Mirrors the surfaces the operator named:
/// Drift Coach chat, Describe, and every other AI entry point.
public enum TelemetrySurface {
    public static let coachChat = "coach_chat"
    public static let describeMeal = "describe_meal"
    public static let exerciseText = "exercise_text"
    public static let photoLog = "photo_log"
    public static let workoutScan = "workout_scan"
}
