import Foundation
import Testing
@testable import Drift

// MARK: - FoodService.editMealEntry Tests
// Seeds AppDatabase.shared with today's meal logs, exercises edit paths,
// cleans up via MealLog cascade.

@MainActor
@discardableResult
private func seedTodayMeal(
    mealType: String,
    foodName: String,
    servingSizeG: Double = 100,
    servings: Double = 1,
    calories: Double = 200,
    proteinG: Double = 10
) -> Int64? {
    let today = DateFormatters.todayString
    var mealLog = MealLog(date: today, mealType: mealType)
    try? AppDatabase.shared.saveMealLog(&mealLog)
    guard let mlId = mealLog.id else { return nil }
    var entry = FoodEntry(
        mealLogId: mlId, foodName: foodName,
        servingSizeG: servingSizeG, servings: servings,
        calories: calories, proteinG: proteinG,
        loggedAt: ISO8601DateFormatter().string(from: Date()),
        date: today, mealType: mealType
    )
    try? AppDatabase.shared.saveFoodEntry(&entry)
    return mlId
}

@MainActor
private func cleanupMeal(_ id: Int64?) {
    guard let id else { return }
    try? AppDatabase.shared.deleteMealLog(id: id)
}

// MARK: Remove

@Test @MainActor func editMealRemoveFromSpecificMeal() {
    let mlId = seedTodayMeal(mealType: "lunch", foodName: "TestRice4Edit", calories: 260)
    defer { cleanupMeal(mlId) }

    let result = FoodService.editMealEntry(
        mealPeriod: "lunch", targetFood: "TestRice4Edit",
        action: "remove", newValue: nil
    )
    #expect(result.contains("Removed"))
    #expect(result.contains("lunch"))
}

// MARK: Update Quantity

@Test @MainActor func editMealUpdateServings() {
    let mlId = seedTodayMeal(mealType: "dinner", foodName: "TestChicken4Edit", servings: 1)
    defer { cleanupMeal(mlId) }

    let result = FoodService.editMealEntry(
        mealPeriod: "dinner", targetFood: "TestChicken4Edit",
        action: "update_quantity", newValue: "2"
    )
    #expect(result.contains("Updated"))
    #expect(result.contains("2 servings"))
}

@Test @MainActor func editMealUpdateGramsConvertsToServings() {
    // 200g entry seeded — change to 400g should become servings = 2
    let mlId = seedTodayMeal(mealType: "breakfast", foodName: "TestOats4Edit", servingSizeG: 200, servings: 1)
    defer { cleanupMeal(mlId) }

    let result = FoodService.editMealEntry(
        mealPeriod: "breakfast", targetFood: "TestOats4Edit",
        action: "update_quantity", newValue: "400g"
    )
    #expect(result.contains("Updated"))
    #expect(result.contains("2 servings"))
}

// MARK: Errors

@Test @MainActor func editMealFoodNotFound() {
    // No need to seed — searching for something that doesn't exist
    let result = FoodService.editMealEntry(
        mealPeriod: "lunch", targetFood: "xyzzy_does_not_exist_9999",
        action: "remove", newValue: nil
    )
    // Covers all "not found" paths regardless of concurrent test state:
    // empty DB → "No food logged today."
    // no lunch entries → "No lunch logged today." / "No entries found in lunch."
    // lunch exists but no match → "Couldn't find 'xyzzy...' in lunch."
    #expect(result.contains("No food") || result.contains("No lunch") || result.contains("Couldn't find") || result.contains("No entries found"))
}

@Test @MainActor func editMealUpdateMissingNewValue() {
    let mlId = seedTodayMeal(mealType: "snack", foodName: "TestSnack4Edit")
    defer { cleanupMeal(mlId) }

    let result = FoodService.editMealEntry(
        mealPeriod: "snack", targetFood: "TestSnack4Edit",
        action: "update_quantity", newValue: nil
    )
    #expect(result.contains("Missing") || result.contains("quantity"))
}

// MARK: Replace

/// Helper — seeds a unique food in the local DB so replace lookup has a hit.
@MainActor
@discardableResult
private func seedFoodDB(name: String, calories: Double = 120, proteinG: Double = 4) -> Int64? {
    var food = Food(
        name: name, category: "grain",
        servingSize: 100, servingUnit: "g",
        calories: calories, proteinG: proteinG, carbsG: 22, fatG: 2, fiberG: 3,
        source: "scanned"
    )
    return FoodService.saveScannedFood(&food)?.id
}

@Test @MainActor func editMealReplaceFoundInDB() {
    // Seed replacement in DB (unique token so searchFood matches it).
    let replacementId = seedFoodDB(name: "TestQuinoaReplace9876", calories: 222, proteinG: 8)
    defer { if let id = replacementId { FoodService.deleteScannedFood(id: id, name: "TestQuinoaReplace9876") } }

    let mlId = seedTodayMeal(mealType: "lunch", foodName: "TestRice4Replace", calories: 260, proteinG: 5)
    defer { cleanupMeal(mlId) }

    let result = FoodService.editMealEntry(
        mealPeriod: "lunch", targetFood: "TestRice4Replace",
        action: "replace", newValue: "TestQuinoaReplace9876"
    )
    #expect(result.contains("Replaced"))
    #expect(result.contains("TestQuinoaReplace9876"))
    #expect(result.contains("lunch"))
}

@Test @MainActor func editMealReplaceNotFoundInDB() {
    let mlId = seedTodayMeal(mealType: "breakfast", foodName: "TestOats4ReplaceMiss")
    defer { cleanupMeal(mlId) }

    let result = FoodService.editMealEntry(
        mealPeriod: "breakfast", targetFood: "TestOats4ReplaceMiss",
        action: "replace", newValue: "zzznonexistent_food_for_test_12345"
    )
    #expect(result.contains("Couldn't find") || result.contains("manually"))
}

@Test @MainActor func editMealReplaceMissingNewValue() {
    let mlId = seedTodayMeal(mealType: "dinner", foodName: "TestDinnerFor4Replace")
    defer { cleanupMeal(mlId) }

    let result = FoodService.editMealEntry(
        mealPeriod: "dinner", targetFood: "TestDinnerFor4Replace",
        action: "replace", newValue: nil
    )
    #expect(result.contains("Missing replacement"))
}

// MARK: Cross-Cutting Edge Cases

@Test @MainActor func editMealCaseInsensitiveMatch() {
    let mlId = seedTodayMeal(mealType: "lunch", foodName: "TestMixedCaseItem")
    defer { cleanupMeal(mlId) }

    // Query in lowercase — match should still succeed.
    let result = FoodService.editMealEntry(
        mealPeriod: "lunch", targetFood: "testmixedcaseitem",
        action: "remove", newValue: nil
    )
    #expect(result.contains("Removed"))
}

@Test @MainActor func editMealUnknownAction() {
    let mlId = seedTodayMeal(mealType: "lunch", foodName: "TestUnknownActionFood")
    defer { cleanupMeal(mlId) }

    let result = FoodService.editMealEntry(
        mealPeriod: "lunch", targetFood: "TestUnknownActionFood",
        action: "teleport", newValue: nil
    )
    #expect(result.contains("Unknown edit action"))
}

@Test @MainActor func editMealNoMealLoggedYet() {
    // Do NOT seed — asking for an empty day.
    let result = FoodService.editMealEntry(
        mealPeriod: "lunch", targetFood: "anything",
        action: "remove", newValue: nil
    )
    #expect(result.contains("No food") || result.contains("No lunch") || result.contains("Couldn't find") || result.contains("No entries found"))
}
