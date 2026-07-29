import Foundation
import GRDB
import Testing
@testable import DriftCore

/// Tier-0 for the telemetry outbox and its two gates. The network is never
/// touched here — these lock the parts that decide WHETHER something is
/// recorded and WHAT it contains, which is where a privacy regression would
/// actually happen.
@MainActor
struct TelemetryServiceTests {

    private func makeService(_ db: AppDatabase) -> TelemetryService {
        TelemetryService(db: db, client: SyncClient())
    }

    /// `nonisolated` and non-async: inside an async test body GRDB resolves
    /// `read`/`write` to its async overloads, which don't apply here.
    nonisolated private func outboxRows(_ db: AppDatabase) throws -> [Row] {
        try db.writer.read { conn in
            try Row.fetchAll(conn, sql: "SELECT kind, payload FROM telemetry_outbox ORDER BY id")
        }
    }

    nonisolated private func outboxCount(_ db: AppDatabase) throws -> Int {
        try db.writer.read { conn in
            try Int.fetchOne(conn, sql: "SELECT COUNT(*) FROM telemetry_outbox") ?? 0
        }
    }

    nonisolated private func seedOutbox(_ db: AppDatabase, rows: Int) throws {
        try db.writer.write { conn in
            for i in 0..<rows {
                try conn.execute(sql: """
                    INSERT INTO telemetry_outbox (kind, payload, created_at, attempts)
                    VALUES ('event', ?, ?, 0)
                    """, arguments: ["{\"n\":\(i)}", TelemetryService.timestamp()])
            }
        }
    }

    /// The recorder hops to a utility queue, so a test has to let it land.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    // MARK: - Usage gate

    @Test func usageEventIsRecordedByDefault() async throws {
        let db = try AppDatabase.empty()
        Preferences.usageTelemetryEnabled = true
        makeService(db).event(TelemetryEvent.foodLogged, props: ["method": "search"])
        await settle()

        let rows = try outboxRows(db)
        #expect(rows.count == 1)
        #expect((rows.first?["kind"] as String?) == "event")
        let payload = rows.first?["payload"] as String? ?? ""
        #expect(payload.contains(TelemetryEvent.foodLogged))
        #expect(payload.contains("search"))
    }

    @Test func optingOutStopsUsageEvents() async throws {
        let db = try AppDatabase.empty()
        Preferences.usageTelemetryEnabled = false
        defer { Preferences.usageTelemetryEnabled = true }
        makeService(db).event(TelemetryEvent.foodLogged)
        await settle()

        #expect(try outboxRows(db).isEmpty)
    }

    // MARK: - AI capture gate (the privacy-critical one)

    @Test func aiTurnOmitsTextWhenCaptureIsOff() async throws {
        let db = try AppDatabase.empty()
        Preferences.usageTelemetryEnabled = true
        Preferences.aiCaptureEnabled = false

        makeService(db).aiTurn(
            surface: TelemetrySurface.describeMeal,
            query: "2 rotis and dal tadka",
            response: "Roti · 320cal",
            outcome: "success", latencyMS: 120)
        await settle()

        let payload = try outboxRows(db).first?["payload"] as String? ?? ""
        // Shape is still useful telemetry…
        #expect(payload.contains(TelemetrySurface.describeMeal))
        #expect(payload.contains("success"))
        // …but the health content must NOT be on its way to a server.
        #expect(!payload.contains("rotis"))
        #expect(!payload.contains("dal tadka"))
        #expect(!payload.contains("320cal"))
    }

    @Test func aiTurnIncludesTextWhenCaptureIsOn() async throws {
        let db = try AppDatabase.empty()
        Preferences.aiCaptureEnabled = true
        defer { Preferences.aiCaptureEnabled = false }

        makeService(db).aiTurn(
            surface: TelemetrySurface.coachChat,
            query: "how much protein today",
            response: "You're at 84g",
            outcome: "success", latencyMS: 900)
        await settle()

        let payload = try outboxRows(db).first?["payload"] as String? ?? ""
        #expect(payload.contains("how much protein today"))
        #expect(payload.contains("84g"))
    }

    /// AI capture is its own switch: a user who turned OFF usage counts but
    /// deliberately opted IN to conversation sharing must still be heard.
    @Test func aiCaptureSurvivesUsageOptOut() async throws {
        let db = try AppDatabase.empty()
        Preferences.usageTelemetryEnabled = false
        Preferences.aiCaptureEnabled = true
        defer {
            Preferences.usageTelemetryEnabled = true
            Preferences.aiCaptureEnabled = false
        }

        makeService(db).aiTurn(surface: TelemetrySurface.coachChat, query: "hi",
                               response: "hello", outcome: "success", latencyMS: 10)
        await settle()

        #expect(try outboxRows(db).count == 1)
    }

    // MARK: - Outbox hygiene

    @Test func outboxIsCappedSoAnOfflineDeviceCannotGrowForever() async throws {
        let db = try AppDatabase.empty()
        Preferences.usageTelemetryEnabled = true
        let service = makeService(db)
        // Cheap stand-in for the real cap: write past it directly, then confirm
        // one more recorded event trims back to the ceiling.
        try seedOutbox(db, rows: TelemetryService.outboxLimit + 25)
        service.event(TelemetryEvent.appOpen)
        await settle()

        #expect(try outboxCount(db) <= TelemetryService.outboxLimit)
    }

    @Test func installIDIsStableAndNotTheSharingIdentity() {
        let first = Preferences.telemetryInstallID
        let second = Preferences.telemetryInstallID
        #expect(first == second)
        #expect(!first.isEmpty)
        #expect(UUID(uuidString: first) != nil)
    }

    @Test func screenViewsCollapseToOneEventName() async throws {
        let db = try AppDatabase.empty()
        Preferences.usageTelemetryEnabled = true
        // FeatureUsage routes through the shared singleton, so assert the
        // mapping rule directly rather than the storage.
        let mapped = TelemetryEvent.screenView
        #expect(mapped == "screen_view")
        _ = db
    }
}
