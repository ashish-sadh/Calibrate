import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — pure value and serialization contracts for extracted biomarkers.
@Suite struct BiomarkerResultTests {
    @Test func initializerDefaultsNormalizationToReportedMeasurement() {
        let result = BiomarkerResult(
            reportId: 12,
            biomarkerId: "hba1c",
            value: 5.4,
            unit: "%",
            createdAt: "2026-07-21T08:30:00Z"
        )

        #expect(result.id == nil)
        #expect(result.normalizedValue == 5.4)
        #expect(result.normalizedUnit == "%")
        #expect(result.referenceLow == nil)
        #expect(result.referenceHigh == nil)
        #expect(result.confidence == nil)
        #expect(!result.isAIParsed)
    }

    @Test func initializerPreservesNormalizationAndExtractionMetadata() {
        let result = BiomarkerResult(
            id: 27,
            reportId: 12,
            biomarkerId: "vitamin_d",
            value: 75,
            unit: "nmol/L",
            normalizedValue: 30,
            normalizedUnit: "ng/mL",
            referenceLow: 20,
            referenceHigh: 50,
            confidence: 0.94,
            isAIParsed: true,
            createdAt: "2026-07-21T08:30:00Z"
        )

        #expect(result.id == 27)
        #expect(result.reportId == 12)
        #expect(result.biomarkerId == "vitamin_d")
        #expect(result.value == 75)
        #expect(result.unit == "nmol/L")
        #expect(result.normalizedValue == 30)
        #expect(result.normalizedUnit == "ng/mL")
        #expect(result.referenceLow == 20)
        #expect(result.referenceHigh == 50)
        #expect(result.confidence == 0.94)
        #expect(result.isAIParsed)
        #expect(result.createdAt == "2026-07-21T08:30:00Z")
    }

    @Test func codableUsesPersistenceFieldNamesAndRoundTrips() throws {
        let original = BiomarkerResult(
            id: 27,
            reportId: 12,
            biomarkerId: "vitamin_d",
            value: 75,
            unit: "nmol/L",
            normalizedValue: 30,
            normalizedUnit: "ng/mL",
            referenceLow: 20,
            referenceHigh: 50,
            confidence: 0.94,
            isAIParsed: true,
            createdAt: "2026-07-21T08:30:00Z"
        )

        let data = try JSONEncoder().encode(original)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["report_id"] as? Int == 12)
        #expect(object["biomarker_id"] as? String == "vitamin_d")
        #expect(object["normalized_value"] as? Double == 30)
        #expect(object["normalized_unit"] as? String == "ng/mL")
        #expect(object["reference_low"] as? Double == 20)
        #expect(object["reference_high"] as? Double == 50)
        #expect(object["is_ai_parsed"] as? Bool == true)
        #expect(object["created_at"] as? String == "2026-07-21T08:30:00Z")
        #expect(object["reportId"] == nil)

        let decoded = try JSONDecoder().decode(BiomarkerResult.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.reportId == original.reportId)
        #expect(decoded.biomarkerId == original.biomarkerId)
        #expect(decoded.value == original.value)
        #expect(decoded.unit == original.unit)
        #expect(decoded.normalizedValue == original.normalizedValue)
        #expect(decoded.normalizedUnit == original.normalizedUnit)
        #expect(decoded.referenceLow == original.referenceLow)
        #expect(decoded.referenceHigh == original.referenceHigh)
        #expect(decoded.confidence == original.confidence)
        #expect(decoded.isAIParsed == original.isAIParsed)
        #expect(decoded.createdAt == original.createdAt)
    }
}
