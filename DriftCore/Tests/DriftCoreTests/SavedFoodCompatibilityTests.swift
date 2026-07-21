import Testing
@testable import DriftCore

/// Tier 0 — pure mapping from the legacy `SavedFood` initializer to `Food`.
@Suite struct SavedFoodCompatibilityTests {
    @Test func defaultInitializerCreatesSavedFoodDefaults() {
        let food = SavedFood(name: "Morning oats", calories: 320)

        #expect(food.id == nil)
        #expect(food.name == "Morning oats")
        #expect(food.normalizedKey == "morning oats")
        #expect(food.category == "Saved")
        #expect(food.servingSize == 1)
        #expect(food.servingUnit == "serving")
        #expect(food.calories == 320)
        #expect(food.proteinG == 0)
        #expect(food.carbsG == 0)
        #expect(food.fatG == 0)
        #expect(food.fiberG == 0)
        #expect(food.defaultServings == 1)
        #expect(!food.isRecipe)
        #expect(food.sortOrder == 0)
        #expect(food.ingredients == nil)
        #expect(!food.expandOnLog)
        #expect(food.source == "recipe")
    }

    @Test func recipeFlagSelectsRecipeCategory() {
        let food = SavedFood(
            name: "Lentil bowl",
            calories: 480,
            isRecipe: true
        )

        #expect(food.category == "Recipe")
        #expect(food.isRecipe)
        #expect(food.source == "recipe")
    }

    @Test func explicitLegacyValuesArePreserved() {
        let food = SavedFood(
            id: 42,
            name: "Protein bowl",
            calories: 515.5,
            proteinG: 38.25,
            carbsG: 54.75,
            fatG: 16.5,
            fiberG: 9.25,
            defaultServings: 1.5,
            isRecipe: true,
            sortOrder: 7,
            createdAt: "2026-07-21T08:30:00Z",
            ingredients: #"["tofu","rice"]"#,
            expandOnLog: true
        )

        #expect(food.id == 42)
        #expect(food.calories == 515.5)
        #expect(food.proteinG == 38.25)
        #expect(food.carbsG == 54.75)
        #expect(food.fatG == 16.5)
        #expect(food.fiberG == 9.25)
        #expect(food.defaultServings == 1.5)
        #expect(food.sortOrder == 7)
        #expect(food.ingredients == #"["tofu","rice"]"#)
        #expect(food.expandOnLog)
    }
}
