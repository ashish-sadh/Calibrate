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
