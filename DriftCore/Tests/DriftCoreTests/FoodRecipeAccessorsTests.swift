import Foundation
@testable import DriftCore
import Testing

@Suite struct FoodRecipeAccessorsTests {
    @Test func typedRecipeJSONProvidesNamesAndFullItems() throws {
        let items = [
            RecipeItem(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "Greek yogurt",
                portionText: "1 cup",
                calories: 130,
                proteinG: 23,
                carbsG: 9,
                fatG: 0,
                fiberG: 0,
                servingSizeG: 227
            ),
            RecipeItem(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "Blueberries",
                portionText: "1/2 cup",
                calories: 42,
                proteinG: 0.5,
                carbsG: 10.5,
                fatG: 0.2,
                fiberG: 1.8,
                servingSizeG: 74
            ),
        ]
        let ingredients = String(decoding: try JSONEncoder().encode(items), as: UTF8.self)
        let food = makeFood(name: "Yogurt bowl", ingredients: ingredients)

        #expect(food.ingredientList == ["Greek yogurt", "Blueberries"])
        #expect(food.recipeItems == items)
    }

    @Test func legacyStringArrayProvidesNamesButNotRecipeItems() {
        let food = makeFood(
            name: "Dal tadka",
            ingredients: #"["lentils","tomato","cumin"]"#
        )

        #expect(food.ingredientList == ["lentils", "tomato", "cumin"])
        #expect(food.recipeItems == nil)
    }

    @Test func absentOrMalformedJSONFallsBackToFoodName() {
        let absent = makeFood(name: "Plain oatmeal", ingredients: nil)
        let malformed = makeFood(name: "Broken recipe", ingredients: "not-json")

        #expect(absent.ingredientList == ["Plain oatmeal"])
        #expect(absent.recipeItems == nil)
        #expect(malformed.ingredientList == ["Broken recipe"])
        #expect(malformed.recipeItems == nil)
    }

    @Test func emptyArrayFallsBackToFoodNameButRemainsAValidTypedRecipe() {
        let food = makeFood(name: "Empty recipe", ingredients: "[]")

        #expect(food.ingredientList == ["Empty recipe"])
        #expect(food.recipeItems == [])
    }

    private func makeFood(name: String, ingredients: String?) -> Food {
        Food(
            name: name,
            category: "Recipe",
            servingSize: 1,
            servingUnit: "serving",
            calories: 0,
            ingredients: ingredients,
            source: "recipe",
            isRecipe: true
        )
    }
}
