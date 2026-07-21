import Foundation
import Testing
@testable import DriftCore

@Suite struct FoodNormalizedKeyTests {
    @Test func normalizationLowercasesSortsAndRemovesPunctuation() {
        #expect(Food.normalizedKey("  Athletic Greens — AG1! ") == "ag1 athletic greens")
    }

    @Test func wordOrderDoesNotChangeCanonicalKey() {
        let brandFirst = Food.normalizedKey("AG1 Athletic Greens")
        let brandLast = Food.normalizedKey("Athletic Greens AG1")

        #expect(brandFirst == brandLast)
    }

    @Test func emptyAndPunctuationOnlyNamesProduceEmptyKey() {
        #expect(Food.normalizedKey("") == "")
        #expect(Food.normalizedKey(" — / ! ") == "")
    }

    @Test func renamingFoodRefreshesDerivedKey() {
        var food = Food(
            name: "Plain Yogurt",
            category: "Dairy",
            servingSize: 170,
            servingUnit: "g",
            calories: 100
        )

        #expect(food.normalizedKey == "plain yogurt")

        food.name = "Greek Yogurt"

        #expect(food.normalizedKey == "greek yogurt")
    }

    @Test func decodingRebuildsRatherThanTrustingStoredKey() throws {
        let json = Data(#"""
        {
          "name": "Greek Yogurt",
          "normalized_key": "stale-key",
          "category": "Dairy",
          "serving_size": 170,
          "serving_unit": "g",
          "calories": 100
        }
        """#.utf8)

        let food = try JSONDecoder().decode(Food.self, from: json)

        #expect(food.normalizedKey == "greek yogurt")
    }
}
