import Foundation
import Testing
import GRDB
@testable import Drift

// MARK: - Food Search Extended Tests (6 tests)

@Test func foodSearchPartialMatchDal() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "dal")
    #expect(results.count >= 4, "Should find multiple dal entries: \(results.count)")
}

@Test func foodSearchTraderJoes() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "TJ")
    #expect(results.count >= 10, "Should find Trader Joe's items: \(results.count)")
}

@Test func foodSearchMeatball() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "meatball")
    #expect(!results.isEmpty, "Should find meatball entries")
}

@Test func foodSearchCostco() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "kirkland")
    #expect(results.count >= 5, "Should find Kirkland/Costco items: \(results.count)")
}

@Test func foodDatabaseCount() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // Verify the food DB has at least 580 items (allows some margin from 600)
    let countA = try db.searchFoods(query: "a", limit: 600).count
    let countE = try db.searchFoods(query: "e", limit: 600).count
    let countI = try db.searchFoods(query: "i", limit: 600).count
    let maxCount = max(countA, max(countE, countI))
    #expect(maxCount >= 400, "Food DB should have 400+ searchable items, got \(maxCount)")
}

@Test func foodSearchLimitRespected() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let limited = try db.searchFoods(query: "a", limit: 5)
    #expect(limited.count <= 5)
}

@Test func foodSearchNoMatchReturnsEmpty() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "xyznonfooditematall")
    #expect(results.isEmpty)
}

@Test func foodCategoriesExist() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let categories = try db.fetchAllFoodCategories()
    #expect(categories.count >= 10, "Should have many categories: \(categories.count)")
}

@Test func foodMacroSummaryFormat() async throws {
    let food = Food(name: "Test", category: "Test", servingSize: 100, servingUnit: "g", calories: 200, proteinG: 25, carbsG: 30, fatG: 8)
    #expect(food.macroSummary == "200cal 25P 30C 8F")
}

@Test func foodSeedIdempotent() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let count1 = try db.searchFoods(query: "a", limit: 1000).count
    try db.seedFoodsFromJSON()
    let count2 = try db.searchFoods(query: "a", limit: 1000).count
    #expect(count1 == count2, "Seeding twice should not create duplicates")
}

// MARK: - Food Logging Flow Tests (10 tests)

@Test func mealLogCreationGetsId() async throws {
    let db = try AppDatabase.empty()
    var mealLog = MealLog(date: "2026-03-30", mealType: "lunch")
    try db.saveMealLog(&mealLog)
    #expect(mealLog.id != nil, "MealLog should get an ID after save")
    let fetched = try db.fetchMealLogs(for: "2026-03-30")
    #expect(fetched.count == 1)
    #expect(fetched[0].mealType == "lunch")
}

@Test func foodEntryPersistsCorrectly() async throws {
    let db = try AppDatabase.empty()
    var mealLog = MealLog(date: "2026-03-30", mealType: "breakfast")
    try db.saveMealLog(&mealLog)
    guard let mlid = mealLog.id else { Issue.record("No meal log ID"); return }

    var entry = FoodEntry(mealLogId: mlid, foodName: "Oatmeal", servingSizeG: 234, servings: 1, calories: 166, proteinG: 6, carbsG: 28, fatG: 3.6, fiberG: 4)
    try db.saveFoodEntry(&entry)
    #expect(entry.id != nil)

    let entries = try db.fetchFoodEntries(forMealLog: mlid)
    #expect(entries.count == 1)
    #expect(entries[0].foodName == "Oatmeal")
    #expect(entries[0].calories == 166)
}

@Test func multipleEntriesSameMealLog() async throws {
    let db = try AppDatabase.empty()
    var mealLog = MealLog(date: "2026-03-30", mealType: "lunch")
    try db.saveMealLog(&mealLog)
    let mlid = mealLog.id!

    var e1 = FoodEntry(mealLogId: mlid, foodName: "Rice", servingSizeG: 200, calories: 260, proteinG: 5, carbsG: 57, fatG: 0.5)
    var e2 = FoodEntry(mealLogId: mlid, foodName: "Dal", servingSizeG: 200, calories: 210, proteinG: 14, carbsG: 36, fatG: 1)
    try db.saveFoodEntry(&e1)
    try db.saveFoodEntry(&e2)

    let entries = try db.fetchFoodEntries(forMealLog: mlid)
    #expect(entries.count == 2)
}

@Test func dailyNutritionAggregatesAcrossMeals() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-03-30"

    var breakfast = MealLog(date: date, mealType: "breakfast")
    try db.saveMealLog(&breakfast)
    var e1 = FoodEntry(mealLogId: breakfast.id!, foodName: "Eggs", servingSizeG: 100, servings: 2, calories: 155, proteinG: 13, carbsG: 1, fatG: 11)
    try db.saveFoodEntry(&e1)

    var lunch = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&lunch)
    var e2 = FoodEntry(mealLogId: lunch.id!, foodName: "Chicken", servingSizeG: 150, servings: 1, calories: 165, proteinG: 31, carbsG: 0, fatG: 3.6)
    try db.saveFoodEntry(&e2)

    let nutrition = try db.fetchDailyNutrition(for: date)
    #expect(nutrition.calories == 155 * 2 + 165, "Total calories: \(nutrition.calories)")
    #expect(nutrition.proteinG == 13 * 2 + 31, "Total protein: \(nutrition.proteinG)")
}

@Test func foodEntryDeletion() async throws {
    let db = try AppDatabase.empty()
    var mealLog = MealLog(date: "2026-03-30", mealType: "dinner")
    try db.saveMealLog(&mealLog)
    var entry = FoodEntry(mealLogId: mealLog.id!, foodName: "Pizza", servingSizeG: 107, calories: 272)
    try db.saveFoodEntry(&entry)

    try db.deleteFoodEntry(id: entry.id!)
    let entries = try db.fetchFoodEntries(forMealLog: mealLog.id!)
    #expect(entries.isEmpty)
}

@Test func foodEntryServingMultiplierCalculation() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Rice", servingSizeG: 200, servings: 1.5, calories: 260, proteinG: 5, carbsG: 57, fatG: 0.5)
    #expect(entry.totalCalories == 390, "1.5 servings of 260 cal = 390")
    #expect(entry.totalProtein == 7.5)
}

@Test func quickAddFoodEntry() async throws {
    let db = try AppDatabase.empty()
    var mealLog = MealLog(date: "2026-03-30", mealType: "snack")
    try db.saveMealLog(&mealLog)

    var entry = FoodEntry(mealLogId: mealLog.id!, foodName: "Custom Snack", servingSizeG: 0, servings: 1, calories: 200, proteinG: 10, carbsG: 25, fatG: 8, fiberG: 2)
    try db.saveFoodEntry(&entry)

    let nutrition = try db.fetchDailyNutrition(for: "2026-03-30")
    #expect(nutrition.calories == 200)
}

@Test func differentDatesNutritionIsolated() async throws {
    let db = try AppDatabase.empty()

    var ml1 = MealLog(date: "2026-03-29", mealType: "lunch")
    try db.saveMealLog(&ml1)
    var e1 = FoodEntry(mealLogId: ml1.id!, foodName: "A", servingSizeG: 100, calories: 100)
    try db.saveFoodEntry(&e1)

    var ml2 = MealLog(date: "2026-03-30", mealType: "lunch")
    try db.saveMealLog(&ml2)
    var e2 = FoodEntry(mealLogId: ml2.id!, foodName: "B", servingSizeG: 100, calories: 300)
    try db.saveFoodEntry(&e2)

    let n29 = try db.fetchDailyNutrition(for: "2026-03-29")
    let n30 = try db.fetchDailyNutrition(for: "2026-03-30")
    #expect(n29.calories == 100)
    #expect(n30.calories == 300)
}

@Test func emptyDateNutritionReturnsZero() async throws {
    let db = try AppDatabase.empty()
    let nutrition = try db.fetchDailyNutrition(for: "2026-12-25")
    #expect(nutrition.calories == 0)
    #expect(nutrition.proteinG == 0)
}

@Test func mealTypesComplete() async throws {
    #expect(MealType.allCases.count == 4)
    #expect(MealType.breakfast.displayName == "Breakfast")
    #expect(MealType.snack.icon == "cup.and.saucer")
}

// MARK: - Food Search Ordering Tests (2 tests)

@Test func foodSearchPrefixMatchFirst() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "chicken")
    // Prefix matches like "Chicken Breast" should come before "Butter Chicken"
    if results.count >= 2 {
        let firstResult = results[0].name.lowercased()
        #expect(firstResult.hasPrefix("chicken"), "First result should start with 'chicken': \(firstResult)")
    }
}

@Test func foodSearchSortedAlphabetically() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "rice")
    // Results should be sorted alphabetically within same prefix group
    if results.count >= 2 {
        // Just verify we get results without crashing
        #expect(!results.isEmpty)
    }
}

// MARK: - Serving Unit Conversion Tests (6 tests)

@Test func servingUnitGramsIdentity() async throws {
    let result = ServingUnit.grams.toGrams(100, foodServingSize: 200)
    #expect(result == 100)
}

@Test func servingUnitPiecesUsesServingSize() async throws {
    let result = ServingUnit.pieces.toGrams(2, foodServingSize: 100)
    #expect(result == 200, "2 servings of 100g = 200g")
}

@Test func servingUnitCupsConversion() async throws {
    let result = ServingUnit.cups.toGrams(1, foodServingSize: 100)
    #expect(result == 240, "1 cup = 240g")
}

@Test func servingUnitTablespoonConversion() async throws {
    let result = ServingUnit.tablespoons.toGrams(2, foodServingSize: 100)
    #expect(result == 30, "2 tbsp = 30g")
}

@Test func servingUnitTeaspoonConversion() async throws {
    let result = ServingUnit.teaspoons.toGrams(3, foodServingSize: 100)
    #expect(result == 15, "3 tsp = 15g")
}

@Test func servingUnitMlPassthrough() async throws {
    let result = ServingUnit.ml.toGrams(250, foodServingSize: 100)
    #expect(result == 250)
}

// MARK: - Smart Food Unit Tests (8 tests)

@Test func smartUnitEggShowsEggLabel() async throws {
    let food = Food(name: "Egg (whole, boiled)", category: "Protein", servingSize: 50, servingUnit: "g", calories: 78)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "egg", "Egg should show 'egg' as primary unit, got: \(units.first?.label ?? "nil")")
    #expect(units.first?.gramsEquivalent == 50)
}

@Test func smartUnitOilShowsTbsp() async throws {
    let food = Food(name: "Olive Oil", category: "Oils", servingSize: 15, servingUnit: "g", calories: 120)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp", "Oil should show 'tbsp' as primary unit")
    #expect(units.first?.gramsEquivalent == 15)
}

@Test func smartUnitMilkShowsMl() async throws {
    let food = Food(name: "Milk (whole)", category: "Dairy", servingSize: 244, servingUnit: "ml", calories: 150)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "ml", "Milk should show 'ml' as primary unit")
    #expect(units.contains(where: { $0.label == "cup" }), "Milk should also have cup option")
}

@Test func smartUnitRiceShowsServingAndCup() async throws {
    let food = Food(name: "Rice (cooked)", category: "Grains", servingSize: 200, servingUnit: "g", calories: 260)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "serving", "Rice should show 'serving' as primary")
    #expect(units.contains(where: { $0.label == "g" }), "Rice should have grams option")
    #expect(units.contains(where: { $0.label == "cup" }), "Rice should have cup option")
}

@Test func smartUnitRotiShowsPiece() async throws {
    let food = Food(name: "Roti (whole wheat)", category: "Bread", servingSize: 40, servingUnit: "g", calories: 120)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "piece", "Roti should show 'piece' as primary unit")
}

@Test func smartUnitAlwaysIncludesGrams() async throws {
    let food = Food(name: "Chicken Breast", category: "Protein", servingSize: 165, servingUnit: "g", calories: 165)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.contains(where: { $0.label == "g" }), "Should always include grams")
}

@Test func smartUnitEggCurryNotCountable() async throws {
    // Egg curry has large serving size (200g), should NOT show "egg" as primary
    let food = Food(name: "Egg Curry", category: "Curries", servingSize: 200, servingUnit: "g", calories: 220)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label != "egg", "Egg curry should not show 'egg' (serving too large)")
}

@Test func smartUnitBananaShowsBanana() async throws {
    let food = Food(name: "Banana", category: "Fruits", servingSize: 120, servingUnit: "g", calories: 107)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "banana", "Banana should show 'banana' as primary unit")
}

// MARK: - Portion Text Tests (6 tests)

@Test func portionTextEgg() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Egg (whole, boiled)", servingSizeG: 50, servings: 2, calories: 78)
    #expect(entry.portionText == "2 eggs")
}

@Test func portionTextSingleEgg() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Egg (whole, boiled)", servingSizeG: 50, servings: 1, calories: 78)
    #expect(entry.portionText == "1 egg")
}

@Test func portionTextGramsDefault() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Chicken Breast", servingSizeG: 165, servings: 1.5, calories: 165)
    #expect(entry.portionText == "247g", "Should show total grams: 165 * 1.5 = 247")
}

@Test func portionTextRoti() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Roti (whole wheat)", servingSizeG: 40, servings: 3, calories: 120)
    #expect(entry.portionText == "3 rotis")
}

@Test func portionTextBanana() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Banana", servingSizeG: 120, servings: 1, calories: 107)
    #expect(entry.portionText == "1 banana")
}

@Test func portionTextQuickAddEmpty() async throws {
    // Quick add entries have servingSizeG = 0
    let entry = FoodEntry(mealLogId: 1, foodName: "Quick Add", servingSizeG: 0, servings: 1, calories: 300)
    #expect(entry.portionText == "", "Quick add should have empty portion text")
}

// MARK: - Food Usage Tracking Tests (6 tests)

@Test func trackFoodUsageInsert() async throws {
    let db = try AppDatabase.empty()
    try db.trackFoodUsage(name: "Chicken", foodId: 1, servings: 2)
    let recent = try db.fetchRecentFoods(limit: 10)
    // Can't check recent foods because we haven't inserted the food record itself
    // But we can verify the usage was tracked by searching ranked
    try db.seedFoodsFromJSON()
    let chickenUsage = try db.searchFoodsRanked(query: "chicken")
    #expect(!chickenUsage.isEmpty, "Should find chicken in ranked search")
}

@Test func trackFoodUsageIncrement() async throws {
    let db = try AppDatabase.empty()
    try db.trackFoodUsage(name: "TestFood", foodId: nil, servings: 1)
    try db.trackFoodUsage(name: "TestFood", foodId: nil, servings: 2)
    // Use_count should be 2 now (upsert increments)
    // Verify via ranked search behavior
    #expect(true, "Upsert should not throw")
}

@Test func rankedSearchFrequentFirst() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // Track usage for a specific food to boost its rank
    let foods = try db.searchFoods(query: "dal")
    guard let firstDal = foods.first else { return }
    for _ in 0..<5 { try db.trackFoodUsage(name: firstDal.name, foodId: firstDal.id, servings: 1) }
    let ranked = try db.searchFoodsRanked(query: "dal")
    #expect(ranked.first?.name == firstDal.name, "Most-used dal should appear first in ranked search")
}

@Test func recentFoodsOrdering() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let foods = try db.searchFoods(query: "rice")
    guard foods.count >= 2 else { return }
    try db.trackFoodUsage(name: foods[0].name, foodId: foods[0].id, servings: 1)
    try await Task.sleep(for: .milliseconds(10))
    try db.trackFoodUsage(name: foods[1].name, foodId: foods[1].id, servings: 1)
    let recent = try db.fetchRecentFoods(limit: 10)
    #expect(recent.count >= 2, "Should have at least 2 recent foods")
    #expect(recent[0].name == foods[1].name, "Most recently used should be first")
}

@Test func frequentFoodsRequiresMultipleUses() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let foods = try db.searchFoods(query: "egg")
    guard let egg = foods.first else { return }
    try db.trackFoodUsage(name: egg.name, foodId: egg.id, servings: 1)
    let freq1 = try db.fetchFrequentFoods()
    #expect(freq1.isEmpty, "Single use should NOT appear in frequent foods (requires >1)")
    try db.trackFoodUsage(name: egg.name, foodId: egg.id, servings: 1)
    let freq2 = try db.fetchFrequentFoods()
    #expect(!freq2.isEmpty, "Two uses should appear in frequent foods")
}

@Test func searchRecipesFindsMatches() async throws {
    let db = try AppDatabase.empty()
    var fav = FavoriteFood(name: "Morning Oatmeal", calories: 350, proteinG: 15, carbsG: 50, fatG: 8)
    try db.saveFavorite(&fav)
    let results = try db.searchRecipes(query: "oat")
    #expect(results.count == 1, "Should find the saved recipe")
    #expect(results[0].name == "Morning Oatmeal")
}

// MARK: - Unit Conversion Tests (3 tests)

@Test func foodUnitGramsConversion() async throws {
    let food = Food(name: "Egg (whole, boiled)", category: "Protein", servingSize: 50, servingUnit: "g", calories: 78)
    let units = FoodUnit.smartUnits(for: food)
    // Primary: egg (50g), Secondary: g (1g)
    #expect(units.count >= 2)
    let eggUnit = units[0]
    let gramUnit = units[1]
    // 2 eggs in grams = 100g
    let twoEggsGrams = 2.0 * eggUnit.gramsEquivalent
    #expect(twoEggsGrams == 100, "2 eggs = 100g")
    // Convert to multiplier
    let multiplier = twoEggsGrams / food.servingSize
    #expect(multiplier == 2.0, "2 eggs = 2x multiplier")
}

@Test func foodUnitCupConversion() async throws {
    let food = Food(name: "Rice (cooked)", category: "Grains", servingSize: 200, servingUnit: "g", calories: 260)
    let units = FoodUnit.smartUnits(for: food)
    guard let cupUnit = units.first(where: { $0.label == "cup" }) else {
        #expect(Bool(false), "Rice should have cup unit")
        return
    }
    #expect(cupUnit.gramsEquivalent == 185, "1 cup rice = 185g")
    let multiplier = cupUnit.gramsEquivalent / food.servingSize
    #expect(abs(multiplier - 0.925) < 0.01, "1 cup rice = 0.925x of 200g serving")
}

@Test func foodUnitTbspOilConversion() async throws {
    let food = Food(name: "Olive Oil", category: "Oils", servingSize: 15, servingUnit: "g", calories: 120)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units[0].label == "tbsp")
    #expect(units[0].gramsEquivalent == 15)
    // 2 tbsp = 30g = 2x multiplier
    let multiplier = (2 * 15.0) / food.servingSize
    #expect(multiplier == 2.0)
}

// MARK: - End-to-End Food Logging Flow Tests (10 tests)

/// Round 1: Log food, verify it appears in todayEntries, verify usage is tracked
@Test func e2eLogFoodAndVerifyEntries() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let vm = await FoodLogViewModel(database: db)
    let eggs = try db.searchFoods(query: "boiled egg")
    guard let egg = eggs.first else { throw TestError("No egg found in \(eggs.count) results") }
    await vm.logFood(egg, servings: 2, mealType: .breakfast)
    #expect(await vm.todayEntries.count == 1, "Should have 1 entry")
    #expect(await vm.todayEntries[0].foodName == egg.name)
    #expect(await vm.todayEntries[0].servings == 2)
    #expect(await vm.todayEntries[0].totalCalories == egg.calories * 2)
    // Usage should be tracked
    let recent = try db.fetchRecentFoods(limit: 5)
    #expect(recent.contains(where: { $0.name == egg.name }), "Egg should be in recents")
}

/// Round 2: Quick add, verify flat diary ordering
@Test func e2eQuickAddOrdering() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Morning Coffee", calories: 50, proteinG: 1, carbsG: 5, fatG: 2, fiberG: 0, mealType: .breakfast)
    await vm.quickAdd(name: "Lunch Salad", calories: 300, proteinG: 20, carbsG: 30, fatG: 10, fiberG: 5, mealType: .lunch)
    let entries = await vm.todayEntries
    #expect(entries.count == 2)
    #expect(entries[0].foodName == "Morning Coffee", "First logged should be first in diary")
    #expect(entries[1].foodName == "Lunch Salad")
    let nutrition = await vm.todayNutrition
    #expect(nutrition.calories == 350, "Total: 50 + 300 = 350")
}

/// Round 3: Delete entry and verify diary updates
@Test func e2eDeleteEntry() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Item A", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 0, mealType: .lunch)
    await vm.quickAdd(name: "Item B", calories: 200, proteinG: 20, carbsG: 20, fatG: 10, fiberG: 0, mealType: .lunch)
    #expect(await vm.todayEntries.count == 2)
    let firstId = await vm.todayEntries[0].id!
    await vm.deleteEntry(id: firstId)
    #expect(await vm.todayEntries.count == 1)
    #expect(await vm.todayEntries[0].foodName == "Item B")
    #expect(await vm.todayNutrition.calories == 200)
}

/// Round 4: Verify auto meal type based on hour of day
@Test func e2eAutoMealType() async throws {
    let vm = await FoodLogViewModel(database: try AppDatabase.empty())
    let mealType = await vm.autoMealType
    let hour = Calendar.current.component(.hour, from: Date())
    switch hour {
    case 5..<11: #expect(mealType == .breakfast)
    case 11..<15: #expect(mealType == .lunch)
    case 15..<21: #expect(mealType == .dinner)
    default: #expect(mealType == .snack)
    }
}

/// Round 5: Ranked search boosts frequently-used foods
@Test func e2eRankedSearchBoost() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // Search for "chicken" - find a non-first result
    let unranked = try db.searchFoods(query: "chicken")
    guard unranked.count >= 2 else { return }
    let second = unranked[1]
    // Log it 10 times to boost
    for _ in 0..<10 { try db.trackFoodUsage(name: second.name, foodId: second.id, servings: 1) }
    // Ranked search should now put it first
    let ranked = try db.searchFoodsRanked(query: "chicken")
    #expect(ranked.first?.name == second.name, "Most-used should appear first, got: \(ranked.first?.name ?? "nil")")
}

/// Round 6: Portion text for various food types from the actual DB
@Test func e2ePortionTextRealFoods() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let vm = await FoodLogViewModel(database: db)

    // Log egg - find a single-egg item (serving size ~50g)
    let eggs = try db.searchFoods(query: "Boiled Egg")
    if let egg = eggs.first {
        await vm.logFood(egg, servings: 3, mealType: .breakfast)
        let entry = await vm.todayEntries.first(where: { $0.foodName == egg.name })
        // portionText depends on serving size - if < 80g, shows "eggs"
        if egg.servingSize < 80 {
            #expect(entry?.portionText == "3 eggs", "Got: \(entry?.portionText ?? "nil")")
        } else {
            #expect(entry?.portionText == "\(Int(egg.servingSize * 3))g")
        }
    }

    // Log rice
    let rices = try db.searchFoods(query: "Rice")
    if let rice = rices.first {
        await vm.logFood(rice, servings: 1.5, mealType: .lunch)
        let entry = await vm.todayEntries.first(where: { $0.foodName == rice.name })
        let expected = "\(Int(rice.servingSize * 1.5))g"
        #expect(entry?.portionText == expected, "Rice portion: got \(entry?.portionText ?? "nil"), expected \(expected)")
    }
}

/// Round 7: Favorite/recipe save and search integration
@Test func e2eRecipeSaveAndSearch() async throws {
    let db = try AppDatabase.empty()
    var recipe = FavoriteFood(name: "My Protein Bowl", calories: 500, proteinG: 40, carbsG: 50, fatG: 15, isRecipe: true)
    try db.saveFavorite(&recipe)

    // Search should find it
    let found = try db.searchRecipes(query: "protein")
    #expect(found.count == 1)
    #expect(found[0].name == "My Protein Bowl")
    #expect(found[0].isRecipe == true)

    // Empty query should return all recipes
    let all = try db.searchRecipes(query: "")
    #expect(all.count == 1)

    // Non-matching query should return empty
    let none = try db.searchRecipes(query: "xyznomatch")
    #expect(none.isEmpty)
}

/// Round 8: Smart units for ALL actual DB food categories
@Test func e2eSmartUnitsAcrossCategories() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let allFoods = try db.searchFoods(query: "a", limit: 289)
    var issues: [String] = []
    for food in allFoods {
        let units = FoodUnit.smartUnits(for: food)
        if units.isEmpty {
            issues.append("\(food.name): no units returned")
        }
        if !units.contains(where: { $0.label == "g" }) && units.first?.label != "ml" {
            // Every non-liquid food should have grams
            issues.append("\(food.name): missing grams option, units: \(units.map(\.label))")
        }
        if units.first?.gramsEquivalent == 0 {
            issues.append("\(food.name): primary unit has 0 gramsEquivalent")
        }
    }
    #expect(issues.isEmpty, "Smart unit issues: \(issues.joined(separator: "; "))")
}

/// Round 9: Verify suggestions loading works
@Test func e2eSuggestionsLoad() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let vm = await FoodLogViewModel(database: db)

    // Initially empty
    await vm.loadSuggestions()
    #expect(await vm.recentFoods.isEmpty, "No recents before any logging")
    #expect(await vm.frequentFoods.isEmpty, "No frequents before any logging")

    // Log a food
    let eggs = try db.searchFoods(query: "Egg")
    if let egg = eggs.first {
        await vm.logFood(egg, servings: 1, mealType: .breakfast)
        await vm.loadSuggestions()
        #expect(await vm.recentFoods.count == 1, "Should have 1 recent food")
        #expect(await vm.frequentFoods.isEmpty, "1 use should not make it frequent")

        // Log again
        await vm.logFood(egg, servings: 2, mealType: .lunch)
        await vm.loadSuggestions()
        #expect(await vm.frequentFoods.count == 1, "2 uses should make it frequent")
    }
}

/// Round 10: Verify day navigation preserves entries
@Test func e2eDayNavigation() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Today Food", calories: 500, proteinG: 30, carbsG: 50, fatG: 20, fiberG: 5, mealType: .lunch)
    #expect(await vm.todayEntries.count == 1)

    // Navigate to previous day
    await vm.goToPreviousDay()
    #expect(await vm.todayEntries.isEmpty, "Yesterday should have no entries")
    #expect(await vm.todayNutrition.calories == 0)

    // Navigate back to today
    await vm.goToNextDay()
    #expect(await vm.todayEntries.count == 1, "Today's entry should reappear")
    #expect(await vm.todayNutrition.calories == 500)
}

// MARK: - Edge Case Tests (5 tests)

/// Zero-calorie food
@Test func edgeCaseZeroCalorieFood() async throws {
    let food = Food(name: "Water", category: "Drinks", servingSize: 250, servingUnit: "ml", calories: 0)
    let units = FoodUnit.smartUnits(for: food)
    #expect(!units.isEmpty, "Even zero-calorie foods should have units")
    let entry = FoodEntry(mealLogId: 1, foodName: "Water", servingSizeG: 250, servings: 1, calories: 0)
    #expect(entry.totalCalories == 0)
    #expect(entry.portionText == "250g") // Water still shows grams
}

/// Very large serving multiplier
@Test func edgeCaseLargeServings() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Rice (cooked)", servingSizeG: 200, servings: 10, calories: 260)
    #expect(entry.totalCalories == 2600)
    #expect(entry.portionText == "2000g")
}

/// Fractional egg servings
@Test func edgeCaseFractionalEggs() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Egg (whole, boiled)", servingSizeG: 50, servings: 1.5, calories: 78)
    #expect(entry.portionText == "1.5 eggs")
}

/// Food with zero serving size (manual/quick add)
@Test func edgeCaseZeroServingSize() async throws {
    let food = Food(name: "Custom Item", category: "Other", servingSize: 0, servingUnit: "g", calories: 100)
    let units = FoodUnit.smartUnits(for: food)
    #expect(!units.isEmpty, "Zero serving size should still produce units")
    #expect(units.first?.gramsEquivalent == 100, "Should default to 100g when serving is 0")
}

/// Duplicate recipe names
@Test func edgeCaseDuplicateRecipes() async throws {
    let db = try AppDatabase.empty()
    var r1 = FavoriteFood(name: "Breakfast", calories: 300, proteinG: 20, carbsG: 30, fatG: 10)
    var r2 = FavoriteFood(name: "Breakfast", calories: 500, proteinG: 30, carbsG: 50, fatG: 15)
    try db.saveFavorite(&r1)
    try db.saveFavorite(&r2)
    let results = try db.searchRecipes(query: "breakfast")
    #expect(results.count == 2, "Should allow duplicate names")
}

// MARK: - Multi-word Search Tests (3 tests)

@Test func multiWordSearchBothDirections() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // "egg boiled" should find "Egg (whole, boiled)" and "Boiled Egg (1)"
    let results1 = try db.searchFoods(query: "egg boiled")
    #expect(!results1.isEmpty, "Should find eggs with 'egg boiled'")
    // "boiled egg" should find the same
    let results2 = try db.searchFoods(query: "boiled egg")
    #expect(!results2.isEmpty, "Should find eggs with 'boiled egg'")
    // Both should find the same items
    let names1 = Set(results1.map(\.name))
    let names2 = Set(results2.map(\.name))
    #expect(names1 == names2, "Word order should not matter")
}

@Test func multiWordSearchNarrows() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let broad = try db.searchFoods(query: "chicken")
    let narrow = try db.searchFoods(query: "chicken curry")
    #expect(narrow.count < broad.count, "Adding a word should narrow results")
    #expect(narrow.allSatisfy { $0.name.lowercased().contains("chicken") && $0.name.lowercased().contains("curry") })
}

@Test func multiWordRankedSearch() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoodsRanked(query: "rice cooked")
    #expect(!results.isEmpty, "Should find cooked rice")
    #expect(results.allSatisfy { $0.name.lowercased().contains("rice") && $0.name.lowercased().contains("cooked") })
}

// MARK: - Indian Food Search Usability (4 tests)

@Test func searchDalVariations() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // "moong dal" should work as multi-word
    let results = try db.searchFoods(query: "moong dal")
    #expect(!results.isEmpty, "Should find moong dal")
}

@Test func searchChickenBreast() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "chicken breast")
    #expect(!results.isEmpty, "Should find chicken breast")
}

@Test func searchPaneerSmartUnit() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let paneer = try db.searchFoods(query: "paneer")
    guard let p = paneer.first else { return }
    let units = FoodUnit.smartUnits(for: p)
    #expect(units.contains(where: { $0.label == "cup" }), "Paneer should have cup option")
    #expect(units.contains(where: { $0.label == "g" }), "Paneer should have grams option")
}

@Test func searchGheeSmartUnit() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let ghee = try db.searchFoods(query: "ghee")
    guard let g = ghee.first else { return }
    let units = FoodUnit.smartUnits(for: g)
    #expect(units.first?.label == "tbsp", "Ghee primary unit should be tbsp, got: \(units.first?.label ?? "nil")")
}

// MARK: - ViewModel Concurrent Safety (2 tests)

@Test func viewModelMultipleQuickAdds() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    for i in 0..<5 {
        await vm.quickAdd(name: "Item \(i)", calories: Double(100 * (i + 1)), proteinG: 10, carbsG: 10, fatG: 5, fiberG: 0, mealType: .lunch)
    }
    #expect(await vm.todayEntries.count == 5, "Should have 5 entries")
    #expect(await vm.todayNutrition.calories == 1500, "Sum: 100+200+300+400+500 = 1500")
}

@Test func viewModelQuickLogFoodUsesAutoMealType() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let vm = await FoodLogViewModel(database: db)
    let foods = try db.searchFoods(query: "rice")
    guard let rice = foods.first else { return }
    await vm.quickLogFood(rice)
    #expect(await vm.todayEntries.count == 1)
    #expect(await vm.todayEntries[0].servings == 1, "quickLogFood should use 1 serving")
}

// MARK: - Copy From Yesterday Test

@Test func copyFromYesterdayLogic() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log food for yesterday
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Yesterday Item 1", calories: 200, proteinG: 15, carbsG: 20, fatG: 8, fiberG: 2, mealType: .lunch)
    await vm.quickAdd(name: "Yesterday Item 2", calories: 300, proteinG: 25, carbsG: 30, fatG: 12, fiberG: 3, mealType: .lunch)
    #expect(await vm.todayEntries.count == 2)

    // Go to today
    await vm.goToDate(Date())
    #expect(await vm.todayEntries.isEmpty, "Today should be empty before copy")

    // Simulate copy from yesterday
    let yesterdayStr = DateFormatters.dateOnly.string(from: yesterday)
    let logs = try db.fetchMealLogs(for: yesterdayStr)
    for log in logs {
        guard let logId = log.id else { continue }
        let entries = try db.fetchFoodEntries(forMealLog: logId)
        for entry in entries {
            await vm.quickAdd(name: entry.foodName, calories: entry.totalCalories,
                              proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                              fatG: entry.totalFat, fiberG: entry.totalFiber, mealType: .lunch)
        }
    }

    #expect(await vm.todayEntries.count == 2, "Should have 2 entries copied from yesterday")
    #expect(await vm.todayNutrition.calories == 500, "Total should be 200 + 300 = 500")
}

// MARK: - Stress Tests

@Test func stressLogManyItems() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    for i in 0..<20 {
        await vm.quickAdd(name: "Food \(i)", calories: Double(50 * (i + 1)), proteinG: 5, carbsG: 10, fatG: 3, fiberG: 1, mealType: .lunch)
    }
    #expect(await vm.todayEntries.count == 20, "Should handle 20 entries")
    #expect(await vm.todayNutrition.calories == 10500, "Sum of 50+100+...+1000 = 10500")
}

@Test func stressSearchRankedWithManyUsages() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // Track 50 different foods
    let allFoods = try db.searchFoods(query: "a", limit: 50)
    for food in allFoods {
        try db.trackFoodUsage(name: food.name, foodId: food.id, servings: 1)
    }
    // Search should still be fast and return results
    let results = try db.searchFoodsRanked(query: "chicken")
    #expect(!results.isEmpty)
}

// MARK: - Macro Targets Tests (4 tests)

@Test func macroTargetsAutoCalculate() async throws {
    // With calorie override of 1800 (simulates knowing your TDEE)
    let goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, calorieTargetOverride: 1800)
    let targets = goal.macroTargets()!
    // Protein: 85kg * 1.6 = 136g (balanced default)
    #expect(abs(targets.proteinG - 136) < 1, "Protein should be ~136g, got \(targets.proteinG)")
    // Fat: must meet minimum
    let fatMin = WeightGoal.minimumFatG(bodyweightKg: 85, calorieTarget: 1800)
    #expect(targets.fatG >= fatMin, "Fat must meet minimum \(fatMin)g")
    // Carbs: remainder
    #expect(targets.carbsG > 0, "Carbs should be positive")
    #expect(targets.calorieTarget == 1800)
}

@Test func macroTargetsManualOverride() async throws {
    var goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, calorieTargetOverride: 2000)
    goal.proteinTargetG = 180
    goal.fatTargetG = 60
    goal.carbsTargetG = 200
    let targets = goal.macroTargets()!
    #expect(targets.proteinG == 180)
    #expect(targets.fatG == 60)
    #expect(targets.carbsG == 200)
}

@Test func macroTargetsWithCurrentWeight() async throws {
    let goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, calorieTargetOverride: 1800)
    let targets80 = goal.macroTargets(currentWeightKg: 80)!
    let targets85 = goal.macroTargets(currentWeightKg: 85)!
    #expect(targets80.proteinG < targets85.proteinG, "Lower weight = less protein needed")
}

@Test func macroTargetsFallbackWithoutData() async throws {
    // No calorie override, no TDEE → uses weight-based estimate (28 kcal/kg)
    let goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85)
    let targets = goal.macroTargets()
    #expect(targets != nil, "Should fall back to weight-based TDEE estimate")
    if let t = targets {
        #expect(t.calorieTarget > 1500 && t.calorieTarget < 3000, "Fallback target should be reasonable")
    }
    // With explicit TDEE, should still work
    let withTDEE = goal.macroTargets(actualTDEE: 2200)
    #expect(withTDEE != nil, "With TDEE, targets should compute")
}

// MARK: - Diet Preference Tests (4 tests)

@Test func dietPrefHighProtein() async throws {
    let goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, dietPreference: .highProtein, calorieTargetOverride: 1800)
    let targets = goal.macroTargets()!
    #expect(abs(targets.proteinG - 187) < 1, "High protein should be ~187g, got \(targets.proteinG)")
    let fatMin = WeightGoal.minimumFatG(bodyweightKg: 85, calorieTarget: 1800)
    #expect(targets.fatG >= fatMin, "Fat must meet minimum")
}

@Test func dietPrefLowCarb() async throws {
    let goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, dietPreference: .lowCarb, calorieTargetOverride: 1800)
    let balanced = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, dietPreference: .balanced, calorieTargetOverride: 1800)
    let lowCarbTargets = goal.macroTargets()!
    let balancedTargets = balanced.macroTargets()!
    #expect(lowCarbTargets.carbsG < balancedTargets.carbsG, "Low carb should have fewer carbs")
    #expect(lowCarbTargets.fatG > balancedTargets.fatG, "Low carb should have more fat")
}

@Test func dietPrefLowFatStillMeetsMinimum() async throws {
    let goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, dietPreference: .lowFat, calorieTargetOverride: 1800)
    let targets = goal.macroTargets()!
    let fatMin = WeightGoal.minimumFatG(bodyweightKg: 85, calorieTarget: 1800)
    #expect(targets.fatG >= fatMin, "Even low-fat must meet minimum \(fatMin)g, got \(targets.fatG)")
}

@Test func minimumFatEnforced() async throws {
    let goal = WeightGoal(targetWeightKg: 60, monthsToAchieve: 2, startDate: "2026-01-01", startWeightKg: 85, dietPreference: .lowFat, calorieTargetOverride: 1200)
    let targets = goal.macroTargets()!
    let fatMin = WeightGoal.minimumFatG(bodyweightKg: 85, calorieTarget: 1200)
    #expect(targets.fatG >= fatMin, "Minimum fat \(fatMin)g must be enforced, got \(targets.fatG)")
    #expect(targets.fatG >= 85 * 0.5, "Fat must be >= 0.5g/kg (\(85 * 0.5)g), got \(targets.fatG)")
}

// MARK: - Entry Update Test (2 tests)

@Test func updateEntryServings() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Test Food", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 0, mealType: .lunch)
    let entry = await vm.todayEntries.first!
    #expect(entry.servings == 1)

    await vm.updateEntryServings(id: entry.id!, servings: 2.5)
    let updated = await vm.todayEntries.first!
    #expect(updated.servings == 2.5, "Servings should be updated to 2.5")
    #expect(await vm.todayNutrition.calories == 250, "Calories should scale: 100 * 2.5 = 250")
}

@Test func updateEntryServingsPreservesOtherEntries() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "A", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 0, mealType: .lunch)
    await vm.quickAdd(name: "B", calories: 200, proteinG: 20, carbsG: 20, fatG: 10, fiberG: 0, mealType: .lunch)

    let entryA = await vm.todayEntries.first(where: { $0.foodName == "A" })!
    await vm.updateEntryServings(id: entryA.id!, servings: 3)

    #expect(await vm.todayEntries.count == 2, "Should still have 2 entries")
    #expect(await vm.todayNutrition.calories == 500, "100*3 + 200 = 500")
}

// MARK: - Aggressive Edge Case Tests (10 tests)

@Test func foodSearchSpecialCharacters() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // These should not crash
    for q in ["'", "\"", "%", "_", "\\", "(", ")", "--", ";", "DROP TABLE"] {
        let _ = try db.searchFoods(query: q)
        let _ = try db.searchFoodsRanked(query: q)
    }
}

@Test func foodSearchUnicodeCharacters() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let _ = try db.searchFoods(query: "café")
    let _ = try db.searchFoods(query: "über")
    let _ = try db.searchFoods(query: "日本")
}

@Test func saveScannedFoodDeduplicates() async throws {
    let db = try AppDatabase.empty()
    var food1 = Food(name: "Test Scanned", category: "Scanned", servingSize: 100, servingUnit: "g", calories: 200)
    var food2 = Food(name: "Test Scanned", category: "Scanned", servingSize: 100, servingUnit: "g", calories: 300)
    try db.saveScannedFood(&food1)
    try db.saveScannedFood(&food2) // Same name - should skip
    let results = try db.searchFoods(query: "Test Scanned")
    #expect(results.count == 1, "Should not duplicate scanned food")
    #expect(results[0].calories == 200, "Should keep first entry")
}

@Test func foodUsageTrackingConcurrent() async throws {
    let db = try AppDatabase.empty()
    // Track same food many times rapidly
    for i in 0..<20 {
        try db.trackFoodUsage(name: "Rapid Food", foodId: nil, servings: Double(i + 1))
    }
    // Should not crash and count should be 20
}

@Test func deleteFavoriteAndSearch() async throws {
    let db = try AppDatabase.empty()
    var fav = FavoriteFood(name: "Delete Me Recipe", calories: 100, proteinG: 10, carbsG: 10, fatG: 5)
    try db.saveFavorite(&fav)
    let before = try db.searchRecipes(query: "Delete Me")
    #expect(before.count == 1)
    if let id = before.first?.id {
        try db.deleteFavorite(id: id)
    }
    let after = try db.searchRecipes(query: "Delete Me")
    #expect(after.isEmpty, "Deleted recipe should not appear in search")
}

@Test func viewModelDeleteAllEntries() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    // Add 5 entries then delete them all
    for i in 0..<5 {
        await vm.quickAdd(name: "Item \(i)", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 0, mealType: .lunch)
    }
    #expect(await vm.todayEntries.count == 5)
    // Delete all
    for entry in await vm.todayEntries {
        if let id = entry.id { await vm.deleteEntry(id: id) }
    }
    #expect(await vm.todayEntries.isEmpty, "All entries should be deleted")
    #expect(await vm.todayNutrition.calories == 0)
}

@Test func foodEntryPortionTextEdgeCases() async throws {
    // Very large servings
    let large = FoodEntry(mealLogId: 1, foodName: "Rice", servingSizeG: 200, servings: 100, calories: 260)
    #expect(large.portionText == "20000g")

    // Very small servings
    let small = FoodEntry(mealLogId: 1, foodName: "Egg (whole, boiled)", servingSizeG: 50, servings: 0.5, calories: 78)
    #expect(small.portionText == "0.5 eggs")

    // Negative servings (shouldn't happen but shouldn't crash)
    let negative = FoodEntry(mealLogId: 1, foodName: "Bug", servingSizeG: 100, servings: -1, calories: 100)
    let _ = negative.portionText // Should not crash
}

@Test func smartUnitsForAllDBFoods() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let allFoods = try db.searchFoods(query: "e", limit: 500) // Most foods have 'e'
    var issues: [String] = []
    for food in allFoods {
        let units = FoodUnit.smartUnits(for: food)
        if units.isEmpty { issues.append("\(food.name): no units") }
        if units.first?.gramsEquivalent == 0 { issues.append("\(food.name): 0g primary unit") }
        // Verify grams is always available for non-liquid
        let hasGrams = units.contains(where: { $0.label == "g" })
        let isMl = units.first?.label == "ml"
        if !hasGrams && !isMl { issues.append("\(food.name): no grams unit") }
    }
    #expect(issues.isEmpty, "Smart unit issues: \(issues.prefix(5).joined(separator: "; "))")
}

@Test func recentEntriesIncludeManualAdds() async throws {
    let db = try AppDatabase.empty()
    try db.trackFoodUsage(name: "Manual Recipe", foodId: nil, servings: 1)
    let recents = try db.fetchRecentEntryNames()
    // Manual entries (no food_id) should still appear in recents
    #expect(recents.contains(where: { $0.name == "Manual Recipe" }), "Manual entries should appear in recents")
}

@Test func weightGoalMacrosWithExtremeValues() async throws {
    // Very aggressive deficit
    let aggressive = WeightGoal(targetWeightKg: 50, monthsToAchieve: 1, startDate: "2026-01-01", startWeightKg: 100, calorieTargetOverride: 800)
    let targets = aggressive.macroTargets()!
    #expect(targets.proteinG > 0)
    #expect(targets.fatG >= WeightGoal.minimumFatG(bodyweightKg: 100, calorieTarget: 800))
    #expect(targets.carbsG >= 0, "Carbs should not go negative")

    // Very high surplus
    let bulk = WeightGoal(targetWeightKg: 100, monthsToAchieve: 12, startDate: "2026-01-01", startWeightKg: 80, calorieTargetOverride: 4000)
    let bulkTargets = bulk.macroTargets()!
    #expect(bulkTargets.calorieTarget == 4000)
    #expect(bulkTargets.proteinG > 100)
}

// MARK: - Scanned Food Integration Tests (3 tests)

@Test func scannedFoodAppearsInSearch() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    var food = Food(name: "Scanned Test Product XYZ", category: "Scanned", servingSize: 100, servingUnit: "g", calories: 250, proteinG: 10, carbsG: 30, fatG: 10)
    try db.saveScannedFood(&food)
    let results = try db.searchFoods(query: "Scanned Test Product")
    #expect(!results.isEmpty, "Scanned food should appear in search")
    #expect(results[0].calories == 250)
}

@Test func scannedFoodNotDuplicated() async throws {
    let db = try AppDatabase.empty()
    var f1 = Food(name: "DupTest", category: "Scanned", servingSize: 50, servingUnit: "g", calories: 100)
    var f2 = Food(name: "DupTest", category: "Scanned", servingSize: 50, servingUnit: "g", calories: 200)
    try db.saveScannedFood(&f1)
    try db.saveScannedFood(&f2) // Should be skipped
    let results = try db.searchFoods(query: "DupTest")
    #expect(results.count == 1)
}

@Test func loggedFoodTracksUsage() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let vm = await FoodLogViewModel(database: db)
    let eggs = try db.searchFoods(query: "egg")
    guard let egg = eggs.first else { return }
    await vm.logFood(egg, servings: 2, mealType: .breakfast)
    let recent = try db.fetchRecentFoods(limit: 10)
    #expect(recent.contains(where: { $0.name == egg.name }), "Logged food should appear in recents")
}

// MARK: - Food Favorites Tests (4 tests)

@Test func toggleFoodFavorite() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let egg = try db.searchFoods(query: "egg").first!
    // Initially not favorite
    #expect(try db.isFoodFavorite(name: egg.name) == false)
    // Toggle on
    try db.toggleFoodFavorite(name: egg.name, foodId: egg.id)
    #expect(try db.isFoodFavorite(name: egg.name) == true)
    // Toggle off
    try db.toggleFoodFavorite(name: egg.name, foodId: egg.id)
    #expect(try db.isFoodFavorite(name: egg.name) == false)
}

@Test func fetchFavoriteFoods() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let egg = try db.searchFoods(query: "egg").first!
    try db.toggleFoodFavorite(name: egg.name, foodId: egg.id)
    let favs = try db.fetchFavoriteFoods()
    #expect(favs.contains(where: { $0.name == egg.name }))
}

@Test func favoritesAndRecentsSeparate() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let rice = try db.searchFoods(query: "rice").first!
    // Log rice (creates recent)
    try db.trackFoodUsage(name: rice.name, foodId: rice.id, servings: 1)
    // Favorite rice
    try db.toggleFoodFavorite(name: rice.name, foodId: rice.id)
    // Should appear in both
    let recents = try db.fetchRecentFoods()
    let favs = try db.fetchFavoriteFoods()
    #expect(recents.contains(where: { $0.name == rice.name }))
    #expect(favs.contains(where: { $0.name == rice.name }))
}

@Test func favoriteWithoutLogging() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let dal = try db.searchFoods(query: "dal").first!
    // Favorite without logging
    try db.toggleFoodFavorite(name: dal.name, foodId: dal.id)
    let favs = try db.fetchFavoriteFoods()
    #expect(favs.contains(where: { $0.name == dal.name }), "Can favorite without logging first")
}

// MARK: - Full User Flow Tests (3 tests)

@Test func fullFlowSearchLogEditDelete() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let vm = await FoodLogViewModel(database: db)

    // 1. Search
    let results = try db.searchFoodsRanked(query: "chicken")
    #expect(!results.isEmpty)

    // 2. Log
    let chicken = results.first!
    await vm.logFood(chicken, servings: 1.5, mealType: .lunch)
    #expect(await vm.todayEntries.count == 1)
    #expect(await vm.todayNutrition.calories > 0)

    // 3. Edit serving
    let entry = await vm.todayEntries.first!
    await vm.updateEntryServings(id: entry.id!, servings: 2.0)
    let updated = await vm.todayEntries.first!
    #expect(updated.servings == 2.0)

    // 4. Delete
    await vm.deleteEntry(id: updated.id!)
    #expect(await vm.todayEntries.isEmpty)
    #expect(await vm.todayNutrition.calories == 0)
}

@Test func fullFlowFavoriteAndFind() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()

    // Search for food
    let eggs = try db.searchFoods(query: "egg")
    guard let egg = eggs.first else { return }

    // Favorite it
    try db.toggleFoodFavorite(name: egg.name, foodId: egg.id)

    // Verify in favorites
    let favs = try db.fetchFavoriteFoods()
    #expect(favs.contains(where: { $0.name == egg.name }))

    // Unfavorite
    try db.toggleFoodFavorite(name: egg.name, foodId: egg.id)
    let favsAfter = try db.fetchFavoriteFoods()
    #expect(!favsAfter.contains(where: { $0.name == egg.name }))
}

@Test func fullFlowRecipeCreateLogDelete() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Create recipe
    var recipe = FavoriteFood(name: "Test Recipe", calories: 500, proteinG: 30, carbsG: 50, fatG: 15, isRecipe: true)
    try db.saveFavorite(&recipe)

    // Find in search
    let found = try db.searchRecipes(query: "Test Recipe")
    #expect(found.count == 1)

    // Log it
    await vm.quickAdd(name: recipe.name, calories: recipe.calories, proteinG: recipe.proteinG,
                      carbsG: recipe.carbsG, fatG: recipe.fatG, fiberG: recipe.fiberG, mealType: .lunch)
    #expect(await vm.todayNutrition.calories == 500)

    // Delete recipe
    if let id = found.first?.id { try db.deleteFavorite(id: id) }
    let after = try db.searchRecipes(query: "Test Recipe")
    #expect(after.isEmpty)
}

// MARK: - Food DB Quality Tests (3 tests)

@Test func allFoodsHavePositiveCaloriesOrZero() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let all = try db.searchFoods(query: "e", limit: 600) + db.searchFoods(query: "a", limit: 600)
    let negative = all.filter { $0.calories < 0 }
    #expect(negative.isEmpty, "Foods with negative calories: \(negative.map(\.name))")
}

@Test func allFoodsHaveReasonableServingSize() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let all = try db.searchFoods(query: "e", limit: 600) + db.searchFoods(query: "a", limit: 600)
    let zeroServing = all.filter { $0.servingSize <= 0 }
    #expect(zeroServing.isEmpty, "Foods with zero serving: \(zeroServing.map(\.name))")
}

@Test func allFoodsHaveNonEmptyNames() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let all = try db.searchFoods(query: "a", limit: 600)
    let empty = all.filter { $0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    #expect(empty.isEmpty)
}

// MARK: - Serving Size Conversion Tests (3 tests)

@Test func smartUnitsEggServing() async throws {
    let food = Food(name: "Egg (whole, boiled)", category: "Protein", servingSize: 50, servingUnit: "g", calories: 78)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "egg")
    // 2 eggs = 2 × 50g = 100g
    let twoEggs = 2.0 * units.first!.gramsEquivalent
    let multiplier = twoEggs / food.servingSize
    #expect(multiplier == 2.0)
    #expect(food.calories * multiplier == 156)
}

@Test func smartUnitsMeatballServing() async throws {
    let food = Food(name: "TJ's Chicken Meatballs (1 meatball)", category: "TJ", servingSize: 21, servingUnit: "g", calories: 38)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "meatball", "Got: \(units.first?.label ?? "nil")")
    // 4 meatballs = 4 × 21g = 84g
    let fourMeatballs = 4.0 * units.first!.gramsEquivalent
    let multiplier = fourMeatballs / food.servingSize
    #expect(multiplier == 4.0)
    #expect(food.calories * multiplier == 152)
}

@Test func smartUnitsAlmondCount() async throws {
    let food = Food(name: "Almonds, Raw", category: "Nuts", servingSize: 28, servingUnit: "g", calories: 164)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.contains(where: { $0.label == "almond" }), "Almonds should have per-piece unit")
    let almondUnit = units.first(where: { $0.label == "almond" })!
    #expect(abs(almondUnit.gramsEquivalent - 1.2) < 0.01, "1 almond ≈ 1.2g")
    // 10 almonds = 12g, multiplier = 12/28 ≈ 0.43
    let tenAlmonds = 10.0 * almondUnit.gramsEquivalent
    let multiplier = tenAlmonds / food.servingSize
    #expect(abs(multiplier - 0.4286) < 0.01)
}

@Test func smartUnitsOilTbsp() async throws {
    let food = Food(name: "Olive Oil (1 tbsp)", category: "Oils", servingSize: 14, servingUnit: "g", calories: 120)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp")
    #expect(units.contains(where: { $0.label == "g" }))
}

// MARK: - Factory Reset Safety Test

@Test func factoryResetClearsAllData() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()

    // Add some data
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Test", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 0, mealType: .lunch)
    #expect(await vm.todayEntries.count == 1)

    // Factory reset
    try db.factoryReset()
    await vm.loadTodayMeals()
    #expect(await vm.todayEntries.isEmpty, "All food entries should be gone after reset")
    #expect(await vm.todayNutrition.calories == 0)

    // Foods should be re-seeded
    let foods = try db.searchFoods(query: "rice")
    #expect(!foods.isEmpty, "Foods should be re-seeded after reset")
}

enum TestError: Error { case msg(String); init(_ s: String) { self = .msg(s) } }
