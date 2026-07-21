import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — deterministic display and coding contracts for cached barcode data.
@Suite struct BarcodeCacheFormattingTests {
    @Test func displayNameIncludesBrandWhenAvailable() {
        #expect(makeCache(brand: "Acme Foods").displayName == "Rolled Oats - Acme Foods")
        #expect(makeCache(brand: nil).displayName == "Rolled Oats")
    }

    @Test func macroSummaryFormatsAllMacrosPerHundredGrams() {
        let cache = makeCache(
            calories: 389,
            protein: 16,
            carbs: 66,
            fat: 7,
            fiber: 11
        )

        #expect(cache.macroSummary == "389cal 16P 66C 7F per 100g")
    }

    @Test func codingUsesDatabaseColumnNames() throws {
        let data = try JSONEncoder().encode(makeCache(brand: "Acme Foods"))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["barcode"] as? String == "0123456789012")
        #expect(object["calories_per_100g"] as? Double == 389)
        #expect(object["protein_g_per_100g"] as? Double == 16)
        #expect(object["serving_size_g"] as? Double == 40)
        #expect(object["package_size_g"] as? Double == 500)
        #expect(object["created_at"] as? String == "2026-07-21T08:00:00Z")
        #expect(object["caloriesPer100g"] == nil)
    }

    private func makeCache(
        brand: String? = nil,
        calories: Double = 389,
        protein: Double = 16,
        carbs: Double = 66,
        fat: Double = 7,
        fiber: Double = 11
    ) -> BarcodeCache {
        BarcodeCache(
            barcode: "0123456789012",
            name: "Rolled Oats",
            brand: brand,
            caloriesPer100g: calories,
            proteinGPer100g: protein,
            carbsGPer100g: carbs,
            fatGPer100g: fat,
            fiberGPer100g: fiber,
            servingSizeG: 40,
            servingDescription: "1/2 cup",
            packageSizeG: 500,
            createdAt: "2026-07-21T08:00:00Z"
        )
    }
}
