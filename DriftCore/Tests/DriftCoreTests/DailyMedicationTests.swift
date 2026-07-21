import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — pure value and persistence-coding contracts for legacy medication logs.
@Suite struct DailyMedicationTests {

    @Test func initializerDefaultsOptionalDoseAndIdentifierToAbsent() {
        let medication = DailyMedication(
            name: "metformin",
            loggedAt: "2026-07-21T08:30:00Z"
        )

        #expect(medication.id == nil)
        #expect(medication.name == "metformin")
        #expect(medication.doseMg == nil)
        #expect(medication.doseUnit == nil)
        #expect(medication.loggedAt == "2026-07-21T08:30:00Z")
    }

    @Test func initializerPreservesCompleteDoseValues() {
        let medication = DailyMedication(
            id: 17,
            name: "semaglutide",
            doseMg: 0.5,
            doseUnit: "mg",
            loggedAt: "2026-07-21T09:15:00Z"
        )

        #expect(medication.id == 17)
        #expect(medication.name == "semaglutide")
        #expect(medication.doseMg == 0.5)
        #expect(medication.doseUnit == "mg")
        #expect(medication.loggedAt == "2026-07-21T09:15:00Z")
    }

    @Test func codableUsesPersistenceFieldNamesAndRoundTrips() throws {
        let original = DailyMedication(
            id: 17,
            name: "cyanocobalamin",
            doseMg: 1_000,
            doseUnit: "mcg",
            loggedAt: "2026-07-21T10:45:00Z"
        )

        let data = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["id"] as? Int == 17)
        #expect(object["name"] as? String == "cyanocobalamin")
        #expect(object["dose_mg"] as? Double == 1_000)
        #expect(object["dose_unit"] as? String == "mcg")
        #expect(object["logged_at"] as? String == "2026-07-21T10:45:00Z")
        #expect(object["doseMg"] == nil)
        #expect(object["doseUnit"] == nil)
        #expect(object["loggedAt"] == nil)

        let decoded = try JSONDecoder().decode(DailyMedication.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.name == original.name)
        #expect(decoded.doseMg == original.doseMg)
        #expect(decoded.doseUnit == original.doseUnit)
        #expect(decoded.loggedAt == original.loggedAt)
    }
}
