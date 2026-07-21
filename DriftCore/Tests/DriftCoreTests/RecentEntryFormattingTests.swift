import Testing
@testable import DriftCore

/// Tier 0 — pure display and classification behavior for recent food entries.
@Suite struct RecentEntryFormattingTests {
    private func entry(
        foodId: Int64? = nil,
        calories: Double = 250,
        proteinG: Double = 20,
        carbsG: Double = 30,
        fatG: Double = 8,
        fiberG: Double = 4,
        servingSize: Double = 100,
        lastServings: Double = 1
    ) -> RecentEntry {
        RecentEntry(
            name: "Test Food",
            foodId: foodId,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG,
            servingSize: servingSize,
            lastServings: lastServings
        )
    }

    @Test func macroSummaryIncludesCaloriesAndPrimaryMacros() {
        #expect(entry().macroSummary == "250cal 20P 30C 8F")
    }

    @Test func macroSummaryTruncatesFractionalValuesTowardZero() {
        let recent = entry(calories: 249.9, proteinG: 19.8, carbsG: 30.7, fatG: 8.6)

        #expect(recent.macroSummary == "249cal 19P 30C 8F")
    }

    @Test func fiberAndServingMetadataDoNotChangeMacroSummary() {
        let first = entry(fiberG: 0, servingSize: 1, lastServings: 1)
        let second = entry(fiberG: 25, servingSize: 500, lastServings: 3)

        #expect(first.macroSummary == second.macroSummary)
    }

    @Test func databaseClassificationDependsOnFoodIdPresence() {
        #expect(entry(foodId: nil).isDBFood == false)
        #expect(entry(foodId: 0).isDBFood == true)
        #expect(entry(foodId: 42).isDBFood == true)
    }
}
