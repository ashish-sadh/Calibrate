import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — pure value semantics for manually entered body composition data.
@Suite struct BodyCompositionModelTests {

    @Test func metadataAloneDoesNotCountAsBodyCompositionData() {
        let composition = BodyComposition(
            id: 42,
            date: "2026-07-21",
            source: "smart_scale",
            createdAt: "2026-07-21T08:30:00Z"
        )

        #expect(!composition.hasData)
    }

    @Test func everySupportedMeasurementCountsAsData() {
        let compositions = [
            BodyComposition(date: "2026-07-21", bodyFatPct: 18.5),
            BodyComposition(date: "2026-07-21", bmi: 23.1),
            BodyComposition(date: "2026-07-21", waterPct: 56.0),
            BodyComposition(date: "2026-07-21", muscleMassKg: 61.2),
            BodyComposition(date: "2026-07-21", boneMassKg: 3.1),
            BodyComposition(date: "2026-07-21", visceralFat: 7.0),
            BodyComposition(date: "2026-07-21", metabolicAge: 31),
        ]

        for composition in compositions {
            #expect(composition.hasData)
        }
    }

    @Test func zeroValueIsStillPresentData() {
        #expect(BodyComposition(date: "2026-07-21", bodyFatPct: 0).hasData)
        #expect(BodyComposition(date: "2026-07-21", metabolicAge: 0).hasData)
    }

    @Test func codableUsesPersistenceFieldNamesAndRoundTrips() throws {
        let original = BodyComposition(
            id: 9,
            date: "2026-07-21",
            bodyFatPct: 18.5,
            bmi: 23.1,
            waterPct: 56.0,
            muscleMassKg: 61.2,
            boneMassKg: 3.1,
            visceralFat: 7.0,
            metabolicAge: 31,
            source: "smart_scale",
            createdAt: "2026-07-21T08:30:00Z"
        )

        let data = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["body_fat_pct"] as? Double == 18.5)
        #expect(object["muscle_mass_kg"] as? Double == 61.2)
        #expect(object["created_at"] as? String == "2026-07-21T08:30:00Z")
        #expect(object["bodyFatPct"] == nil)

        let decoded = try JSONDecoder().decode(BodyComposition.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.date == original.date)
        #expect(decoded.bodyFatPct == original.bodyFatPct)
        #expect(decoded.bmi == original.bmi)
        #expect(decoded.waterPct == original.waterPct)
        #expect(decoded.muscleMassKg == original.muscleMassKg)
        #expect(decoded.boneMassKg == original.boneMassKg)
        #expect(decoded.visceralFat == original.visceralFat)
        #expect(decoded.metabolicAge == original.metabolicAge)
        #expect(decoded.source == original.source)
        #expect(decoded.createdAt == original.createdAt)
    }
}
