import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — edge contracts for the pure Apple Health nutrition sample planner.
@Suite struct NutritionHealthSyncEdgeCaseTests {
    private func entry(
        id: Int64? = 17,
        calories: Double = 321.5,
        protein: Double = 27.25,
        carbs: Double = 42.75,
        fat: Double = 11.5,
        fiber: Double = 6.25,
        loggedAt: String = "2026-07-21T14:15:16Z",
        date: String? = "2026-07-21"
    ) -> FoodEntry {
        FoodEntry(
            id: id,
            mealLogId: 0,
            foodId: nil,
            foodName: "Sample meal",
            servingSizeG: 100,
            servings: 1,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            fiberG: fiber,
            createdAt: loggedAt,
            loggedAt: loggedAt,
            date: date,
            mealType: "lunch"
        )
    }

    @Test func specsPreserveValueKindIdentifierAndTimestampMapping() throws {
        let expectedDate = try #require(ISO8601DateFormatter().date(from: "2026-07-21T14:15:16Z"))
        let specs = NutritionHealthSync.specs(for: entry())

        #expect(specs.map(\.kind) == [.energyKcal, .proteinG, .carbsG, .fatG, .fiberG])
        #expect(specs.map(\.value) == [321.5, 27.25, 42.75, 11.5, 6.25])
        #expect(specs.map(\.syncIdentifier) == [
            "drift-food-17-kcal",
            "drift-food-17-protein",
            "drift-food-17-carbs",
            "drift-food-17-fat",
            "drift-food-17-fiber",
        ])
        #expect(specs.allSatisfy { $0.date == expectedDate })
    }

    @Test func everyNonPositiveNutrientIsOmitted() {
        let specs = NutritionHealthSync.specs(for: entry(
            calories: 0,
            protein: -1,
            carbs: 0,
            fat: -0.5,
            fiber: 0
        ))

        #expect(specs.isEmpty)
    }

    @Test func deletionIdentifiersCoverEveryKindInStableOrder() {
        #expect(NutritionHealthSync.syncIdentifiers(entryId: 123) == [
            "drift-food-123-kcal",
            "drift-food-123-protein",
            "drift-food-123-carbs",
            "drift-food-123-fat",
            "drift-food-123-fiber",
        ])
    }

    @Test func timestampAcceptsFractionalSecondsAheadOfDayFallback() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = try #require(formatter.date(from: "2026-07-20T23:59:58.125Z"))
        let value = NutritionHealthSync.timestamp(for: entry(
            loggedAt: "2026-07-20T23:59:58.125Z",
            date: "2026-07-01"
        ))

        #expect(value == expected)
    }
}
