import Foundation
import Testing
@testable import Drift

// MARK: - FoodService Tests

// MARK: Search

@Test @MainActor func foodServiceSearchKnownFoodReturnsResults() {
    let results = FoodService.searchFood(query: "rice")
    #expect(!results.isEmpty, "Searching for 'rice' should return results")
}

@Test @MainActor func foodServiceSearchGibberishTracksEmptyResult() {
    // Should return empty and track the miss — just verify it doesn't crash
    let results = FoodService.searchFood(query: "xyzzy_nonexistent_zzz_9999")
    #expect(results.isEmpty)
}

@Test @MainActor func foodServiceSearchSynonymCurd() {
    // "curd" → "yogurt" synonym expansion; should return yogurt results
    let results = FoodService.searchFood(query: "curd")
    #expect(!results.isEmpty, "Synonym 'curd' should expand to find yogurt")
}

@Test @MainActor func foodServiceFindByNameKnownFood() {
    let food = FoodService.findByName("paneer")
    #expect(food != nil, "Should find paneer in the database")
}

@Test @MainActor func foodServiceFindByNameUnknown() {
    let food = FoodService.findByName("xyzzy_nonexistent_item_9999")
    #expect(food == nil)
}

@Test @MainActor func foodServiceSearchRecipesDoesNotCrash() {
    let results = FoodService.searchRecipes(query: "")
    // May be empty in test env; just verify it returns without crash
    #expect(results.count >= 0)
}

@Test @MainActor func foodServiceFetchRecentFoodsReturnsArray() {
    let recents = FoodService.fetchRecentFoods(limit: 5)
    #expect(recents.count >= 0)
    #expect(recents.count <= 5)
}

@Test @MainActor func foodServiceFetchFoodsByCategoryIndianStaples() {
    let foods = FoodService.fetchFoodsByCategory("Indian Staples")
    #expect(!foods.isEmpty, "Indian Staples category should have entries")
}

@Test @MainActor func foodServiceFetchFoodsByCategoryUnknown() {
    let foods = FoodService.fetchFoodsByCategory("zzz_no_such_category_xyz")
    #expect(foods.isEmpty)
}

@Test @MainActor func foodServiceIsFavoriteUnknownFood() {
    let result = FoodService.isFavorite(name: "xyzzy_unknown_food_zzz")
    #expect(result == false)
}

@Test @MainActor func foodServiceFetchCachedBarcodeNonexistent() {
    let result = FoodService.fetchCachedBarcode("000000000000")
    #expect(result == nil)
}

// MARK: Nutrition Lookup

@Test @MainActor func foodServiceGetNutritionKnownFood() {
    let result = FoodService.getNutrition(name: "paneer")
    #expect(result != nil, "paneer should be found in DB")
    if let r = result {
        #expect(r.food.calories > 0)
        #expect(!r.perServing.isEmpty)
        #expect(r.perServing.contains("cal"))
    }
}

@Test @MainActor func foodServiceGetNutritionUnknown() {
    let result = FoodService.getNutrition(name: "xyzzy_nonexistent_zzz")
    #expect(result == nil)
}

// MARK: Daily Totals

@Test @MainActor func foodServiceResolvedCalorieTargetIsPositive() {
    let target = FoodService.resolvedCalorieTarget()
    #expect(target >= 1200, "Calorie target should be at least 1200")
}

@Test @MainActor func foodServiceGetDailyTotalsTargetPositive() {
    let totals = FoodService.getDailyTotals()
    #expect(totals.target >= 1200)
    #expect(totals.eaten >= 0)
}

@Test @MainActor func foodServiceGetCaloriesLeftReturnsNonEmpty() {
    let result = FoodService.getCaloriesLeft()
    #expect(!result.isEmpty)
}

@Test @MainActor func foodServiceGetCaloriesLeftWithDateParam() {
    let result = FoodService.getDailyTotals(date: "2000-01-01")
    #expect(result.eaten == 0, "No food on year-2000 date")
    #expect(result.target >= 1200)
    #expect(result.remaining == result.target)
}

// MARK: Explain

@Test @MainActor func foodServiceExplainCaloriesContainsTDEE() {
    let text = FoodService.explainCalories()
    #expect(text.contains("TDEE"))
    #expect(text.contains("cal"))
}

@Test @MainActor func foodServiceExplainCaloriesMultiLine() {
    let text = FoodService.explainCalories()
    let lines = text.components(separatedBy: "\n")
    #expect(lines.count >= 4, "explainCalories should return at least 4 lines")
}

// MARK: Suggestions

@Test @MainActor func foodServiceTopProteinFoodsReturnsArray() {
    let foods = FoodService.topProteinFoods(limit: 3)
    #expect(foods.count <= 3)
}

@Test @MainActor func foodServiceTopProteinFoodsAllHavePositiveProtein() {
    let foods = FoodService.topProteinFoods(limit: 5)
    for food in foods {
        #expect(food.proteinG >= 0)
    }
}

@Test @MainActor func foodServiceSuggestMealReturnsArray() {
    let foods = FoodService.suggestMeal()
    #expect(foods.count <= 3)
}

@Test @MainActor func foodServiceSuggestMealWithBudget() {
    let foods = FoodService.suggestMeal(caloriesLeft: 500, proteinNeeded: 40)
    for food in foods {
        #expect(food.calories <= 500)
    }
}

// MARK: Delete Entry

@Test @MainActor func foodServiceDeleteEntryNotFound() {
    let result = FoodService.deleteEntry(matching: "xyzzy_no_such_food_zzz_999")
    // Either "No food logged today." or "Couldn't find '...' in today's food log."
    #expect(result.contains("No food logged") || result.contains("Couldn't find"))
}

@Test @MainActor func foodServiceDeleteEntryLastKeywordNoFood() {
    // "last" is a special keyword — if no entries today, returns "No food entries today."
    // In test env, likely no entries, so the path exercises the special "last" branch
    let result = FoodService.deleteEntry(matching: "last")
    #expect(!result.isEmpty)
}

// MARK: Preview / Copy Yesterday

@Test @MainActor func foodServicePreviewYesterdayReturnsString() {
    let result = FoodService.previewYesterday()
    #expect(!result.isEmpty)
}

@Test @MainActor func foodServiceCopyYesterdayReturnsString() {
    let result = FoodService.copyYesterday()
    // In test env likely no yesterday data; returns one of the empty-state messages
    #expect(!result.isEmpty)
}

// MARK: Fetch by ID

// MARK: - Recipe Editing (#192)

@Test @MainActor func foodServiceUpdateRecipePersistsIngredientsAndMacros() {
    // Create a 2-ingredient recipe via the normal save path, then edit it
    // through updateRecipe and verify the row is updated in place.
    let baseName = "test-recipe-192-\(UUID().uuidString.prefix(8))"
    let first = QuickAddView.RecipeItem(
        name: "chicken", portionText: "100g",
        calories: 165, proteinG: 31, carbsG: 0, fatG: 3.6, fiberG: 0, servingSizeG: 100)
    let second = QuickAddView.RecipeItem(
        name: "rice", portionText: "100g",
        calories: 130, proteinG: 2.7, carbsG: 28, fatG: 0.3, fiberG: 0.4, servingSizeG: 100)
    let initialJson = (try? JSONEncoder().encode([first, second]))
        .flatMap { String(data: $0, encoding: .utf8) }
    var recipe = SavedFood(
        name: baseName,
        calories: 295, proteinG: 33.7, carbsG: 28, fatG: 3.9, fiberG: 0.4,
        isRecipe: true, ingredients: initialJson)
    FoodService.saveRecipe(&recipe)
    guard let id = recipe.id else {
        Issue.record("saveRecipe failed to assign an ID")
        return
    }

    // Edit: add a third ingredient and rename.
    let third = QuickAddView.RecipeItem(
        name: "olive oil", portionText: "1 tbsp",
        calories: 119, proteinG: 0, carbsG: 0, fatG: 13.5, fiberG: 0, servingSizeG: 15)
    let newName = baseName + "-edited"
    FoodService.updateRecipe(id: id, name: newName, items: [first, second, third], servings: 1)

    // Reload and verify.
    let reloaded = FoodService.fetchFoodById(id)
    #expect(reloaded != nil)
    #expect(reloaded?.name == newName)
    #expect(reloaded?.isRecipe == true)
    // Totals = chicken + rice + olive oil = 414 cal, 33.7 P, 28 C, 17.4 F, 0.4 Fb
    #expect((reloaded?.calories ?? 0) == 414)
    #expect(abs((reloaded?.fatG ?? 0) - 17.4) < 0.01)
    // Ingredients JSON should have 3 items now.
    let items = reloaded?.recipeItems ?? []
    #expect(items.count == 3)
    #expect(items.contains(where: { $0.name == "olive oil" }))
}

@Test @MainActor func foodServiceUpdateRecipeRemovesIngredient() {
    // Create 3-ingredient recipe, remove one, verify totals and ingredients updated.
    let baseName = "test-recipe-remove-\(UUID().uuidString.prefix(8))"
    let a = QuickAddView.RecipeItem(name: "egg", portionText: "1", calories: 72, proteinG: 6, carbsG: 0, fatG: 5, fiberG: 0, servingSizeG: 50)
    let b = QuickAddView.RecipeItem(name: "toast", portionText: "1 slice", calories: 80, proteinG: 3, carbsG: 15, fatG: 1, fiberG: 1, servingSizeG: 30)
    let c = QuickAddView.RecipeItem(name: "butter", portionText: "1 tsp", calories: 34, proteinG: 0, carbsG: 0, fatG: 4, fiberG: 0, servingSizeG: 5)
    let initialJson = (try? JSONEncoder().encode([a, b, c])).flatMap { String(data: $0, encoding: .utf8) }
    var recipe = SavedFood(
        name: baseName,
        calories: 186, proteinG: 9, carbsG: 15, fatG: 10, fiberG: 1,
        isRecipe: true, ingredients: initialJson)
    FoodService.saveRecipe(&recipe)
    guard let id = recipe.id else { Issue.record("saveRecipe failed"); return }

    // Remove butter.
    FoodService.updateRecipe(id: id, name: baseName, items: [a, b], servings: 1)

    let reloaded = FoodService.fetchFoodById(id)
    let items = reloaded?.recipeItems ?? []
    #expect(items.count == 2)
    #expect(!items.contains(where: { $0.name == "butter" }))
    // Totals = egg + toast = 152 cal, 9 P, 15 C, 6 F, 1 Fb
    #expect(reloaded?.calories == 152)
    #expect(reloaded?.fatG == 6)
}

@Test @MainActor func foodServiceUpdateRecipeRespectsServings() {
    // Per-serving macros should be totals/servings when servings > 1.
    let baseName = "test-recipe-servings-\(UUID().uuidString.prefix(8))"
    let item = QuickAddView.RecipeItem(
        name: "pasta", portionText: "400g",
        calories: 800, proteinG: 20, carbsG: 160, fatG: 4, fiberG: 8, servingSizeG: 400)
    var recipe = SavedFood(
        name: baseName,
        calories: 800, proteinG: 20, carbsG: 160, fatG: 4, fiberG: 8,
        isRecipe: true, ingredients: nil)
    FoodService.saveRecipe(&recipe)
    guard let id = recipe.id else { Issue.record("saveRecipe failed"); return }

    // Edit with servings=4 → per-serving cal should be 200.
    FoodService.updateRecipe(id: id, name: baseName, items: [item], servings: 4)
    let reloaded = FoodService.fetchFoodById(id)
    #expect(reloaded?.calories == 200)
    #expect(reloaded?.carbsG == 40)
}

@Test @MainActor func foodServiceFetchFoodByIdNonexistent() {
    let food = FoodService.fetchFoodById(Int64.max)
    #expect(food == nil)
}

// MARK: - Recipe Expand-On-Log (#190)

@Test @MainActor func logRecipeAggregatedByDefault() throws {
    let db = try AppDatabase.empty()
    let vm = FoodLogViewModel(database: db)
    let items = [
        QuickAddView.RecipeItem(name: "coffee", portionText: "250ml",
                                calories: 5, proteinG: 0, carbsG: 1, fatG: 0, fiberG: 0, servingSizeG: 250),
        QuickAddView.RecipeItem(name: "milk", portionText: "50ml",
                                calories: 25, proteinG: 2, carbsG: 2, fatG: 1, fiberG: 0, servingSizeG: 50),
        QuickAddView.RecipeItem(name: "protein powder", portionText: "1 scoop",
                                calories: 120, proteinG: 24, carbsG: 3, fatG: 1, fiberG: 0, servingSizeG: 30),
    ]
    let ingredientsJson = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) }
    let recipe = SavedFood(name: "coffee-group-agg", calories: 150, proteinG: 26, carbsG: 6,
                           fatG: 2, fiberG: 0, isRecipe: true, ingredients: ingredientsJson,
                           expandOnLog: false)

    let expanded = FoodService.logRecipe(recipe, servings: 1, mealType: .breakfast, viewModel: vm)
    #expect(expanded == false, "logRecipe should return false when expandOnLog is off")

    let entries = try db.fetchFoodEntries(for: DateFormatters.todayString)
    #expect(entries.count == 1, "Aggregated recipe should produce exactly 1 entry")
    #expect(entries.first?.foodName == "coffee-group-agg")
    #expect(entries.first?.calories == 150)
}

@Test @MainActor func logRecipeExpandedCreatesOneEntryPerItem() throws {
    let db = try AppDatabase.empty()
    let vm = FoodLogViewModel(database: db)
    let items = [
        QuickAddView.RecipeItem(name: "dosa", portionText: "1",
                                calories: 180, proteinG: 4, carbsG: 33, fatG: 4, fiberG: 2, servingSizeG: 90),
        QuickAddView.RecipeItem(name: "sambar", portionText: "1 bowl",
                                calories: 80, proteinG: 4, carbsG: 12, fatG: 2, fiberG: 3, servingSizeG: 150),
    ]
    let ingredientsJson = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) }
    let recipe = SavedFood(name: "dosa+sambar", calories: 260, proteinG: 8, carbsG: 45,
                           fatG: 6, fiberG: 5, isRecipe: true, ingredients: ingredientsJson,
                           expandOnLog: true)

    let expanded = FoodService.logRecipe(recipe, servings: 1, mealType: .breakfast, viewModel: vm)
    #expect(expanded == true, "logRecipe should return true when expandOnLog is on")

    let entries = try db.fetchFoodEntries(for: DateFormatters.todayString)
    #expect(entries.count == 2, "Expanded recipe should produce one entry per ingredient")
    let names = Set(entries.map(\.foodName))
    #expect(names == ["dosa", "sambar"])
    // Per-item macros preserved (not summed into one row).
    let dosa = entries.first { $0.foodName == "dosa" }
    #expect(dosa?.calories == 180)
    #expect(dosa?.proteinG == 4)
    let sambar = entries.first { $0.foodName == "sambar" }
    #expect(sambar?.calories == 80)
}

@Test @MainActor func logRecipeExpandedScalesByServings() throws {
    let db = try AppDatabase.empty()
    let vm = FoodLogViewModel(database: db)
    let items = [
        QuickAddView.RecipeItem(name: "rice", portionText: "100g",
                                calories: 130, proteinG: 3, carbsG: 28, fatG: 0, fiberG: 0, servingSizeG: 100),
    ]
    let ingredientsJson = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) }
    let recipe = SavedFood(name: "rice-bowl", calories: 130, proteinG: 3, carbsG: 28,
                           fatG: 0, fiberG: 0, isRecipe: true, ingredients: ingredientsJson,
                           expandOnLog: true)

    _ = FoodService.logRecipe(recipe, servings: 2, mealType: .lunch, viewModel: vm)

    let entries = try db.fetchFoodEntries(for: DateFormatters.todayString)
    #expect(entries.count == 1)
    let rice = entries.first
    #expect(rice?.foodName == "rice")
    #expect(rice?.calories == 260, "Servings=2 should double the logged calories")
    #expect(rice?.servingSizeG == 200)
}

@Test @MainActor func updateRecipePersistsExpandOnLogFlag() {
    let baseName = "test-recipe-expand-\(UUID().uuidString.prefix(8))"
    let item = QuickAddView.RecipeItem(
        name: "oats", portionText: "50g",
        calories: 190, proteinG: 7, carbsG: 33, fatG: 3, fiberG: 5, servingSizeG: 50)
    var recipe = SavedFood(name: baseName, calories: 190, proteinG: 7, carbsG: 33,
                           fatG: 3, fiberG: 5, isRecipe: true, ingredients: nil)
    FoodService.saveRecipe(&recipe)
    guard let id = recipe.id else { Issue.record("saveRecipe failed"); return }

    // Default (expandOnLog=false).
    let initial = FoodService.fetchFoodById(id)
    #expect(initial?.expandOnLog == false)

    // Flip the flag.
    FoodService.updateRecipe(id: id, name: baseName, items: [item], servings: 1, expandOnLog: true)
    let reloaded = FoodService.fetchFoodById(id)
    #expect(reloaded?.expandOnLog == true)

    // Clean up.
    FoodService.deleteFavorite(id: id)
}

@Test @MainActor func logRecipeExpandedFallsBackWhenItemsMissing() throws {
    // Recipe flagged expandOnLog but with no ingredient JSON → behave aggregated.
    let db = try AppDatabase.empty()
    let vm = FoodLogViewModel(database: db)
    let recipe = SavedFood(name: "orphan-recipe", calories: 500, proteinG: 20, carbsG: 40,
                           fatG: 15, fiberG: 3, isRecipe: true, ingredients: nil,
                           expandOnLog: true)

    let expanded = FoodService.logRecipe(recipe, servings: 1, mealType: .snack, viewModel: vm)
    #expect(expanded == false, "Should fall through to aggregated when no items are present")

    let entries = try db.fetchFoodEntries(for: DateFormatters.todayString)
    #expect(entries.count == 1)
    #expect(entries.first?.calories == 500)
}
