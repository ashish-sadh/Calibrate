import Testing
@testable import DriftCore

/// Tier 0 — pure formatting behavior for daily nutrition totals.
@Suite struct DailyNutritionFormattingTests {

    @Test func zeroTotalsProduceZeroMacroSummary() {
        #expect(DailyNutrition.zero.macroSummary == "0cal 0P 0C 0F")
    }

    @Test func macroSummaryTruncatesFractionalTotals() {
        let nutrition = DailyNutrition(
            calories: 1999.9,
            proteinG: 149.9,
            carbsG: 200.8,
            fatG: 79.7,
            fiberG: 30.5
        )

        #expect(nutrition.macroSummary == "1999cal 149P 200C 79F")
    }

    @Test func macroSummaryReflectsCurrentMutableTotals() {
        var nutrition = DailyNutrition.zero
        nutrition.calories = 450
        nutrition.proteinG = 32
        nutrition.carbsG = 48
        nutrition.fatG = 14

        #expect(nutrition.macroSummary == "450cal 32P 48C 14F")
    }

    @Test func fiberDoesNotChangeMacroSummary() {
        let withoutFiber = DailyNutrition(
            calories: 500,
            proteinG: 30,
            carbsG: 60,
            fatG: 15,
            fiberG: 0
        )
        let withFiber = DailyNutrition(
            calories: 500,
            proteinG: 30,
            carbsG: 60,
            fatG: 15,
            fiberG: 25
        )

        #expect(withFiber.macroSummary == withoutFiber.macroSummary)
    }
}
