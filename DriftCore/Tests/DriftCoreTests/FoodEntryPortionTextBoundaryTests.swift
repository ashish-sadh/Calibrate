import Testing
@testable import DriftCore

/// Tier 0 — deterministic portion formatting with no database dependencies.
@Suite struct FoodEntryPortionTextBoundaryTests {
    private func entry(
        _ name: String,
        servingSizeG: Double,
        servings: Double = 1,
        loggedPortion: String? = nil
    ) -> FoodEntry {
        FoodEntry(
            foodName: name,
            servingSizeG: servingSizeG,
            servings: servings,
            calories: 0,
            loggedPortion: loggedPortion
        )
    }

    @Test func explicitLoggedPortionWinsOverDerivedFormatting() {
        let food = entry(
            "Egg",
            servingSizeG: 0,
            servings: 2,
            loggedPortion: "150 g"
        )

        #expect(food.portionText == "150 g")
    }

    @Test func unusableServingSizesProduceNoPortionText() {
        #expect(entry("Unknown", servingSizeG: 0).portionText == "")
        #expect(entry("Unknown", servingSizeG: -25).portionText == "")
        #expect(entry("Unknown", servingSizeG: .nan).portionText == "")
    }

    @Test func countableFoodsFormatSingularPluralAndFractionalServings() {
        #expect(entry("Egg", servingSizeG: 50).portionText == "1 egg")
        #expect(entry("Egg", servingSizeG: 50, servings: 2).portionText == "2 eggs")
        #expect(entry("Egg", servingSizeG: 50, servings: 1.5).portionText == "1.5 eggs")
    }

    @Test func pieceSizeThresholdsAreExclusive() {
        #expect(entry("Egg", servingSizeG: 79, servings: 2).portionText == "2 eggs")
        #expect(entry("Egg", servingSizeG: 80, servings: 2).portionText == "160g")
        #expect(entry("Banana", servingSizeG: 159, servings: 2).portionText == "2 bananas")
        #expect(entry("Banana", servingSizeG: 160, servings: 2).portionText == "320g")
    }

    @Test func keywordExceptionsAvoidFalseCountUnits() {
        #expect(entry("Cooked barley", servingSizeG: 157, servings: 2).portionText == "2 cups")
        #expect(entry("Protein bar", servingSizeG: 60, servings: 2).portionText == "2 bars")
        #expect(entry("Cough syrup", servingSizeG: 15, servings: 2).portionText == "30g")
    }

    @Test func drinkNamesRenderTheirPortionAsMilliliters() {
        #expect(entry("Caffe latte", servingSizeG: 240, servings: 1.5).portionText == "360ml")
        #expect(entry("Electrolyte drink", servingSizeG: 500).portionText == "500ml")
    }
}
