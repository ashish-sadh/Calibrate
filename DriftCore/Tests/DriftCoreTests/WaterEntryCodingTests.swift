import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — pure value and persistence-coding contracts for hydration entries.
@Suite struct WaterEntryCodingTests {

    @Test func initializerDefaultsToManualSourceAndGeneratedTimestamp() {
        let entry = WaterEntry(date: "2026-07-21", amountMl: 350)

        #expect(entry.id == nil)
        #expect(entry.date == "2026-07-21")
        #expect(entry.amountMl == 350)
        #expect(entry.source == "manual")
        #expect(ISO8601DateFormatter().date(from: entry.loggedAt) != nil)
    }

    @Test func initializerPreservesExplicitPersistenceValues() {
        let entry = WaterEntry(
            id: 42,
            date: "2026-07-20",
            amountMl: 473.18,
            loggedAt: "2026-07-20T18:45:00Z",
            source: "health_connect"
        )

        #expect(entry.id == 42)
        #expect(entry.date == "2026-07-20")
        #expect(entry.amountMl == 473.18)
        #expect(entry.loggedAt == "2026-07-20T18:45:00Z")
        #expect(entry.source == "health_connect")
    }

    @Test func codableUsesDatabaseFieldNamesAndRoundTrips() throws {
        let original = WaterEntry(
            id: 42,
            date: "2026-07-20",
            amountMl: 473.18,
            loggedAt: "2026-07-20T18:45:00Z",
            source: "health_connect"
        )

        let data = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(Set(object.keys) == ["id", "date", "amount_ml", "logged_at", "source"])
        #expect(object["id"] as? Int == 42)
        #expect(object["date"] as? String == "2026-07-20")
        #expect(object["amount_ml"] as? Double == 473.18)
        #expect(object["logged_at"] as? String == "2026-07-20T18:45:00Z")
        #expect(object["source"] as? String == "health_connect")
        #expect(object["amountMl"] == nil)
        #expect(object["loggedAt"] == nil)

        let decoded = try JSONDecoder().decode(WaterEntry.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.date == original.date)
        #expect(decoded.amountMl == original.amountMl)
        #expect(decoded.loggedAt == original.loggedAt)
        #expect(decoded.source == original.source)
    }
}
