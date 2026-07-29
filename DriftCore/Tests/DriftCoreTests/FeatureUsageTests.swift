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
        TelemetryService(db: db, client: SyncClient()).event(TelemetryEvent.foodLogged)
        await settle()

        #expect(try outboxPayloads(db).first?.contains(TelemetryEvent.foodLogged) == true)
    }

    /// The vocabulary contract: every event a call site records must be a
    /// `TelemetryEvent` constant — screen views go through the "screen."
    /// prefix that collapses to `screen_view`. An ad-hoc string literal at a
    /// call site reopens the closed server-side vocabulary; reject it here at
    /// Tier 0 rather than noticing a stray name in the events table.
    @Test func callSitesRecordOnlyVocabularyConstants() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DriftCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // DriftCore
            .deletingLastPathComponent()   // repo root
        let roots = ["SharedUI", "Drift", "DriftCore/Sources", "drift-android/Sources/DriftAndroid"]
            .map { repoRoot.appendingPathComponent($0) }

        var callSites = 0
        var violations: [String] = []
        for root in roots {
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in files where url.pathExtension == "swift" {
                if url.path.contains("SharedUICopy") { continue }   // generated mirror
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
                for line in source.split(separator: "\n") {
                    guard let range = line.range(of: "FeatureUsage.record(") else { continue }
                    callSites += 1
                    let arg = line[range.upperBound...]
                    if !arg.hasPrefix("TelemetryEvent.") && !arg.hasPrefix("\"screen.") {
                        violations.append("\(url.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        // An empty scan means the roots above went stale, not that we are
        // clean — the app has ~20 real call sites (assert well below that so
        // legitimate consolidation does not trip it).
        #expect(callSites >= 10)
        #expect(violations.isEmpty, "ad-hoc event names at: \(violations)")
    }
}
