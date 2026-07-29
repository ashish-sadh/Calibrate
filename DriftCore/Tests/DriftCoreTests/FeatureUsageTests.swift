import Foundation
import GRDB
@testable import DriftCore
import Testing

/// Tier-0 for the `FeatureUsage` façade. The old suite asserted the on-device
/// UserDefaults counters (`all` / `reset` / `exportText`), which were removed on
/// 2026-07-28 when usage counts moved to the anonymous server-side pipeline —
/// those APIs no longer exist, so this covers the routing that replaced them.
@MainActor
struct FeatureUsageTests {

    nonisolated private func outboxPayloads(_ db: AppDatabase) throws -> [String] {
        try db.writer.read { conn in
            try String.fetchAll(conn, sql: "SELECT payload FROM telemetry_outbox ORDER BY id")
        }
    }

    private func settle() async {
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    /// `screen.*` events collapse to ONE server event name with the screen as a
    /// prop, so the vocabulary stays closed as screens are added.
    @Test func screenEventsCollapseToScreenViewWithAProp() async throws {
        let db = try AppDatabase.empty()
        Preferences.usageTelemetryEnabled = true
        TelemetryService(db: db, client: SyncClient())
            .event(TelemetryEvent.screenView, props: ["screen": "food"])
        await settle()

        let payload = try outboxPayloads(db).first ?? ""
        #expect(payload.contains("screen_view"))
        #expect(payload.contains("food"))
    }

    /// Non-screen actions keep their own name rather than being flattened.
    @Test func actionEventsKeepTheirOwnName() async throws {
        let db = try AppDatabase.empty()
        Preferences.usageTelemetryEnabled = true
        TelemetryService(db: db, client: SyncClient()).event("action.log_food")
        await settle()

        #expect(try outboxPayloads(db).first?.contains("action.log_food") == true)
    }
}
