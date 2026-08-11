@testable import DriftCore
import Testing

// The RecipeItem → PhotoLogItem seam (#1135): AI-chat composed-meal paths hand
// resolved RecipeItems to the editable review sheet, which speaks PhotoLogItem.
// The load-bearing rule is NO re-scaling — `resolveRecipeItem` already scaled
// the macros to the stated portion, so a second multiply would silently inflate
// every chat-logged meal.
@Suite struct PhotoLogItemFromRecipeItemTests {
    @Test func mapsGramsFromServingSizeAndPassesMacrosThrough() {
        let recipe = RecipeItem(name: "Dal Tadka", portionText: "1 bowl",
                                calories: 220, proteinG: 12, carbsG: 30, fatG: 6,
                                fiberG: 8, servingSizeG: 200)
        let item = PhotoLogItem(from: recipe)

        #expect(item.name == "Dal Tadka")
        #expect(item.grams == 200)
        #expect(item.calories == 220)
        #expect(item.proteinG == 12)
        #expect(item.carbsG == 30)
        #expect(item.fatG == 6)
        #expect(item.fiberG == 8)
        #expect(item.confidence == .medium)
    }

    @Test func doesNotRescaleAlreadyTotaledMacros() {
        // A 2-serving resolve arrives pre-multiplied (440 cal, 400g).
        let recipe = RecipeItem(name: "Roti", portionText: "2 rotis",
                                calories: 240, proteinG: 8, carbsG: 48, fatG: 2,
                                fiberG: 4, servingSizeG: 120)
        let item = PhotoLogItem(from: recipe)

        #expect(item.calories == 240)
        #expect(item.grams == 120)
    }

    @Test func zeroMacroPlaceholderSurvivesConversion() {
        // Unresolvable names come through as a 0-macro placeholder so the user
        // still sees the row (and can delete it) instead of a silent drop.
        let recipe = RecipeItem(name: "Grandma's pickle", portionText: "1 serving",
                                calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0)
        let item = PhotoLogItem(from: recipe)

        #expect(item.name == "Grandma's pickle")
        #expect(item.calories == 0)
        #expect(item.grams == 0)
        #expect(item.fiberG == 0)
    }
}
