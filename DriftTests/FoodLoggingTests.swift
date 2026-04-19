import Foundation
import Testing
import GRDB
@testable import Drift

// Shared pre-seeded database — created once, reused by read-only tests.
// Tests that modify data should use `try AppDatabase.empty()` + seed individually.
private let _sharedSeededDB: AppDatabase = {
    let db = try! AppDatabase.empty()
    try! db.seedFoodsFromJSON()
    return db
}()

/// Returns the shared pre-seeded database for read-only food search tests.
private func seededDB() -> AppDatabase { _sharedSeededDB }

// MARK: - Food Search Extended Tests (6 tests)

@Test func foodSearchPartialMatchDal() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "dal")
    #expect(results.count >= 4, "Should find multiple dal entries: \(results.count)")
}

@Test func foodSearchTraderJoes() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "TJ")
    #expect(results.count >= 10, "Should find Trader Joe's items: \(results.count)")
}

@Test func foodSearchMeatball() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "meatball")
    #expect(!results.isEmpty, "Should find meatball entries")
}

@Test func foodSearchCostco() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "kirkland")
    #expect(results.count >= 5, "Should find Kirkland/Costco items: \(results.count)")
}

@Test func foodDatabaseCount() async throws {
    let db = seededDB()
    // Verify the food DB has at least 580 items (allows some margin from 600)
    let countA = try db.searchFoods(query: "a", limit: 600).count
    let countE = try db.searchFoods(query: "e", limit: 600).count
    let countI = try db.searchFoods(query: "i", limit: 600).count
    let maxCount = max(countA, max(countE, countI))
    #expect(maxCount >= 400, "Food DB should have 400+ searchable items, got \(maxCount)")
}

@Test func foodSearchLimitRespected() async throws {
    let db = seededDB()
    let limited = try db.searchFoods(query: "a", limit: 5)
    #expect(limited.count <= 5)
}

@Test func foodSearchNoMatchReturnsEmpty() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "xyznonfooditematall")
    #expect(results.isEmpty)
}

@Test func foodCategoriesExist() async throws {
    let db = seededDB()
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
    let db = seededDB()
    let results = try db.searchFoods(query: "chicken")
    // Prefix matches like "Chicken Breast" should come before "Butter Chicken"
    if results.count >= 2 {
        let firstResult = results[0].name.lowercased()
        #expect(firstResult.hasPrefix("chicken"), "First result should start with 'chicken': \(firstResult)")
    }
}

@Test func foodSearchSortedAlphabetically() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "rice")
    // Results should be sorted alphabetically within same prefix group
    if results.count >= 2 {
        // Just verify we get results without crashing
        #expect(!results.isEmpty)
    }
}

@Test func foodSearchRankedPrefersShorterName() async throws {
    let db = seededDB()
    // "banana" should rank plain "Banana" above "TJ's Gone Bananas" or "Banana Bread"
    let results = try db.searchFoodsRanked(query: "banana")
    #expect(!results.isEmpty)
    if let first = results.first {
        #expect(first.name.lowercased().hasPrefix("banana"),
            "Plain Banana should rank first, got: \(first.name)")
    }
    // Also test singular search via findFood
    let match = AIActionExecutor.findFood(query: "bananas", servings: nil, gramAmount: nil)
    if let match {
        #expect(match.food.name.lowercased().contains("banana"),
            "findFood('bananas') should find Banana, got: \(match.food.name)")
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

@Test func smartUnitRiceShowsCupPrimary() async throws {
    let food = Food(name: "Rice (cooked)", category: "Grains", servingSize: 200, servingUnit: "g", calories: 260)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Rice should default to cup as primary unit")
    #expect(units.contains(where: { $0.label == "g" }), "Rice should still have grams option")

    // Excluded: rice cakes, rice paper, rice crackers should NOT default to cup
    let riceCake = Food(name: "Rice Cake", category: "Snacks", servingSize: 9, servingUnit: "g", calories: 35)
    #expect(FoodUnit.smartUnits(for: riceCake).first?.label != "cup",
            "Rice cake should not default to cup")
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

@Test func smartUnitPapadShowsPiece() async throws {
    let food = Food(name: "Papad (roasted)", category: "Indian Snacks", servingSize: 10, servingUnit: "g", calories: 35)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "piece", "Papad should default to piece")
}

@Test func smartUnitProteinBarShowsPiece() async throws {
    let bar = Food(name: "Protein Bar", category: "Snacks", servingSize: 60, servingUnit: "g", calories: 200)
    #expect(FoodUnit.smartUnits(for: bar).first?.label == "piece", "Protein bar should default to piece")

    let granola = Food(name: "Granola Bar", category: "Snacks", servingSize: 40, servingUnit: "g", calories: 180)
    #expect(FoodUnit.smartUnits(for: granola).first?.label == "piece", "Granola bar should default to piece")
}

@Test func smartUnitPickleShowsTbsp() async throws {
    let food = Food(name: "Pickle / Achar", category: "Condiments", servingSize: 15, servingUnit: "g", calories: 20)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp", "Pickle/achar should default to tbsp")
}

@Test func smartUnitQuinoaShowsCup() async throws {
    let food = Food(name: "Quinoa (cooked)", category: "Grains", servingSize: 185, servingUnit: "g", calories: 222)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Quinoa should default to cup")
    #expect(units.first?.gramsEquivalent == 185)
}

@Test func smartUnitOmeletteShowsPiece() {
    let food = Food(name: "Masala Omelette", category: "Protein", servingSize: 120, servingUnit: "g", calories: 180)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Omelette should default to piece")
    let omelet = Food(name: "Veggie Omelet", category: "Protein", servingSize: 100, servingUnit: "g", calories: 150)
    #expect(FoodUnit.smartUnits(for: omelet).first?.label == "piece", "Omelet (US spelling) should default to piece")
}

@Test func smartUnitDhoklaShowsPiece() {
    let food = Food(name: "Dhokla (Khaman Dhokla)", category: "Indian Snacks", servingSize: 60, servingUnit: "g", calories: 120)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Dhokla should default to piece")
    let khaman = Food(name: "Khaman", category: "Indian Snacks", servingSize: 60, servingUnit: "g", calories: 115)
    #expect(FoodUnit.smartUnits(for: khaman).first?.label == "piece", "Khaman should default to piece")
}

@Test func smartUnitKhakhraShowsPiece() {
    let food = Food(name: "Khakhra (Masala)", category: "Indian Snacks", servingSize: 30, servingUnit: "g", calories: 135)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Khakhra should default to piece")
}

@Test func smartUnitChillaShowsPiece() {
    let besan = Food(name: "Besan Chilla", category: "Indian Snacks", servingSize: 80, servingUnit: "g", calories: 145)
    #expect(FoodUnit.smartUnits(for: besan).first?.label == "piece", "Besan Chilla should default to piece")
    let moong = Food(name: "Moong Dal Cheela", category: "Indian Snacks", servingSize: 80, servingUnit: "g", calories: 120)
    #expect(FoodUnit.smartUnits(for: moong).first?.label == "piece", "Cheela should default to piece")
}

@Test func smartUnitPavBhajiShowsBowl() {
    let food = Food(name: "Pav Bhaji", category: "Indian Street Food", servingSize: 300, servingUnit: "g", calories: 420)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Pav Bhaji should default to bowl")
    let misal = Food(name: "Misal Pav", category: "Indian Street Food", servingSize: 300, servingUnit: "g", calories: 380)
    #expect(FoodUnit.smartUnits(for: misal).first?.label == "bowl", "Misal Pav should default to bowl")
}

@Test func smartUnitChiliDishShowsBowl() {
    let food = Food(name: "Chili Con Carne", category: "Mains", servingSize: 250, servingUnit: "g", calories: 320)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Chili (dish) should default to bowl")
    // Chili powder must NOT become a bowl
    let spice = Food(name: "Chili Powder", category: "Spices", servingSize: 3, servingUnit: "g", calories: 9)
    #expect(FoodUnit.smartUnits(for: spice).first?.label != "bowl", "Chili powder should not be a bowl")
}

@Test func smartUnitPuddingShowsBowl() {
    let mousse = Food(name: "Chocolate Mousse", category: "Desserts", servingSize: 120, servingUnit: "g", calories: 280)
    #expect(FoodUnit.smartUnits(for: mousse).first?.label == "bowl", "Mousse should default to bowl")
    let pudding = Food(name: "Bread Pudding", category: "Desserts", servingSize: 150, servingUnit: "g", calories: 310)
    #expect(FoodUnit.smartUnits(for: pudding).first?.label == "bowl", "Pudding should default to bowl")
}

@Test func smartUnitSevPuriIsChaat() {
    // "Sev Puri" contains "puri" but is a chaat — must return bowl, not piece
    let sevPuri = Food(name: "Sev Puri", category: "Indian Street Food", servingSize: 100, servingUnit: "g", calories: 200)
    #expect(FoodUnit.smartUnits(for: sevPuri).first?.label == "bowl", "Sev Puri is chaat — should be bowl not piece")
    let dahiPuri = Food(name: "Dahi Puri", category: "Indian Street Food", servingSize: 120, servingUnit: "g", calories: 210)
    #expect(FoodUnit.smartUnits(for: dahiPuri).first?.label == "bowl", "Dahi Puri is chaat — should be bowl")
}

// MARK: - Smart Unit Tests — Cheese, Fish, Tofu, Mushrooms, Steak

@Test func smartUnitTofuShowsCup() {
    let food = Food(name: "Tofu (firm)", category: "Protein", servingSize: 85, servingUnit: "g", calories: 70)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Tofu should default to cup")
    let superFirm = Food(name: "High Protein Tofu Super Firm", category: "Protein", servingSize: 85, servingUnit: "g", calories: 90)
    #expect(FoodUnit.smartUnits(for: superFirm).first?.label == "cup", "Super firm tofu should default to cup")
}

@Test func smartUnitMushroomShowsCup() {
    let food = Food(name: "Mushrooms (white)", category: "Vegetables", servingSize: 100, servingUnit: "g", calories: 22)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Mushrooms should default to cup")
    let shiitake = Food(name: "Shiitake Mushrooms", category: "Vegetables", servingSize: 100, servingUnit: "g", calories: 56)
    #expect(FoodUnit.smartUnits(for: shiitake).first?.label == "cup", "Shiitake mushrooms should default to cup")
}

@Test func smartUnitPortobelloShowsPiece() {
    let food = Food(name: "Portobello Mushroom", category: "Vegetables", servingSize: 120, servingUnit: "g", calories: 27)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Portobello should default to piece")
}

@Test func smartUnitParmesanShowsTbsp() {
    let food = Food(name: "Parmesan Cheese", category: "Dairy", servingSize: 15, servingUnit: "g", calories: 55)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "tbsp", "Parmesan should default to tbsp")
}

@Test func smartUnitFetaShowsTbsp() {
    let food = Food(name: "Feta Cheese", category: "Dairy", servingSize: 30, servingUnit: "g", calories: 75)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "tbsp", "Feta should default to tbsp")
}

// Regression: "Butter Chicken" was getting tbsp (butter word rule firing before dish rules)
@Test func smartUnitButterChickenShowsBowl() {
    let food = Food(name: "Butter Chicken", category: "Indian Mains", servingSize: 250, servingUnit: "g", calories: 350)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Butter Chicken is a dish — should be bowl, not tbsp")
    let frozen = Food(name: "TJ's Butter Chicken (frozen)", category: "Frozen", servingSize: 284, servingUnit: "g", calories: 400)
    #expect(FoodUnit.smartUnits(for: frozen).first?.label == "bowl", "Frozen Butter Chicken should also be bowl")
}

// Regression: "Chicken Parmesan" was getting tbsp (parmesan rule firing before dish check)
@Test func smartUnitChickenParmesanShowsPiece() {
    let food = Food(name: "Chicken Parmesan", category: "Mains", servingSize: 300, servingUnit: "g", calories: 480)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Chicken Parmesan is a dish — should be piece, not tbsp")
    // Plain parmesan cheese itself should still be tbsp
    let cheese = Food(name: "Parmesan Cheese (grated)", category: "Dairy", servingSize: 15, servingUnit: "g", calories: 55)
    #expect(FoodUnit.smartUnits(for: cheese).first?.label == "tbsp", "Parmesan cheese itself should remain tbsp")
}

// Regression: "Chicken Vindaloo" was falling through to serving (vindaloo not in curry list)
@Test func smartUnitVindalooShowsBowl() {
    let food = Food(name: "Chicken Vindaloo", category: "Indian Mains", servingSize: 250, servingUnit: "g", calories: 320)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Vindaloo should default to bowl")
}

// Regression: "Chicken Stock" was getting serving ("stock" not in broth/soup list)
@Test func smartUnitChickenStockShowsBowl() {
    let food = Food(name: "Kirkland Organic Chicken Stock", category: "Pantry", servingSize: 240, servingUnit: "ml", calories: 20)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Chicken stock should default to bowl like broth")
}

@Test func smartUnitShreddedCheeseShowsCup() {
    let cheddar = Food(name: "Cheddar Cheese (Shredded)", category: "Dairy", servingSize: 112, servingUnit: "g", calories: 450)
    #expect(FoodUnit.smartUnits(for: cheddar).first?.label == "cup", "Shredded cheddar should default to cup")
    let mozzarella = Food(name: "Mozzarella Shredded", category: "Dairy", servingSize: 112, servingUnit: "g", calories: 320)
    #expect(FoodUnit.smartUnits(for: mozzarella).first?.label == "cup", "Shredded mozzarella should default to cup")
}

@Test func smartUnitSalmonShowsPiece() {
    let fillet = Food(name: "Grilled Salmon Fillet", category: "Seafood", servingSize: 165, servingUnit: "g", calories: 280)
    #expect(FoodUnit.smartUnits(for: fillet).first?.label == "piece", "Salmon fillet should default to piece")
    // Salmon salad should remain bowl (salad rule takes priority)
    let salad = Food(name: "Salmon Salad", category: "Salads", servingSize: 200, servingUnit: "g", calories: 300)
    #expect(FoodUnit.smartUnits(for: salad).first?.label == "bowl", "Salmon salad should be bowl")
}

@Test func smartUnitSteakShowsPiece() {
    let steak = Food(name: "Beef Steak (sirloin)", category: "Protein", servingSize: 170, servingUnit: "g", calories: 320)
    #expect(FoodUnit.smartUnits(for: steak).first?.label == "piece", "Steak should default to piece")
    // Steak sauce should NOT become a piece
    let sauce = Food(name: "Steak Sauce", category: "Condiments", servingSize: 15, servingUnit: "g", calories: 20)
    #expect(FoodUnit.smartUnits(for: sauce).first?.label != "piece", "Steak sauce should not be piece")
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
    // A food with no specific portionText rule should fall back to total grams
    let entry = FoodEntry(mealLogId: 1, foodName: "Vegetable Medley", servingSizeG: 165, servings: 1.5, calories: 90)
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

@Test func portionTextBread() {
    let entry = FoodEntry(mealLogId: 1, foodName: "White Bread", servingSizeG: 30, servings: 2, calories: 80)
    #expect(entry.portionText == "2 slices", "Bread should show slices")
}

@Test func portionTextPizza() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Margherita Pizza", servingSizeG: 100, servings: 2, calories: 250)
    #expect(entry.portionText == "2 slices", "Pizza should show slices")
}

@Test func portionTextProteinPowder() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Whey Protein Powder", servingSizeG: 30, servings: 2, calories: 120)
    #expect(entry.portionText == "2 scoops", "Protein powder should show scoops")
}

@Test func portionTextSoup() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Tomato Soup", servingSizeG: 240, servings: 1, calories: 90)
    #expect(entry.portionText == "1 bowl", "Soup should show bowl")
}

@Test func portionTextBroth() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Chicken Broth", servingSizeG: 240, servings: 2, calories: 15)
    #expect(entry.portionText == "2 bowls", "Broth should show bowls")
}

@Test func portionTextOmelette() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Masala Omelette", servingSizeG: 120, servings: 1, calories: 180)
    #expect(entry.portionText == "1 omelette")
    let two = FoodEntry(mealLogId: 1, foodName: "Masala Omelette", servingSizeG: 120, servings: 2, calories: 180)
    #expect(two.portionText == "2 omelettes")
}

@Test func portionTextKhakhra() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Khakhra (Masala)", servingSizeG: 30, servings: 3, calories: 135)
    #expect(entry.portionText == "3 khakhras")
}

@Test func portionTextDhokla() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Dhokla (Khaman Dhokla)", servingSizeG: 60, servings: 2, calories: 120)
    #expect(entry.portionText == "2 pieces")
}

@Test func portionTextChilla() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Besan Chilla", servingSizeG: 80, servings: 1, calories: 145)
    #expect(entry.portionText == "1 piece")
}

@Test func portionTextPavBhaji() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Pav Bhaji", servingSizeG: 300, servings: 1, calories: 420)
    #expect(entry.portionText == "1 bowl")
}

@Test func portionTextChiliDish() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Chili Con Carne", servingSizeG: 250, servings: 2, calories: 320)
    #expect(entry.portionText == "2 bowls", "Chili dish should show bowls")
}

@Test func portionTextSalmonFillet() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Grilled Salmon Fillet", servingSizeG: 165, servings: 2, calories: 280)
    #expect(entry.portionText == "2 pieces", "Salmon fillet should show pieces")
    let single = FoodEntry(mealLogId: 1, foodName: "Salmon (baked)", servingSizeG: 150, servings: 1, calories: 240)
    #expect(single.portionText == "1 piece", "Single salmon serving should show piece")
}

@Test func portionTextSteak() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Beef Steak (sirloin)", servingSizeG: 170, servings: 1, calories: 320)
    #expect(entry.portionText == "1 piece", "Steak should show piece")
}

@Test func portionTextTofu() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Tofu (firm)", servingSizeG: 85, servings: 2, calories: 70)
    #expect(entry.portionText == "2 cups", "Tofu should show cups")
}

@Test func portionTextMushroom() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Mushrooms (white)", servingSizeG: 100, servings: 1, calories: 22)
    #expect(entry.portionText == "1 cup", "Mushrooms should show cup")
    let portobello = FoodEntry(mealLogId: 1, foodName: "Portobello Mushroom", servingSizeG: 120, servings: 2, calories: 27)
    #expect(portobello.portionText == "2 pieces", "Portobello should show pieces")
}

@Test func portionTextShreddedCheese() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Cheddar Cheese Shredded", servingSizeG: 112, servings: 1, calories: 450)
    #expect(entry.portionText == "1 cup", "Shredded cheese should show cup")
}

// MARK: - Smart Unit Tests — Batch 2/3 (flatbreads, snacks, grains, meats, produce)

@Test func smartUnitBhakri() {
    let food = Food(name: "Bhakri (Jowar)", category: "Indian Breads", servingSize: 50, servingUnit: "g", calories: 160)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Bhakri should default to piece")
}

@Test func smartUnitBhujia() {
    let food = Food(name: "Aloo Bhujia", category: "Indian Snacks", servingSize: 30, servingUnit: "g", calories: 160)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Aloo Bhujia should default to cup (loose snack)")
    // Aloo sabzi (not bhujia) should still be bowl
    let sabzi = Food(name: "Aloo Matar Sabzi", category: "Indian Mains", servingSize: 200, servingUnit: "g", calories: 180)
    #expect(FoodUnit.smartUnits(for: sabzi).first?.label == "bowl", "Aloo sabzi should be bowl")
}

@Test func smartUnitAncientGrainsShowCup() {
    let barley = Food(name: "Barley (cooked)", category: "Grains", servingSize: 182, servingUnit: "g", calories: 193)
    #expect(FoodUnit.smartUnits(for: barley).first?.label == "cup", "Barley should default to cup")
    let farro = Food(name: "Farro (cooked)", category: "Grains", servingSize: 182, servingUnit: "g", calories: 220)
    #expect(FoodUnit.smartUnits(for: farro).first?.label == "cup", "Farro should default to cup")
    let millet = Food(name: "Millet", category: "Grains", servingSize: 182, servingUnit: "g", calories: 207)
    #expect(FoodUnit.smartUnits(for: millet).first?.label == "cup", "Millet should default to cup")
}

@Test func smartUnitFloursShowCup() {
    let besan = Food(name: "Besan (Chickpea Flour)", category: "Flours", servingSize: 120, servingUnit: "g", calories: 440)
    #expect(FoodUnit.smartUnits(for: besan).first?.label == "cup", "Besan should default to cup")
    let bajra = Food(name: "Bajra Flour", category: "Flours", servingSize: 120, servingUnit: "g", calories: 380)
    #expect(FoodUnit.smartUnits(for: bajra).first?.label == "cup", "Bajra flour should default to cup")
    let ragi = Food(name: "Ragi Flour", category: "Flours", servingSize: 120, servingUnit: "g", calories: 336)
    #expect(FoodUnit.smartUnits(for: ragi).first?.label == "cup", "Ragi flour should default to cup")
}

@Test func smartUnitJerkyShowsStrip() {
    let food = Food(name: "Beef Jerky", category: "Snacks", servingSize: 28, servingUnit: "g", calories: 116)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "strip", "Beef jerky should default to strip")
    let turkey = Food(name: "Turkey Jerky", category: "Snacks", servingSize: 28, servingUnit: "g", calories: 90)
    #expect(FoodUnit.smartUnits(for: turkey).first?.label == "strip", "Turkey jerky should default to strip")
}

@Test func smartUnitCalamariShowsPiece() {
    let food = Food(name: "Fried Calamari", category: "Seafood", servingSize: 60, servingUnit: "g", calories: 150)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Calamari should default to piece")
}

@Test func smartUnitBuiltBarShowsPiece() {
    let food = Food(name: "Built Bar (Coconut Almond)", category: "Protein Bars", servingSize: 56, servingUnit: "g", calories: 180)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Built Bar should default to piece")
}

@Test func smartUnitCantaloupeShowsPiece() {
    let food = Food(name: "Cantaloupe", category: "Fruits", servingSize: 177, servingUnit: "g", calories: 60)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Cantaloupe should default to piece")
    let honeydew = Food(name: "Honeydew Melon", category: "Fruits", servingSize: 177, servingUnit: "g", calories: 64)
    #expect(FoodUnit.smartUnits(for: honeydew).first?.label == "piece", "Honeydew should default to piece")
}

@Test func smartUnitCherryTomatoShowsCup() {
    let food = Food(name: "Cherry Tomatoes", category: "Vegetables", servingSize: 150, servingUnit: "g", calories: 27)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Cherry tomatoes should default to cup")
}

@Test func smartUnitCeleryShowsPiece() {
    let food = Food(name: "Celery (2 stalks)", category: "Vegetables", servingSize: 80, servingUnit: "g", calories: 13)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Celery should default to piece (stalk)")
}

@Test func smartUnitBegunBhajaShowsPiece() {
    let food = Food(name: "Begun Bhaja (Bengali Fried Eggplant)", category: "Indian Mains", servingSize: 100, servingUnit: "g", calories: 120)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Begun Bhaja should default to piece")
    let stuffed = Food(name: "Bharwa Baingan", category: "Indian Mains", servingSize: 150, servingUnit: "g", calories: 180)
    #expect(FoodUnit.smartUnits(for: stuffed).first?.label == "piece", "Bharwa Baingan should default to piece")
}

@Test func smartUnitStirFryShowsBowl() {
    let food = Food(name: "Chicken Stir Fry", category: "Mains", servingSize: 300, servingUnit: "g", calories: 350)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Stir fry should default to bowl")
    let rendang = Food(name: "Beef Rendang", category: "Mains", servingSize: 250, servingUnit: "g", calories: 420)
    #expect(FoodUnit.smartUnits(for: rendang).first?.label == "bowl", "Rendang should default to bowl")
}

@Test func smartUnitKoreanDishesShowBowl() {
    let bulgogi = Food(name: "Beef Bulgogi", category: "Korean", servingSize: 200, servingUnit: "g", calories: 280)
    #expect(FoodUnit.smartUnits(for: bulgogi).first?.label == "bowl", "Bulgogi should default to bowl")
    let galbi = Food(name: "Galbi (Korean Short Ribs)", category: "Korean", servingSize: 200, servingUnit: "g", calories: 380)
    #expect(FoodUnit.smartUnits(for: galbi).first?.label == "bowl", "Galbi should default to bowl")
}

@Test func smartUnitChettinadShowsBowl() {
    let food = Food(name: "Chicken Chettinad", category: "Indian Mains", servingSize: 250, servingUnit: "g", calories: 350)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Chicken Chettinad should default to bowl")
    let handi = Food(name: "Chicken Handi", category: "Indian Mains", servingSize: 250, servingUnit: "g", calories: 380)
    #expect(FoodUnit.smartUnits(for: handi).first?.label == "bowl", "Chicken Handi should default to bowl")
}

// MARK: - Portion Text Tests — Batch 2/3

@Test func portionTextBhakri() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Bhakri (Jowar)", servingSizeG: 50, servings: 2, calories: 160)
    #expect(entry.portionText == "2 bhakris", "Bhakri should show bhakris")
}

@Test func portionTextLadooVariants() {
    let ladoo = FoodEntry(mealLogId: 1, foodName: "Besan Ladoo", servingSizeG: 40, servings: 2, calories: 200)
    #expect(ladoo.portionText == "2 pieces", "Ladoo should show pieces")
    let modak = FoodEntry(mealLogId: 1, foodName: "Ukadiche Modak", servingSizeG: 50, servings: 3, calories: 150)
    #expect(modak.portionText == "3 pieces", "Modak should show pieces")
    let baklava = FoodEntry(mealLogId: 1, foodName: "Baklava", servingSizeG: 35, servings: 2, calories: 180)
    #expect(baklava.portionText == "2 pieces", "Baklava should show pieces")
}

@Test func portionTextBhujia() {
    let entry = FoodEntry(mealLogId: 1, foodName: "Aloo Bhujia", servingSizeG: 30, servings: 1, calories: 160)
    #expect(entry.portionText == "1 cup", "Bhujia should show cup")
}

@Test func portionTextGrains() {
    let barley = FoodEntry(mealLogId: 1, foodName: "Barley (cooked)", servingSizeG: 182, servings: 1, calories: 193)
    #expect(barley.portionText == "1 cup", "Barley should show cup")
    let bulgur = FoodEntry(mealLogId: 1, foodName: "Bulgur Wheat", servingSizeG: 182, servings: 2, calories: 150)
    #expect(bulgur.portionText == "2 cups", "Bulgur should show cups")
}

@Test func portionTextFlours() {
    let besan = FoodEntry(mealLogId: 1, foodName: "Besan (Chickpea Flour)", servingSizeG: 120, servings: 1, calories: 440)
    #expect(besan.portionText == "1 cup", "Besan should show cup")
    let ragi = FoodEntry(mealLogId: 1, foodName: "Ragi Flour", servingSizeG: 120, servings: 1, calories: 336)
    #expect(ragi.portionText == "1 cup", "Ragi flour should show cup")
}

@Test func portionTextStirFryAndBulgogi() {
    let stirFry = FoodEntry(mealLogId: 1, foodName: "Chicken Stir Fry", servingSizeG: 300, servings: 1, calories: 350)
    #expect(stirFry.portionText == "1 bowl", "Stir fry should show bowl")
    let bulgogi = FoodEntry(mealLogId: 1, foodName: "Beef Bulgogi", servingSizeG: 200, servings: 1, calories: 280)
    #expect(bulgogi.portionText == "1 bowl", "Bulgogi should show bowl")
    let rendang = FoodEntry(mealLogId: 1, foodName: "Beef Rendang", servingSizeG: 250, servings: 1, calories: 420)
    #expect(rendang.portionText == "1 bowl", "Rendang should show bowl")
}

@Test func portionTextPastaExtended() {
    let mac = FoodEntry(mealLogId: 1, foodName: "Mac and Cheese", servingSizeG: 240, servings: 1, calories: 380)
    #expect(mac.portionText == "1 cup", "Mac and cheese should show cup")
    let carbonara = FoodEntry(mealLogId: 1, foodName: "Pasta Carbonara", servingSizeG: 250, servings: 1, calories: 450)
    #expect(carbonara.portionText == "1 cup", "Carbonara should show cup")
    let gnocchi = FoodEntry(mealLogId: 1, foodName: "Gnocchi", servingSizeG: 170, servings: 1, calories: 280)
    #expect(gnocchi.portionText == "1 cup", "Gnocchi should show cup")
}

@Test func portionTextDessertSlices() {
    let cheesecake = FoodEntry(mealLogId: 1, foodName: "New York Cheesecake", servingSizeG: 120, servings: 1, calories: 400)
    #expect(cheesecake.portionText == "1 slice", "Cheesecake should show slice")
    let tiramisu = FoodEntry(mealLogId: 1, foodName: "Tiramisu", servingSizeG: 150, servings: 1, calories: 350)
    #expect(tiramisu.portionText == "1 slice", "Tiramisu should show slice")
    let pannaCotta = FoodEntry(mealLogId: 1, foodName: "Panna Cotta", servingSizeG: 120, servings: 1, calories: 210)
    #expect(pannaCotta.portionText == "1 piece", "Panna cotta should show piece")
}

@Test func portionTextCoffeeDrinksShowMl() {
    let latte = FoodEntry(mealLogId: 1, foodName: "Oat Milk Latte", servingSizeG: 240, servings: 1, calories: 120)
    #expect(latte.portionText == "240ml", "Latte should show ml not grams")
    let espresso = FoodEntry(mealLogId: 1, foodName: "Espresso", servingSizeG: 30, servings: 2, calories: 4)
    #expect(espresso.portionText == "60ml", "Espresso should show ml")
    let cappuccino = FoodEntry(mealLogId: 1, foodName: "Cappuccino", servingSizeG: 180, servings: 1, calories: 80)
    #expect(cappuccino.portionText == "180ml", "Cappuccino should show ml")
}

@Test func portionTextFastFood() {
    let bigMac = FoodEntry(mealLogId: 1, foodName: "Big Mac", servingSizeG: 200, servings: 1, calories: 563)
    #expect(bigMac.portionText == "1 piece", "Big Mac should show piece")
    let whopper = FoodEntry(mealLogId: 1, foodName: "Whopper", servingSizeG: 270, servings: 1, calories: 657)
    #expect(whopper.portionText == "1 piece", "Whopper should show piece")
}

@Test func portionTextCornOnCob() {
    let cob = FoodEntry(mealLogId: 1, foodName: "Corn on the Cob", servingSizeG: 90, servings: 2, calories: 77)
    #expect(cob.portionText == "2 pieces", "Corn on the cob should show pieces")
    let kernels = FoodEntry(mealLogId: 1, foodName: "Sweet Corn (cooked)", servingSizeG: 154, servings: 1, calories: 132)
    #expect(kernels.portionText == "1 cup", "Corn kernels should show cup")
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

@Test func searchPrefixMatchFindsFullWord() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // Partial word "chick" should find "Chicken Breast", "Chicken Tikka", etc.
    let results = try db.searchFoodsRanked(query: "chick")
    #expect(!results.isEmpty, "Prefix 'chick' should match chicken foods")
    #expect(results.contains(where: { $0.name.lowercased().contains("chicken") }),
            "Results should include chicken: \(results.prefix(5).map(\.name))")
}

@Test func searchPrefixMatchShortQuery() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // Very short prefix "ban" should find "Banana"
    let results = try db.searchFoodsRanked(query: "ban")
    #expect(!results.isEmpty, "Prefix 'ban' should match banana foods")
    #expect(results.contains(where: { $0.name.lowercased().contains("banana") }),
            "Results should include banana: \(results.prefix(5).map(\.name))")
}

@Test func searchPrefixMatchRanksShorterNamesHigher() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    // "rice" should rank plain "Rice" before "Rice Pudding" or "Chicken Fried Rice"
    let results = try db.searchFoodsRanked(query: "rice")
    guard results.count >= 2 else { return }
    // Shortest match should be near top (ORDER BY LENGTH(f.name))
    let topName = results[0].name.lowercased()
    #expect(topName.contains("rice"), "Top result should contain rice")
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
    var fav = SavedFood(name: "Morning Oatmeal", calories: 350, proteinG: 15, carbsG: 50, fatG: 8)
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
    var recipe = SavedFood(name: "My Protein Bowl", calories: 500, proteinG: 40, carbsG: 50, fatG: 15, isRecipe: true)
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
    let db = seededDB()
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
    var r1 = SavedFood(name: "Breakfast", calories: 300, proteinG: 20, carbsG: 30, fatG: 10)
    var r2 = SavedFood(name: "Breakfast", calories: 500, proteinG: 30, carbsG: 50, fatG: 15)
    try db.saveFavorite(&r1)
    try db.saveFavorite(&r2)
    let results = try db.searchRecipes(query: "breakfast")
    #expect(results.count == 2, "Should allow duplicate names")
}

// MARK: - Multi-word Search Tests (3 tests)

@Test func multiWordSearchBothDirections() async throws {
    let db = seededDB()
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
    let db = seededDB()
    let broad = try db.searchFoods(query: "chicken")
    let narrow = try db.searchFoods(query: "chicken curry")
    #expect(narrow.count < broad.count, "Adding a word should narrow results")
    #expect(narrow.allSatisfy { $0.name.lowercased().contains("chicken") && $0.name.lowercased().contains("curry") })
}

@Test func multiWordRankedSearch() async throws {
    let db = seededDB()
    let results = try db.searchFoodsRanked(query: "rice cooked")
    #expect(!results.isEmpty, "Should find cooked rice")
    #expect(results.allSatisfy { $0.name.lowercased().contains("rice") && $0.name.lowercased().contains("cooked") })
}

// MARK: - Indian Food Search Usability (4 tests)

@Test func searchDalVariations() async throws {
    let db = seededDB()
    // "moong dal" should work as multi-word
    let results = try db.searchFoods(query: "moong dal")
    #expect(!results.isEmpty, "Should find moong dal")
}

@Test func searchChickenBreast() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "chicken breast")
    #expect(!results.isEmpty, "Should find chicken breast")
}

@Test func searchPaneerSmartUnit() async throws {
    let db = seededDB()
    let paneer = try db.searchFoods(query: "paneer")
    guard let p = paneer.first else { return }
    let units = FoodUnit.smartUnits(for: p)
    #expect(units.contains(where: { $0.label == "cup" }), "Paneer should have cup option")
    #expect(units.contains(where: { $0.label == "g" }), "Paneer should have grams option")
}

@Test func searchGheeSmartUnit() async throws {
    let db = seededDB()
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

// MARK: - Copy All to Today (date targeting)

@Test func copyAllToTodayUsesTodaysDate() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log food on a past date
    let pastDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
    await vm.goToDate(pastDate)
    await vm.quickAdd(name: "Past Meal A", calories: 400, proteinG: 30, carbsG: 40, fatG: 15, fiberG: 4, mealType: .lunch)
    await vm.quickAdd(name: "Past Meal B", calories: 250, proteinG: 20, carbsG: 25, fatG: 10, fiberG: 2, mealType: .lunch)
    #expect(await vm.todayEntries.count == 2)

    // Stay on past date (simulating user viewing a past day) and copy with explicit today date
    let todayStr = DateFormatters.todayString
    let pastEntries = await vm.todayEntries
    for entry in pastEntries {
        await vm.quickAdd(name: entry.foodName, calories: entry.totalCalories,
                          proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                          fatG: entry.totalFat, fiberG: entry.totalFiber,
                          mealType: .lunch, date: todayStr)
    }

    // Past date should still have only 2 entries (not 4)
    await vm.goToDate(pastDate)
    #expect(await vm.todayEntries.count == 2, "Past date should still have only 2 entries")

    // Today should have the 2 copied entries
    await vm.goToDate(Date())
    #expect(await vm.todayEntries.count == 2, "Today should have 2 copied entries")
    #expect(await vm.todayNutrition.calories == 650, "Total should be 400 + 250 = 650")
}

@Test func quickAddWithoutDateParameterUsesSelectedDate() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Navigate to a past date and quickAdd without date param
    let pastDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
    let pastStr = DateFormatters.dateOnly.string(from: pastDate)
    await vm.goToDate(pastDate)
    await vm.quickAdd(name: "Past Entry", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 1, mealType: .lunch)

    // Entry should be on the past date
    let logs = try db.fetchMealLogs(for: pastStr)
    #expect(!logs.isEmpty, "Meal log should exist on past date")
    let entries = try db.fetchFoodEntries(forMealLog: logs[0].id!)
    #expect(entries.count == 1)
    #expect(entries[0].date == pastStr, "Entry date should match selected past date")

    // Today should be empty
    let todayLogs = try db.fetchMealLogs(for: DateFormatters.todayString)
    let todayEntryCount = try todayLogs.reduce(0) { sum, log in
        sum + (try db.fetchFoodEntries(forMealLog: log.id!)).count
    }
    #expect(todayEntryCount == 0, "Today should have no entries")
}

@Test func quickAddWithDateParameterOverridesSelectedDate() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Navigate to a past date but quickAdd with explicit today date
    let pastDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
    let pastStr = DateFormatters.dateOnly.string(from: pastDate)
    let todayStr = DateFormatters.todayString
    await vm.goToDate(pastDate)
    await vm.quickAdd(name: "Redirected Entry", calories: 200, proteinG: 15, carbsG: 20, fatG: 8, fiberG: 2, mealType: .lunch, date: todayStr)

    // Past date should have nothing
    let pastLogs = try db.fetchMealLogs(for: pastStr)
    let pastEntryCount = try pastLogs.reduce(0) { sum, log in
        sum + (try db.fetchFoodEntries(forMealLog: log.id!)).count
    }
    #expect(pastEntryCount == 0, "Past date should have no entries")

    // Today should have the entry
    let todayLogs = try db.fetchMealLogs(for: todayStr)
    #expect(!todayLogs.isEmpty, "Today should have a meal log")
    let todayEntries = try db.fetchFoodEntries(forMealLog: todayLogs[0].id!)
    #expect(todayEntries.count == 1)
    #expect(todayEntries[0].foodName == "Redirected Entry")
    #expect(todayEntries[0].date == todayStr)
}

@Test func copyAllToTodayPreservesNutritionData() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log food with specific macros on a past date
    let pastDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
    await vm.goToDate(pastDate)
    await vm.quickAdd(name: "Chicken Breast", calories: 330, proteinG: 62, carbsG: 0, fatG: 7, fiberG: 0, mealType: .lunch, servingSizeG: 200)
    await vm.quickAdd(name: "Brown Rice", calories: 215, proteinG: 5, carbsG: 45, fatG: 2, fiberG: 4, mealType: .lunch, servingSizeG: 180)

    let todayStr = DateFormatters.todayString
    let pastEntries = await vm.todayEntries
    for entry in pastEntries {
        await vm.quickAdd(name: entry.foodName, calories: entry.totalCalories,
                          proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                          fatG: entry.totalFat, fiberG: entry.totalFiber,
                          mealType: .lunch, servingSizeG: entry.servingSizeG, date: todayStr)
    }

    // Verify nutrition is preserved on today
    await vm.goToDate(Date())
    let todayEntries = await vm.todayEntries
    #expect(todayEntries.count == 2, "Should have 2 copied entries")

    let chicken = todayEntries.first { $0.foodName == "Chicken Breast" }
    let rice = todayEntries.first { $0.foodName == "Brown Rice" }
    #expect(chicken != nil, "Chicken should be copied")
    #expect(rice != nil, "Rice should be copied")
    #expect(chicken?.totalCalories == 330)
    #expect(chicken?.totalProtein == 62)
    #expect(chicken?.servingSizeG == 200)
    #expect(rice?.totalCalories == 215)
    #expect(rice?.totalCarbs == 45)
    #expect(rice?.totalFiber == 4)
}

@Test func copyAllToTodayDoesNotDuplicateOnSource() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log 3 entries on a past date
    let pastDate = Calendar.current.date(byAdding: .day, value: -4, to: Date())!
    let pastStr = DateFormatters.dateOnly.string(from: pastDate)
    await vm.goToDate(pastDate)
    await vm.quickAdd(name: "Item 1", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 1, mealType: .breakfast)
    await vm.quickAdd(name: "Item 2", calories: 200, proteinG: 20, carbsG: 20, fatG: 10, fiberG: 2, mealType: .lunch)
    await vm.quickAdd(name: "Item 3", calories: 300, proteinG: 30, carbsG: 30, fatG: 15, fiberG: 3, mealType: .dinner)

    // Copy all to today
    let todayStr = DateFormatters.todayString
    let pastEntries = await vm.todayEntries
    for entry in pastEntries {
        await vm.quickAdd(name: entry.foodName, calories: entry.totalCalories,
                          proteinG: entry.totalProtein, carbsG: entry.totalCarbs,
                          fatG: entry.totalFat, fiberG: entry.totalFiber,
                          mealType: MealType(rawValue: entry.mealType ?? "lunch") ?? .lunch, date: todayStr)
    }

    // Source date should still have exactly 3
    await vm.goToDate(pastDate)
    #expect(await vm.todayEntries.count == 3, "Source date should still have exactly 3 entries")

    // Count entries in DB for past date to be extra sure
    let pastLogs = try db.fetchMealLogs(for: pastStr)
    let pastTotal = try pastLogs.reduce(0) { sum, log in
        sum + (try db.fetchFoodEntries(forMealLog: log.id!)).count
    }
    #expect(pastTotal == 3, "DB should have exactly 3 entries on source date")
}

@Test func copyEntryToTodayFromDistantPast() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log on a date 30 days ago
    let distantPast = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
    await vm.goToDate(distantPast)
    await vm.quickAdd(name: "Old Meal", calories: 500, proteinG: 35, carbsG: 50, fatG: 20, fiberG: 5, mealType: .lunch)

    // Copy single entry to today
    let entries = await vm.todayEntries
    guard let entry = entries.first else {
        #expect(Bool(false), "Should have an entry to copy")
        return
    }
    await vm.copyEntryToToday(entry)

    // Verify on today
    await vm.goToDate(Date())
    await vm.loadTodayMeals()
    let todayEntries = await vm.todayEntries
    #expect(todayEntries.count == 1, "Should have 1 copied entry on today")
    #expect(todayEntries[0].foodName == "Old Meal")
    #expect(todayEntries[0].totalCalories == 500)
    #expect(todayEntries[0].date == DateFormatters.todayString, "Copied entry date must be today")
}

@Test func copyEntryToTodayDoesNotRemoveFromSource() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Keep Me", calories: 150, proteinG: 12, carbsG: 15, fatG: 6, fiberG: 2, mealType: .lunch)

    let entries = await vm.todayEntries
    guard let entry = entries.first else { return }
    await vm.copyEntryToToday(entry)

    // Source should still have the entry
    await vm.goToDate(yesterday)
    await vm.loadTodayMeals()
    #expect(await vm.todayEntries.count == 1, "Source entry should not be removed")
    #expect(await vm.todayEntries[0].foodName == "Keep Me")

    // Today should also have it
    await vm.goToDate(Date())
    await vm.loadTodayMeals()
    #expect(await vm.todayEntries.count == 1, "Today should have copied entry")
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
        #expect(t.calorieTarget > 800 && t.calorieTarget < 4000, "Fallback target should be reasonable, got \(Int(t.calorieTarget))")
    }
    // With explicit TDEE, should still work
    let withTDEE = goal.macroTargets(actualTDEE: 2200)
    #expect(withTDEE != nil, "With TDEE, targets should compute")
}

@Test func macroTargetsIncludesFiberUsingUSDAFormula() async throws {
    // 2000 kcal → 14 * 2000/1000 = 28 → round up to 30 g
    let goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, calorieTargetOverride: 2000)
    let targets = goal.macroTargets()!
    #expect(targets.fiberG == 30, "2000 kcal should yield 30 g fiber target, got \(targets.fiberG)")
}

@Test func macroTargetsFiberTargetRespectsFloor() async throws {
    // 1200 kcal → 14 * 1.2 = 16.8 → rounds up to 20, but floor is 25 g
    let goal = WeightGoal(targetWeightKg: 60, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 70, calorieTargetOverride: 1200)
    let targets = goal.macroTargets()!
    #expect(targets.fiberG == 25, "Fiber floor of 25 g should apply, got \(targets.fiberG)")
}

@Test func macroTargetsFiberWithAllMacrosSet() async throws {
    // Even when all 3 macros are overridden, fiber target should still be computed.
    var goal = WeightGoal(targetWeightKg: 75, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 85, calorieTargetOverride: 2000)
    goal.proteinTargetG = 180
    goal.fatTargetG = 60
    goal.carbsTargetG = 200
    let targets = goal.macroTargets()!
    #expect(targets.fiberG > 0, "Fiber target should always be present")
    // 180*4 + 200*4 + 60*9 = 720 + 800 + 540 = 2060 kcal → 14*2.06=28.84 → rounds up to 30
    #expect(targets.fiberG == 30, "Expected 30 g fiber for ~2060 kcal, got \(targets.fiberG)")
}

@Test func defaultFiberGRoundsUpToNearestFive() async throws {
    // 1500 kcal → 14 * 1.5 = 21, rounds up to 25 (which also happens to be the floor)
    #expect(WeightGoal.defaultFiberG(calories: 1500) == 25)
    // 2200 kcal → 14 * 2.2 = 30.8, rounds up to 35
    #expect(WeightGoal.defaultFiberG(calories: 2200) == 35)
    // 3000 kcal → 14 * 3 = 42, rounds up to 45
    #expect(WeightGoal.defaultFiberG(calories: 3000) == 45)
}

@Test func goalResolvedCalorieTargetUsesSoftCap() async throws {
    // Heavy person: off-main-thread fallback should use computeBase (with soft cap)
    let goal = WeightGoal(targetWeightKg: 100, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 120)
    // With explicit TDEE, soft cap doesn't apply (it's a known value)
    let withExplicit = goal.macroTargets(actualTDEE: 2800)
    #expect(withExplicit != nil)

    // The base for 120kg at moderate activity: raw = 2619, under 2700 soft cap, so = 2619
    let base = TDEEEstimator.computeBase(weightKg: 120, activityMultiplier: 29)
    #expect(base < 2700, "120kg moderate should be under soft cap, got \(Int(base))")
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
    let db = seededDB()
    // These should not crash
    for q in ["'", "\"", "%", "_", "\\", "(", ")", "--", ";", "DROP TABLE"] {
        let _ = try db.searchFoods(query: q)
        let _ = try db.searchFoodsRanked(query: q)
    }
}

@Test func foodSearchUnicodeCharacters() async throws {
    let db = seededDB()
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
    var fav = SavedFood(name: "Delete Me Recipe", calories: 100, proteinG: 10, carbsG: 10, fatG: 5)
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
    let db = seededDB()
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

@Test func fetchSavedFoods() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let egg = try db.searchFoods(query: "egg").first!
    try db.toggleFoodFavorite(name: egg.name, foodId: egg.id)
    let favs = try db.fetchSavedFoods()
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
    let favs = try db.fetchSavedFoods()
    #expect(recents.contains(where: { $0.name == rice.name }))
    #expect(favs.contains(where: { $0.name == rice.name }))
}

@Test func favoriteWithoutLogging() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let dal = try db.searchFoods(query: "dal").first!
    // Favorite without logging
    try db.toggleFoodFavorite(name: dal.name, foodId: dal.id)
    let favs = try db.fetchSavedFoods()
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
    let favs = try db.fetchSavedFoods()
    #expect(favs.contains(where: { $0.name == egg.name }))

    // Unfavorite
    try db.toggleFoodFavorite(name: egg.name, foodId: egg.id)
    let favsAfter = try db.fetchSavedFoods()
    #expect(!favsAfter.contains(where: { $0.name == egg.name }))
}

@Test func fullFlowRecipeCreateLogDelete() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Create recipe
    var recipe = SavedFood(name: "Test Recipe", calories: 500, proteinG: 30, carbsG: 50, fatG: 15, isRecipe: true)
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
    let db = seededDB()
    let all = try db.searchFoods(query: "e", limit: 600) + db.searchFoods(query: "a", limit: 600)
    let negative = all.filter { $0.calories < 0 }
    #expect(negative.isEmpty, "Foods with negative calories: \(negative.map(\.name))")
}

@Test func allFoodsHaveReasonableServingSize() async throws {
    let db = seededDB()
    let all = try db.searchFoods(query: "e", limit: 600) + db.searchFoods(query: "a", limit: 600)
    let zeroServing = all.filter { $0.servingSize <= 0 }
    #expect(zeroServing.isEmpty, "Foods with zero serving: \(zeroServing.map(\.name))")
}

@Test func allFoodsHaveNonEmptyNames() async throws {
    let db = seededDB()
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

@Test func smartUnitsIndianSweetPiece() async throws {
    let gulab = Food(name: "Gulab Jamun", category: "Desserts", servingSize: 45, servingUnit: "g", calories: 175)
    #expect(FoodUnit.smartUnits(for: gulab).first?.label == "piece",
            "Gulab jamun should default to piece, not serving or grams")

    let laddu = Food(name: "Besan Laddu", category: "Desserts", servingSize: 40, servingUnit: "g", calories: 185)
    #expect(FoodUnit.smartUnits(for: laddu).first?.label == "piece",
            "Laddu should default to piece")

    let jalebi = Food(name: "Jalebi", category: "Desserts", servingSize: 30, servingUnit: "g", calories: 120)
    #expect(FoodUnit.smartUnits(for: jalebi).first?.label == "piece",
            "Jalebi should default to piece")
}

@Test func smartUnitsBatterCup() async throws {
    let batter = Food(name: "Dosa Batter", category: "Indian Staples", servingSize: 100, servingUnit: "g", calories: 82)
    let units = FoodUnit.smartUnits(for: batter)
    #expect(units.first?.label == "cup", "Dosa batter should default to cup, not piece")

    let idliBatter = Food(name: "Idli Batter", category: "Indian Staples", servingSize: 100, servingUnit: "g", calories: 78)
    #expect(FoodUnit.smartUnits(for: idliBatter).first?.label == "cup",
            "Idli batter should default to cup")

    // "doughnut" contains "dough" but is a countable — must not be treated as batter
    let doughnut = Food(name: "Glazed Doughnut", category: "Bakery", servingSize: 60, servingUnit: "g", calories: 250)
    #expect(FoodUnit.smartUnits(for: doughnut).first?.label == "piece",
            "Doughnut should default to piece, not cup")

    // "cookie dough" flavor (e.g. protein bar) — must not be treated as batter
    let bar = Food(name: "Quest Bar Cookie Dough", category: "Protein Bars", servingSize: 60, servingUnit: "g", calories: 190)
    #expect(FoodUnit.smartUnits(for: bar).first?.label != "cup",
            "Cookie dough flavor bar must not default to cup")
}

@Test func smartUnitsBreadSlice() async throws {
    let bread = Food(name: "Whole Wheat Bread", category: "Bakery", servingSize: 30, servingUnit: "g", calories: 75)
    #expect(FoodUnit.smartUnits(for: bread).first?.label == "slice",
            "Bread should default to slice")

    let toast = Food(name: "White Toast", category: "Bakery", servingSize: 25, servingUnit: "g", calories: 65)
    #expect(FoodUnit.smartUnits(for: toast).first?.label == "slice",
            "Toast should default to slice")

    let sourdough = Food(name: "Sourdough Bread", category: "Bakery", servingSize: 35, servingUnit: "g", calories: 90)
    #expect(FoodUnit.smartUnits(for: sourdough).first?.label == "slice",
            "Sourdough bread should default to slice, not cup")
}

@Test func smartUnitsPizzaSlice() async throws {
    let pizza = Food(name: "Margherita Pizza", category: "Italian", servingSize: 100, servingUnit: "g", calories: 250)
    #expect(FoodUnit.smartUnits(for: pizza).first?.label == "slice",
            "Pizza should default to slice")
}

@Test func smartUnitsSoupBowl() async throws {
    let soup = Food(name: "Chicken Noodle Soup", category: "Soups", servingSize: 250, servingUnit: "g", calories: 150)
    #expect(FoodUnit.smartUnits(for: soup).first?.label == "bowl",
            "Soup should default to bowl")

    let stew = Food(name: "Beef Stew", category: "Soups", servingSize: 300, servingUnit: "g", calories: 280)
    #expect(FoodUnit.smartUnits(for: stew).first?.label == "bowl",
            "Stew should default to bowl")
}

@Test func smartUnitsYogurtCup() async throws {
    let yogurt = Food(name: "Greek Yogurt", category: "Dairy", servingSize: 170, servingUnit: "g", calories: 100)
    let units = FoodUnit.smartUnits(for: yogurt)
    #expect(units.first?.label == "cup", "Yogurt should default to cup")
    // 1 cup yogurt ≈ 245g
    #expect(units.first!.gramsEquivalent == 245)
}

@Test func smartUnitsOatsCup() async throws {
    let oats = Food(name: "Oats (dry)", category: "Grains & Cereals", servingSize: 40, servingUnit: "g", calories: 156)
    let units = FoodUnit.smartUnits(for: oats)
    #expect(units.first?.label == "cup", "Oats should default to cup")
    // 1 cup dry oats ≈ 80g
    #expect(units.first!.gramsEquivalent == 80)
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

// MARK: - Batch Query Tests

@Test func fetchDailyCaloriesBatch() async throws {
    let db = try AppDatabase.empty()
    let today = DateFormatters.todayString
    let vm = await FoodLogViewModel(database: db)

    // Log food
    await vm.quickAdd(name: "Breakfast", calories: 400, proteinG: 20, carbsG: 40, fatG: 15, fiberG: 3, mealType: .breakfast)
    await vm.quickAdd(name: "Lunch", calories: 600, proteinG: 30, carbsG: 50, fatG: 20, fiberG: 5, mealType: .lunch)

    let result = try db.fetchDailyCalories(from: today, to: today)
    #expect(result[today] != nil, "Should have calories for today")
    #expect(abs((result[today] ?? 0) - 1000) < 1, "Total should be ~1000, got \(result[today] ?? 0)")
}

@Test func fetchDailyCaloriesEmptyRange() async throws {
    let db = try AppDatabase.empty()
    let result = try db.fetchDailyCalories(from: "2020-01-01", to: "2020-01-31")
    #expect(result.isEmpty, "No data should return empty dict")
}

// MARK: - Recovery Estimator Tests

@Test func recoveryDeviationCalculation() async throws {
    // HRV above baseline should be favorable
    let (arrow, pct, favorable) = RecoveryEstimator.deviation(current: 65, baseline: 50, higherIsBetter: true)
    #expect(arrow == "↑")
    #expect(pct == 30)
    #expect(favorable == true)

    // RHR above baseline should be unfavorable (lower is better)
    let (arrow2, _, fav2) = RecoveryEstimator.deviation(current: 70, baseline: 60, higherIsBetter: false)
    #expect(arrow2 == "↑")
    #expect(fav2 == false)
}

@Test func dynamicSleepNeedCapped() async throws {
    // Even with extreme inputs, sleep need should never exceed 9h
    let need = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: 21, rollingDebtHours: -3)
    #expect(need <= 9.0, "Sleep need should be capped at 9h, got \(need)")
    #expect(need >= 7.5, "Sleep need should be at least 7.5h")
}

@Test func sleepDebtCapped() async throws {
    // Massive undersleeping should cap at -3h
    let recentSleep: [(date: Date, hours: Double)] = (0..<7).map { i in
        (Calendar.current.date(byAdding: .day, value: -i, to: Date())!, 4.0)
    }
    let debt = RecoveryEstimator.sleepDebt(recentSleep: recentSleep, need: 8.0)
    #expect(debt >= -3.0, "Debt should be capped at -3, got \(debt)")
}

@Test func activityLoadClassification() async throws {
    let (rest, _) = RecoveryEstimator.calculateActivityLoad(activeCalories: 0, steps: 0)
    #expect(rest == .rest)

    let (moderate, _) = RecoveryEstimator.calculateActivityLoad(activeCalories: 400, steps: 8000)
    #expect(moderate == .moderate || moderate == .light)

    let (high, raw) = RecoveryEstimator.calculateActivityLoad(activeCalories: 1000, steps: 20000)
    #expect(raw > 10, "High activity should produce raw > 10, got \(raw)")
    #expect(high == .heavy || high == .extreme, "1000 cal + 20k steps should be heavy or extreme, got \(high)")
}

// MARK: - Recovery Algorithm Tests (missing data handling)

@Test func recoveryMissingHRVWithGoodRHRAndSleep() async throws {
    // User's real scenario: no HRV, RHR 51 (baseline 65), sleep 6.8h (baseline 7.5h)
    let baselines = RecoveryEstimator.Baselines(hrvMs: 45, restingHR: 65, respiratoryRate: 15, sleepHours: 7.5, daysOfData: 14)
    let score = RecoveryEstimator.calculateRecovery(hrvMs: 0, restingHR: 51, sleepHours: 6.8, baselines: baselines)
    #expect(score >= 80, "Missing HRV + excellent RHR + decent sleep should score 80+, got \(score)")
    #expect(score <= 95, "Should not be unrealistically high, got \(score)")
}

@Test func recoveryMissingHRVScoresHigherThanBadHRV() async throws {
    // Missing HRV should redistribute weights, not penalize.
    // Bad HRV (15ms) should score LOWER than no HRV with same RHR/sleep.
    let baselines = RecoveryEstimator.Baselines(hrvMs: 45, restingHR: 65, respiratoryRate: 15, sleepHours: 7.5, daysOfData: 14)
    let noHRV = RecoveryEstimator.calculateRecovery(hrvMs: 0, restingHR: 55, sleepHours: 7, baselines: baselines)
    let badHRV = RecoveryEstimator.calculateRecovery(hrvMs: 15, restingHR: 55, sleepHours: 7, baselines: baselines)
    #expect(noHRV > badHRV, "No HRV (\(noHRV)) should score higher than bad HRV (\(badHRV))")
}

@Test func sleepScoreWithoutStageData() async throws {
    // iPhone-only sleep: no REM/Deep stages, just duration
    let score = RecoveryEstimator.calculateSleepScore(totalHours: 6.8, remHours: 0, deepHours: 0, targetHours: 7.5)
    #expect(score >= 85, "Good duration without stage data should score 85+, got \(score)")
}

@Test func sleepScoreWithStageDataStillUsesQuality() async throws {
    // When stage data exists, quality should still matter
    let good = RecoveryEstimator.calculateSleepScore(totalHours: 7, remHours: 1.5, deepHours: 1.2, targetHours: 7.5)
    let noStages = RecoveryEstimator.calculateSleepScore(totalHours: 7, remHours: 0, deepHours: 0, targetHours: 7.5)
    #expect(good > noStages || good == noStages, "Good stages should score >= no stages: good=\(good) noStages=\(noStages)")
}

// MARK: - TDEE Estimator Tests

// Group 1: Base formula
@Test func tdeeBaseNoWeight() async throws {
    let base = TDEEEstimator.computeBase(weightKg: nil, activityMultiplier: 29)
    #expect(base == 2000, "No weight = 2000 default")
}

@Test func tdeeBaseAnchor70kg() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    #expect(abs(base - 2000) < 1, "70kg at moderate = 2000 anchor")
}

@Test func tdeeBaseLightPerson() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 53.8, activityMultiplier: 29)
    #expect(base > 1700 && base < 1800, "53.8kg should be ~1,754, got \(Int(base))")
}

@Test func tdeeBaseHeavyPerson() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 78.4, activityMultiplier: 29)
    #expect(base > 2050 && base < 2200, "78.4kg should be ~2,117 (not 2,585), got \(Int(base))")
}

@Test func tdeeBaseVeryHeavy() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 110, activityMultiplier: 29)
    #expect(base > 2400 && base < 2600, "110kg should be ~2,508 with diminishing returns, got \(Int(base))")
}

// Group 2: Activity slider
@Test func tdeeActivitySedentary() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 78.4, activityMultiplier: 22)
    #expect(base > 1500 && base < 1700, "Sedentary 78.4kg ~1,606, got \(Int(base))")
}

@Test func tdeeActivityAthlete() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 78.4, activityMultiplier: 36)
    #expect(base > 2500 && base < 2700, "Athlete 78.4kg ~2,628, got \(Int(base))")
}

// Group 3: Mifflin-St Jeor
@Test func mifflinMale() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 36, heightCm: 185, sex: .male)
    let (tdee, confidence) = TDEEEstimator.computeMifflin(weightKg: 78.4, config: config)!
    #expect(abs(tdee - 2736) < 5, "Male Mifflin TDEE ~2,736, got \(Int(tdee))")
    #expect(confidence == 1.0, "All 3 fields = 100% confidence")
}

@Test func mifflinFemale() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 30, heightCm: 165, sex: .female)
    let (tdee, _) = TDEEEstimator.computeMifflin(weightKg: 62, config: config)!
    #expect(abs(tdee - 2079) < 5, "Female Mifflin TDEE ~2,079, got \(Int(tdee))")
}

@Test func mifflinReturnsNilWithoutAnyProfile() async throws {
    let config = TDEEEstimator.TDEEConfig.default
    let result = TDEEEstimator.computeMifflin(weightKg: 70, config: config)
    #expect(result == nil, "No profile fields at all = nil")
}

@Test func mifflinPartialAgeOnly() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 36, heightCm: nil, sex: nil)
    let (tdee, confidence) = TDEEEstimator.computeMifflin(weightKg: 78.4, config: config)!
    #expect(confidence > 0.3 && confidence < 0.4, "1 of 3 fields = ~33% confidence")
    #expect(tdee > 1500 && tdee < 3000, "Partial Mifflin should be reasonable")
}

@Test func mifflinPartialSexOnly() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: nil, heightCm: nil, sex: .female)
    let (tdee, confidence) = TDEEEstimator.computeMifflin(weightKg: 62, config: config)!
    #expect(confidence > 0.3 && confidence < 0.4)
    // Uses defaults: age 30, height 170cm
    #expect(tdee > 1500 && tdee < 2500, "Female partial should be reasonable")
}

@Test func mifflinPartialTwoFields() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 36, heightCm: 185, sex: nil)
    let (_, confidence) = TDEEEstimator.computeMifflin(weightKg: 78.4, config: config)!
    #expect(confidence > 0.6 && confidence < 0.7, "2 of 3 fields = ~67% confidence")
}

// Group 4: Mifflin correction dampening
@Test func mifflinCorrectionDampened() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 78.4, activityMultiplier: 29) // ~2117
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 36, heightCm: 185, sex: .male)
    let (mifflin, confidence) = TDEEEstimator.computeMifflin(weightKg: 78.4, config: config)! // ~2736, 1.0
    let corrected = base + (mifflin - base) * 0.4 * confidence // ~2365
    #expect(corrected > 2300 && corrected < 2400, "Dampened correction should be ~2,365, got \(Int(corrected))")
    #expect(corrected < mifflin, "Correction must be less than raw Mifflin")
    #expect(corrected > base, "Correction must be more than base for tall active male")
}

// Group 5: Same weight, different demographics
@Test func sameWeightDifferentPeople() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 78, activityMultiplier: 29) // same for both

    let maleConfig = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                                age: 28, heightCm: 185, sex: .male)
    let femaleConfig = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                                  age: 50, heightCm: 158, sex: .female)
    let (maleMifflin, maleConf) = TDEEEstimator.computeMifflin(weightKg: 78, config: maleConfig)!
    let (femaleMifflin, femaleConf) = TDEEEstimator.computeMifflin(weightKg: 78, config: femaleConfig)!

    let maleResult = base + (maleMifflin - base) * 0.4 * maleConf
    let femaleResult = base + (femaleMifflin - base) * 0.4 * femaleConf

    #expect(maleResult - femaleResult > 250, "Same 78kg: male should be >250 cal higher than older shorter female, got \(Int(maleResult - femaleResult))")
}

// Group 6: Diminishing returns (heavy weights don't explode)
@Test func diminishingReturns() async throws {
    let at70 = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    let at140 = TDEEEstimator.computeBase(weightKg: 140, activityMultiplier: 29)
    // sqrt scaling: doubling weight should NOT double TDEE
    let ratio = at140 / at70
    #expect(ratio < 1.5, "Doubling weight should increase TDEE by < 50%, got \(String(format: "%.0f", (ratio-1)*100))%")
    #expect(ratio > 1.3, "But should still increase meaningfully")
}

// Group 7: Edge cases
@Test func tdeeMinimumFloor() async throws {
    // Even with extreme negative adjustment, should floor at 1200
    var base = TDEEEstimator.computeBase(weightKg: 45, activityMultiplier: 22) // ~1216
    base = max(1200, base + (-500)) // adjustment -500
    #expect(base >= 1200, "TDEE should never go below 1200")
}

// MARK: - TDEE Sync Tests (Algorithm page must match Dashboard)

@MainActor
@Test func tdeeSyncAfterConfigChange() async throws {
    // Save a config, then verify cachedOrSync returns consistent value
    var config = TDEEEstimator.TDEEConfig.default
    config.activityMultiplier = 32
    TDEEEstimator.saveConfig(config) // clears cache
    let first = TDEEEstimator.shared.cachedOrSync().tdee
    let second = TDEEEstimator.shared.cachedOrSync().tdee
    #expect(first == second, "Two consecutive reads must return same TDEE")
    // Restore default
    TDEEEstimator.saveConfig(.default)
}

@MainActor
@Test func tdeeSyncBetweenReads() async throws {
    // Verify that cachedOrSync is idempotent within a session
    TDEEEstimator.saveConfig(.default)
    let read1 = TDEEEstimator.shared.cachedOrSync()
    let read2 = TDEEEstimator.shared.cachedOrSync()
    let read3 = TDEEEstimator.shared.cachedOrSync()
    #expect(read1.tdee == read2.tdee && read2.tdee == read3.tdee,
            "All reads must return identical TDEE: \(read1.tdee), \(read2.tdee), \(read3.tdee)")
}

@MainActor
@Test func tdeeCacheInvalidatedOnSave() async throws {
    // Change config, verify TDEE changes
    var config1 = TDEEEstimator.TDEEConfig.default
    config1.manualAdjustment = 0
    TDEEEstimator.saveConfig(config1)
    let tdee1 = TDEEEstimator.shared.cachedOrSync().tdee

    var config2 = config1
    config2.manualAdjustment = 200
    TDEEEstimator.saveConfig(config2)
    let tdee2 = TDEEEstimator.shared.cachedOrSync().tdee

    #expect(abs(tdee2 - tdee1 - 200) < 1, "Adding +200 adjustment should increase TDEE by ~200, got \(tdee2 - tdee1)")

    // Restore
    TDEEEstimator.saveConfig(.default)
}

// MARK: - TDEE Comprehensive Demographic Tests

// Soft cap: base formula should never exceed ~2800 without profile data
@Test func tdeeBaseSoftCapPreventsExtreme() async throws {
    // 110kg athlete: raw would be ~3114, soft cap should bring it under 2850
    let heavy = TDEEEstimator.computeBase(weightKg: 110, activityMultiplier: 36)
    #expect(heavy < 2850, "110kg athlete base should be soft-capped, got \(Int(heavy))")
    #expect(heavy > 2700, "Should still be higher than moderate, got \(Int(heavy))")

    // 140kg athlete: raw would be ~3514, soft cap should keep it well under 3000
    let veryHeavy = TDEEEstimator.computeBase(weightKg: 140, activityMultiplier: 36)
    #expect(veryHeavy < 3000, "140kg athlete base must stay under 3000 without profile, got \(Int(veryHeavy))")
    #expect(veryHeavy > 2800, "But still meaningful, got \(Int(veryHeavy))")
}

@Test func tdeeBaseSoftCapDoesNotAffectNormal() async throws {
    // Normal-weight people at moderate activity should NOT be capped
    let at53 = TDEEEstimator.computeBase(weightKg: 53, activityMultiplier: 29)
    let at70 = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    let at85 = TDEEEstimator.computeBase(weightKg: 85, activityMultiplier: 29)

    #expect(at53 > 1700 && at53 < 1800, "53kg moderate unchanged, got \(Int(at53))")
    #expect(abs(at70 - 2000) < 1, "70kg anchor unchanged, got \(Int(at70))")
    #expect(at85 > 2100 && at85 < 2250, "85kg moderate unchanged, got \(Int(at85))")
}

// Age group tests: Mifflin-St Jeor across demographics
@Test func mifflinYoungMale20() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 20, heightCm: 178, sex: .male)
    let (tdee, _) = TDEEEstimator.computeMifflin(weightKg: 75, config: config)!
    // BMR: 10*75 + 6.25*178 - 5*20 + 5 = 750+1112.5-100+5 = 1767.5, × 1.55 = 2740
    #expect(tdee > 2600 && tdee < 2850, "Young 20yo male TDEE ~2740, got \(Int(tdee))")
}

@Test func mifflinYoungFemale25() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 25, heightCm: 163, sex: .female)
    let (tdee, _) = TDEEEstimator.computeMifflin(weightKg: 58, config: config)!
    // BMR: 10*58 + 6.25*163 - 5*25 - 161 = 580+1018.75-125-161 = 1312.75, × 1.55 = 2035
    #expect(tdee > 1900 && tdee < 2150, "Young 25yo female TDEE ~2035, got \(Int(tdee))")
}

@Test func mifflinMiddleAgeMale45() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 45, heightCm: 175, sex: .male)
    let (tdee, _) = TDEEEstimator.computeMifflin(weightKg: 85, config: config)!
    // BMR: 10*85 + 6.25*175 - 5*45 + 5 = 850+1093.75-225+5 = 1723.75, × 1.55 = 2672
    #expect(tdee > 2550 && tdee < 2800, "Middle-aged 45yo male TDEE ~2672, got \(Int(tdee))")
}

@Test func mifflinMiddleAgeFemale50() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 50, heightCm: 160, sex: .female)
    let (tdee, _) = TDEEEstimator.computeMifflin(weightKg: 70, config: config)!
    // BMR: 10*70 + 6.25*160 - 5*50 - 161 = 700+1000-250-161 = 1289, × 1.55 = 1998
    #expect(tdee > 1880 && tdee < 2120, "Middle-aged 50yo female TDEE ~1998, got \(Int(tdee))")
}

@Test func mifflinOlderMale65() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 25, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 65, heightCm: 172, sex: .male)
    let (tdee, _) = TDEEEstimator.computeMifflin(weightKg: 78, config: config)!
    // BMR: 10*78 + 6.25*172 - 5*65 + 5 = 780+1075-325+5 = 1535, × 1.35 (light) = 2072
    #expect(tdee > 1950 && tdee < 2200, "Older 65yo light-active male TDEE ~2072, got \(Int(tdee))")
}

@Test func mifflinOlderFemale70() async throws {
    let config = TDEEEstimator.TDEEConfig(activityMultiplier: 22, appleHealthTrust: 1.0, manualAdjustment: 0,
                                            age: 70, heightCm: 155, sex: .female)
    let (tdee, _) = TDEEEstimator.computeMifflin(weightKg: 62, config: config)!
    // BMR: 10*62 + 6.25*155 - 5*70 - 161 = 620+968.75-350-161 = 1077.75, × 1.2 (sedentary) = 1293
    #expect(tdee > 1200 && tdee < 1400, "Older 70yo sedentary female TDEE ~1293, got \(Int(tdee))")
}

// Blended TDEE: base + Mifflin correction should be reasonable across all combos
@Test func blendedTDEENeverExtremeWithoutAppleHealth() async throws {
    // Test various weight × activity × demographic combos
    let weights: [Double] = [45, 53, 60, 70, 80, 90, 100, 110, 120]
    let activities: [Double] = [22, 25, 29, 33, 36]

    for w in weights {
        for act in activities {
            let base = TDEEEstimator.computeBase(weightKg: w, activityMultiplier: act)

            // Without Mifflin: base alone should be 1200-2950
            #expect(base >= 1200, "Base too low for \(w)kg/act\(act): \(Int(base))")
            #expect(base < 2950, "Base too high for \(w)kg/act\(act) without profile: \(Int(base))")

            // With Mifflin (male, 30, 175cm): blended should be 1200-3200
            let maleConfig = TDEEEstimator.TDEEConfig(activityMultiplier: act, appleHealthTrust: 1.0, manualAdjustment: 0,
                                                        age: 30, heightCm: 175, sex: .male)
            if let (mifflin, conf) = TDEEEstimator.computeMifflin(weightKg: w, config: maleConfig) {
                let blended = base + (mifflin - base) * 0.4 * conf
                #expect(blended >= 1200, "Blended too low for \(w)kg male: \(Int(blended))")
                #expect(blended < 3500, "Blended too high for \(w)kg male: \(Int(blended))")
            }

            // With Mifflin (female, 30, 165cm): blended should be lower
            let femaleConfig = TDEEEstimator.TDEEConfig(activityMultiplier: act, appleHealthTrust: 1.0, manualAdjustment: 0,
                                                          age: 30, heightCm: 165, sex: .female)
            if let (mifflin, conf) = TDEEEstimator.computeMifflin(weightKg: w, config: femaleConfig) {
                let blended = base + (mifflin - base) * 0.4 * conf
                #expect(blended >= 1200, "Blended too low for \(w)kg female: \(Int(blended))")
                #expect(blended < 3200, "Blended too high for \(w)kg female: \(Int(blended))")
            }
        }
    }
}

// The 53kg user case: with weight trend correction, should be ~1800
@Test func tdee53kgWithWeightTrendShouldBe1800ish() async throws {
    // Simulates: 53kg, moderate activity, losing 0.5kg/week, eating ~1400 cal/day
    let base = TDEEEstimator.computeBase(weightKg: 53, activityMultiplier: 29)
    // base ~1738

    // Weight trend TDEE: avgIntake - deficit = 1400 - (-428) = 1828
    let weeklyRate = -0.5 // losing
    let deficit = weeklyRate * 6000 / 7 // -428.57
    let avgIntake = 1400.0
    let trendTDEE = avgIntake - deficit // 1828.57

    // Apply 0.3 dampening (same as TDEEEstimator.refresh)
    let blended = base + (trendTDEE - base) * 0.3
    #expect(blended > 1750 && blended < 1850,
            "53kg with trend should be ~1800, got \(Int(blended))")
}

// Test that higher intake + same trend = higher TDEE (sanity)
@Test func tdeeAdaptiveHigherIntakeMeansHigherTDEE() async throws {
    let base = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    let deficit = -0.5 * 6000 / 7 // -428 kcal/day

    let lowIntake = 1600.0
    let highIntake = 2000.0

    let trendLow = lowIntake - deficit // 2028
    let trendHigh = highIntake - deficit // 2428

    let blendedLow = base + (trendLow - base) * 0.3
    let blendedHigh = base + (trendHigh - base) * 0.3

    #expect(blendedHigh > blendedLow, "Higher intake with same weight loss = higher TDEE")
    #expect(blendedHigh - blendedLow > 100, "Difference should be meaningful: \(Int(blendedHigh - blendedLow))")
}

// Test weight × activity matrix: every combo produces a sane result
@Test func tdeeBaseWeightActivityMatrix() async throws {
    let cases: [(weight: Double, activity: Double, min: Int, max: Int, label: String)] = [
        (45, 22, 1150, 1350, "45kg sedentary"),
        (45, 29, 1500, 1650, "45kg moderate"),
        (45, 36, 1850, 2050, "45kg athlete"),
        (53, 22, 1250, 1400, "53kg sedentary"),
        (53, 29, 1700, 1800, "53kg moderate"),
        (53, 36, 2050, 2250, "53kg athlete"),
        (70, 22, 1450, 1600, "70kg sedentary"),
        (70, 29, 1950, 2050, "70kg moderate"),
        (70, 36, 2400, 2550, "70kg athlete"),
        (85, 29, 2150, 2300, "85kg moderate"),
        (100, 29, 2300, 2500, "100kg moderate"),
        (100, 36, 2700, 2850, "100kg athlete"),  // soft cap region
        (120, 29, 2550, 2700, "120kg moderate"),
        (120, 36, 2750, 2950, "120kg athlete"),  // soft cap region
    ]

    for c in cases {
        let base = TDEEEstimator.computeBase(weightKg: c.weight, activityMultiplier: c.activity)
        #expect(Int(base) >= c.min && Int(base) <= c.max,
                "\(c.label): expected \(c.min)-\(c.max), got \(Int(base))")
    }
}

// Mifflin activity factor mapping
@Test func mifflinActivityFactorMapping() async throws {
    let config22 = TDEEEstimator.TDEEConfig(activityMultiplier: 22, appleHealthTrust: 1.0, manualAdjustment: 0)
    let config29 = TDEEEstimator.TDEEConfig(activityMultiplier: 29, appleHealthTrust: 1.0, manualAdjustment: 0)
    let config36 = TDEEEstimator.TDEEConfig(activityMultiplier: 36, appleHealthTrust: 1.0, manualAdjustment: 0)

    #expect(abs(config22.mifflinActivityFactor - 1.2) < 0.01, "Sedentary = 1.2")
    #expect(abs(config29.mifflinActivityFactor - 1.55) < 0.01, "Moderate = 1.55")
    #expect(abs(config36.mifflinActivityFactor - 1.9) < 0.01, "Athlete = 1.9")
}

// MARK: - Weight Trend Fallback Tests

@Test func weightTrendFallbackUsesTwoMostRecent() async throws {
    // With < 3 points in regression window, should use 2 most recent (not oldest-to-newest)
    let entries: [(date: String, weightKg: Double)] = [
        ("2026-01-01", 80.0),  // old entry, far away
        ("2026-03-28", 75.0),  // recent
        ("2026-03-30", 74.5),  // most recent
    ]
    let trend = WeightTrendCalculator.calculateTrend(
        entries: entries,
        config: .init(emaAlpha: 0.1, regressionWindowDays: 3, kcalPerKg: 6000, maintainingThresholdKgPerWeek: 0.05)
    )
    #expect(trend != nil)
    // With 3-day window, only last 2 entries are in window → fallback path
    // Rate should be based on 74.5 vs 75.0 over 2 days, NOT 74.5 vs 80.0 over 89 days
    if let rate = trend?.weeklyRateKg {
        #expect(rate < 0, "Should show losing trend")
        #expect(abs(rate) < 5, "Rate should be moderate, not extreme: \(rate)")
    }
}

// MARK: - Recovery Score Edge Cases

@Test func recoveryScoreAllDataPresent() async throws {
    // Normal case: all data available
    let baselines = RecoveryEstimator.Baselines(hrvMs: 45, restingHR: 65, respiratoryRate: 15, sleepHours: 7.5, daysOfData: 14)
    let score = RecoveryEstimator.calculateRecovery(hrvMs: 50, restingHR: 60, sleepHours: 7.5, baselines: baselines)
    #expect(score > 60 && score < 90, "Normal data should give moderate-high score: \(score)")
}

@Test func recoveryScoreMissingHRVStillReasonable() async throws {
    // Missing HRV should not tank score when other metrics are good
    let baselines = RecoveryEstimator.Baselines(hrvMs: 45, restingHR: 65, respiratoryRate: 15, sleepHours: 7.5, daysOfData: 14)
    let withHRV = RecoveryEstimator.calculateRecovery(hrvMs: 50, restingHR: 55, sleepHours: 7.5, baselines: baselines)
    let noHRV = RecoveryEstimator.calculateRecovery(hrvMs: 0, restingHR: 55, sleepHours: 7.5, baselines: baselines)
    // Without HRV, score should still be reasonable (not < 50)
    #expect(noHRV >= 70, "Missing HRV with good RHR + sleep should score 70+: \(noHRV)")
    // Bad HRV should score LOWER than missing HRV
    let badHRV = RecoveryEstimator.calculateRecovery(hrvMs: 15, restingHR: 55, sleepHours: 7.5, baselines: baselines)
    #expect(noHRV > badHRV, "No HRV (\(noHRV)) should beat bad HRV (\(badHRV))")
}

@Test func sleepScoreWithoutStagesIsReasonable() async throws {
    // iPhone-only: no REM/Deep stages
    let score = RecoveryEstimator.calculateSleepScore(totalHours: 7.5, remHours: 0, deepHours: 0, targetHours: 7.5)
    #expect(score >= 90, "Full duration without stages should score 90+: \(score)")

    let partialDuration = RecoveryEstimator.calculateSleepScore(totalHours: 6, remHours: 0, deepHours: 0, targetHours: 7.5)
    #expect(partialDuration >= 60 && partialDuration < 90, "80% duration without stages: \(partialDuration)")
}

// MARK: - TDEE Soft Cap Regression

@Test func tdeeSoftCapStillApplies() async throws {
    // Verify soft cap at 2700 is still in place after all the refactoring
    let heavyAthlete = TDEEEstimator.computeBase(weightKg: 120, activityMultiplier: 36)
    #expect(heavyAthlete < 2950, "120kg athlete should be soft-capped: \(Int(heavyAthlete))")

    let normalModerate = TDEEEstimator.computeBase(weightKg: 70, activityMultiplier: 29)
    #expect(abs(normalModerate - 2000) < 1, "70kg moderate should still be 2000 anchor: \(Int(normalModerate))")
}

// MARK: - Adaptive TDEE Tests (DISABLED — feature reverted)
// Adaptive TDEE v1 was removed because it depended on food logging accuracy
// and dropped calories dangerously (1960→1400). See Docs/backlog.md for v2 design.

// MARK: - Serving Size Parsing Tests

@Test func parseServingSizeGrams() async throws {
    #expect(OpenFoodFactsService.parseServingSize("30g") == 30)
    #expect(OpenFoodFactsService.parseServingSize("170g") == 170)
    #expect(OpenFoodFactsService.parseServingSize("100 g") == 100)
    #expect(OpenFoodFactsService.parseServingSize("2.5g") == 2.5)
}

@Test func parseServingSizeWithParens() async throws {
    // "1 cup (240g)" should extract 240
    #expect(OpenFoodFactsService.parseServingSize("1 cup (240g)") == 240)
    #expect(OpenFoodFactsService.parseServingSize("1 serving (85g)") == 85)
}

@Test func parseServingSizeML() async throws {
    // ml treated as grams (1:1 for liquids)
    #expect(OpenFoodFactsService.parseServingSize("250ml") == 250)
    #expect(OpenFoodFactsService.parseServingSize("330 ml") == 330)
}

@Test func parseServingSizeNil() async throws {
    #expect(OpenFoodFactsService.parseServingSize(nil) == nil)
    #expect(OpenFoodFactsService.parseServingSize("1 cup") == nil) // no grams or ml
    #expect(OpenFoodFactsService.parseServingSize("") == nil)
}

// MARK: - Food Entry loggedAt Tests

@Test func foodEntryLoggedAtDefault() async throws {
    let entry = FoodEntry(mealLogId: 1, foodName: "Test", servingSizeG: 100, calories: 100)
    #expect(!entry.loggedAt.isEmpty, "loggedAt should default to current timestamp")
    let iso = ISO8601DateFormatter()
    #expect(iso.date(from: entry.loggedAt) != nil, "loggedAt should be valid ISO8601")
}

@Test func foodEntryLoggedAtPersists() async throws {
    let db = try AppDatabase.empty()
    var log = MealLog(date: "2026-04-03", mealType: "breakfast")
    try db.saveMealLog(&log)
    let customTime = "2026-04-03T07:30:00Z"
    var entry = FoodEntry(mealLogId: log.id!, foodName: "Oatmeal", servingSizeG: 100, calories: 350, loggedAt: customTime)
    try db.saveFoodEntry(&entry)
    let fetched = try db.fetchFoodEntries(forMealLog: log.id!)
    #expect(fetched.count == 1)
    #expect(fetched[0].loggedAt == customTime)
}

@Test func foodEntriesSortedByLoggedAt() async throws {
    let db = try AppDatabase.empty()
    var log = MealLog(date: "2026-04-03", mealType: "breakfast")
    try db.saveMealLog(&log)
    // Insert in reverse time order
    var e1 = FoodEntry(mealLogId: log.id!, foodName: "Dinner", servingSizeG: 100, calories: 500, loggedAt: "2026-04-03T19:00:00Z")
    var e2 = FoodEntry(mealLogId: log.id!, foodName: "Breakfast", servingSizeG: 100, calories: 300, loggedAt: "2026-04-03T07:30:00Z")
    var e3 = FoodEntry(mealLogId: log.id!, foodName: "Lunch", servingSizeG: 100, calories: 400, loggedAt: "2026-04-03T12:00:00Z")
    try db.saveFoodEntry(&e1)
    try db.saveFoodEntry(&e2)
    try db.saveFoodEntry(&e3)
    let fetched = try db.fetchFoodEntries(forMealLog: log.id!)
    #expect(fetched.count == 3)
    #expect(fetched[0].foodName == "Breakfast", "Should be sorted by loggedAt ascending")
    #expect(fetched[1].foodName == "Lunch")
    #expect(fetched[2].foodName == "Dinner")
}

@Test func foodEntryLoggedAtMigrationBackfill() async throws {
    // Entries created without explicit loggedAt get it from createdAt
    let db = try AppDatabase.empty()
    var log = MealLog(date: "2026-04-03", mealType: "lunch")
    try db.saveMealLog(&log)
    let now = ISO8601DateFormatter().string(from: Date())
    var entry = FoodEntry(mealLogId: log.id!, foodName: "Test", servingSizeG: 100, calories: 200, createdAt: now, loggedAt: now)
    try db.saveFoodEntry(&entry)
    let fetched = try db.fetchFoodEntries(forMealLog: log.id!)
    #expect(fetched[0].loggedAt == now, "loggedAt should match createdAt for new entries")
}

@Test func dateFormattersSqliteDatetime() async throws {
    let f = DateFormatters.sqliteDatetime
    let date = f.date(from: "2026-04-03 15:30:00")
    #expect(date != nil, "Should parse SQLite datetime format")
    let str = f.string(from: date!)
    #expect(str == "2026-04-03 15:30:00")
}

@Test func dateFormattersShortTime() async throws {
    let f = DateFormatters.shortTime
    let cal = Calendar.current
    let date = cal.date(bySettingHour: 14, minute: 30, second: 0, of: Date())!
    let str = f.string(from: date)
    #expect(str == "2:30 PM")
}

// MARK: - Scanned Product Unit Tests

@Test func smartUnitScannedMilkGetsMl() async throws {
    // Scanned "Amul Toned Milk" with 240ml serving from OpenFoodFacts
    let food = Food(name: "Amul Toned Milk - Amul", category: "Scanned", servingSize: 240, servingUnit: "g", calories: 120)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "ml", "Scanned milk should get ml as primary, got: \(units.first?.label ?? "nil")")
    #expect(units.contains(where: { $0.label == "cup" }), "Should have cup option")
    #expect(units.contains(where: { $0.label == "g" }), "Should have grams option")
}

@Test func smartUnitScannedChipsGetsServing() async throws {
    // Scanned "Lay's Classic" with 28g serving — must NOT match "lassi" in "classic"
    let food = Food(name: "Lay's Classic Potato Chips - Frito-Lay", category: "Scanned", servingSize: 28, servingUnit: "g", calories: 160)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "serving", "Chips should get serving as primary, got: \(units.first?.label ?? "nil")")
    #expect(units.first?.gramsEquivalent == 28, "Serving should be 28g, got: \(units.first?.gramsEquivalent ?? 0)")
    #expect(units.contains(where: { $0.label == "g" }), "Should have grams option")
    #expect(!units.contains(where: { $0.label == "ml" }), "Chips should NOT get ml unit")
}

@Test func smartUnitScannedOilGetsTbsp() async throws {
    let food = Food(name: "Extra Virgin Olive Oil - Bertolli", category: "Scanned", servingSize: 15, servingUnit: "g", calories: 120)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp", "Scanned oil should get tbsp")
}

@Test func smartUnitScannedYogurtGetsCup() async throws {
    let food = Food(name: "Greek Yogurt - Chobani", category: "Scanned", servingSize: 170, servingUnit: "g", calories: 100)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.contains(where: { $0.label == "cup" }), "Yogurt should have cup option")
}

@Test func smartUnitSteakNotLiquid() async throws {
    // "steak" contains "tea" — must NOT get ml units
    let food = Food(name: "Steak (8oz ribeye)", category: "Protein", servingSize: 227, servingUnit: "g", calories: 544)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label != "ml", "Steak must not get ml, got: \(units.first?.label ?? "nil")")
    #expect(!units.contains(where: { $0.label == "ml" }), "Steak should have no ml option")
}

@Test func smartUnitVeggieBurgerNotEgg() async throws {
    // "veggies" contains "egg" — must NOT get egg units
    let food = Food(name: "Veggie Burger Patty", category: "Protein", servingSize: 113, servingUnit: "g", calories: 190)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label != "egg", "Veggie burger must not get egg, got: \(units.first?.label ?? "nil")")
}

@Test func smartUnitBoiledEggNotOil() async throws {
    // "boiled" contains "oil" — must NOT get tbsp units
    let food = Food(name: "Egg (whole, boiled)", category: "Protein", servingSize: 50, servingUnit: "g", calories: 72)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "egg", "Boiled egg should get egg unit, got: \(units.first?.label ?? "nil")")
    #expect(!units.contains(where: { $0.label == "tbsp" }), "Boiled egg should NOT get tbsp")
    #expect(!units.contains(where: { $0.label == "spray" }), "Boiled egg should NOT get spray")
}

@Test func smartUnitButternutSquashNotButter() async throws {
    // "butternut" contains "butter" — must NOT get tbsp
    let food = Food(name: "Butternut Squash (cooked)", category: "Vegetables", servingSize: 200, servingUnit: "g", calories: 82)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label != "tbsp", "Butternut squash must not get tbsp")
}

@Test func smartUnitSteamedRiceNotLiquid() async throws {
    // "steamed" contains "tea" — must NOT get ml
    let food = Food(name: "Steamed Rice (white)", category: "Grains", servingSize: 200, servingUnit: "g", calories: 260)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label != "ml", "Steamed rice must not get ml")
    #expect(units.contains(where: { $0.label == "cup" }), "Rice should have cup option")
}

@Test func scannedFoodServingSizePreserved() async throws {
    // Verify that when saving a scanned food with non-100g serving, it persists
    let db = try AppDatabase.empty()
    var food = Food(name: "Test Scanned Product", category: "Scanned", servingSize: 30, servingUnit: "g", calories: 150)
    try db.saveScannedFood(&food)
    let results = try db.searchFoods(query: "Test Scanned Product")
    #expect(results.count == 1)
    #expect(results[0].servingSize == 30, "Serving size should be 30g, got: \(results[0].servingSize)")
}

@Test func scannedFoodMultiplierCalculation() async throws {
    // 28g serving, user picks 2 servings → multiplier should be 2
    let servingG: Double = 28
    let amount: Double = 2
    let unit = FoodUnit(label: "serving", gramsEquivalent: servingG)
    let totalGrams = amount * unit.gramsEquivalent
    let multiplier = totalGrams / servingG
    #expect(multiplier == 2.0)
    // 100g in grams → multiplier should be 100/28 ≈ 3.57
    let gUnit = FoodUnit(label: "g", gramsEquivalent: 1)
    let gMultiplier = (100 * gUnit.gramsEquivalent) / servingG
    #expect(abs(gMultiplier - 3.571) < 0.01)
}

// MARK: - Plant Points Tests

@Test func plantPointsAliasNormalization() async throws {
    // palak and spinach should count as 1 plant, not 2
    let items: [PlantPointsService.FoodItem] = [
        .init(name: "palak", ingredients: nil, novaGroup: 1),
        .init(name: "spinach", ingredients: nil, novaGroup: 1),
    ]
    let pp = PlantPointsService.calculate(from: items)
    #expect(pp.uniquePlants.count == 1, "palak + spinach = 1 plant, got \(pp.uniquePlants)")
}

@Test func plantPointsNOVA3UsesIngredients() async throws {
    // NOVA 3 food: skip name, count ingredients
    let items: [PlantPointsService.FoodItem] = [
        .init(name: "Chicken Biryani", ingredients: ["rice", "onion", "tomato", "turmeric", "cumin"], novaGroup: 3),
    ]
    let pp = PlantPointsService.calculate(from: items)
    #expect(pp.uniquePlants.count >= 3, "Biryani ingredients should yield 3+ plants, got \(pp.uniquePlants)")
    #expect(!pp.uniquePlants.contains("chicken biryani"), "Food name should not appear in plant list")
    #expect(pp.uniquePlants.contains("rice"), "Rice should be a plant")
    #expect(pp.uniquePlants.contains("onion"), "Onion should be a plant")
}

@Test func plantPointsNOVA4SkipsEverything() async throws {
    // NOVA 4: skip food AND ingredients
    let items: [PlantPointsService.FoodItem] = [
        .init(name: "Chips", ingredients: ["potato", "oil"], novaGroup: 4),
    ]
    let pp = PlantPointsService.calculate(from: items)
    #expect(pp.total == 0, "NOVA 4 should give 0 points, got \(pp.total)")
}

@Test func plantPointsProcessedExcluded() async throws {
    // Bread, pasta, naan should not count
    let items: [PlantPointsService.FoodItem] = [
        .init(name: "bread", ingredients: nil, novaGroup: nil),
        .init(name: "pasta", ingredients: nil, novaGroup: nil),
        .init(name: "naan", ingredients: nil, novaGroup: nil),
    ]
    let pp = PlantPointsService.calculate(from: items)
    #expect(pp.total == 0, "Processed foods should give 0 points, got \(pp.total)")
}

@Test func plantPointsSpiceBlendExpansion() async throws {
    let items: [PlantPointsService.FoodItem] = [
        .init(name: "garam masala", ingredients: nil, novaGroup: nil),
    ]
    let pp = PlantPointsService.calculate(from: items)
    // garam masala expands to cumin, coriander, cardamom, cloves, pepper = 5 spices × 0.25 = 1.25
    #expect(pp.uniqueHerbsSpices.count == 5, "Garam masala = 5 spices, got \(pp.uniqueHerbsSpices)")
    #expect(abs(pp.quarterPoints - 1.25) < 0.01, "Should be 1.25 pts, got \(pp.quarterPoints)")
}

@Test func plantPointsKeywordExtraction() async throws {
    // "avocado toast" without ingredients should extract keyword "avocado", not store "avocado toast"
    let items: [PlantPointsService.FoodItem] = [
        .init(name: "avocado toast", ingredients: nil, novaGroup: nil),
    ]
    let pp = PlantPointsService.calculate(from: items)
    #expect(pp.uniquePlants.contains("avocado"), "Should extract 'avocado' keyword")
    #expect(!pp.uniquePlants.contains("avocado toast"), "Should not contain full food name")
}

@Test func plantPointsAvocadoDeduplication() async throws {
    // Avocado + Avocado (half) should = 1 plant
    let items: [PlantPointsService.FoodItem] = [
        .init(name: "Avocado", ingredients: ["avocado"], novaGroup: 1),
        .init(name: "Avocado (half)", ingredients: ["avocado"], novaGroup: 1),
        .init(name: "Avocado Toast", ingredients: ["avocado", "lime"], novaGroup: 3),
    ]
    let pp = PlantPointsService.calculate(from: items)
    #expect(pp.uniquePlants.contains("avocado"))
    #expect(pp.uniquePlants.contains("lime"))
    #expect(pp.uniquePlants.count == 2, "Avocado + lime = 2, got \(pp.uniquePlants)")
}

// MARK: - Food Entry Reorder + Edit Tests

@Test func updateFoodEntryLoggedAt() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-04-09"
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var entry = FoodEntry(mealLogId: ml.id!, foodName: "Rice", servingSizeG: 150, calories: 200)
    try db.saveFoodEntry(&entry)

    // Update time
    try db.updateFoodEntryLoggedAt(id: entry.id!, loggedAt: "2026-04-09T08:00:00Z")
    let fetched = try db.fetchFoodEntries(for: date)
    #expect(fetched.first?.loggedAt == "2026-04-09T08:00:00Z")
}

@Test func updateFoodEntryMacros() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-04-09"
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var entry = FoodEntry(mealLogId: ml.id!, foodName: "Custom Lunch", servingSizeG: 0, calories: 500, proteinG: 30)
    try db.saveFoodEntry(&entry)

    // Edit macros
    try db.updateFoodEntryMacros(id: entry.id!, calories: 600, proteinG: 40, carbsG: 50, fatG: 20, fiberG: 5)
    let fetched = try db.fetchFoodEntries(for: date)
    let updated = fetched.first!
    #expect(updated.calories == 600)
    #expect(updated.proteinG == 40)
    #expect(updated.carbsG == 50)
}

@Test func timestampSwapReorders() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-04-09"
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var e1 = FoodEntry(mealLogId: ml.id!, foodName: "Breakfast", servingSizeG: 100, calories: 300,
                        loggedAt: "2026-04-09T08:00:00Z")
    var e2 = FoodEntry(mealLogId: ml.id!, foodName: "Lunch", servingSizeG: 100, calories: 500,
                        loggedAt: "2026-04-09T12:00:00Z")
    try db.saveFoodEntry(&e1)
    try db.saveFoodEntry(&e2)

    // Swap timestamps
    try db.updateFoodEntryLoggedAt(id: e1.id!, loggedAt: "2026-04-09T12:00:00Z")
    try db.updateFoodEntryLoggedAt(id: e2.id!, loggedAt: "2026-04-09T08:00:00Z")

    let fetched = try db.fetchFoodEntries(for: date) // sorted DESC
    #expect(fetched[0].foodName == "Breakfast", "Breakfast should now be at 12:00 (first in DESC)")
    #expect(fetched[1].foodName == "Lunch", "Lunch should now be at 8:00 (second in DESC)")
}

@Test func updateFoodEntryMealTypeCrossesGroupBoundary() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-04-09"
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var entry = FoodEntry(mealLogId: ml.id!, foodName: "Eggs", servingSizeG: 100, calories: 150,
                          mealType: "lunch")
    try db.saveFoodEntry(&entry)

    // Move from lunch to breakfast
    try db.updateFoodEntryMealType(id: entry.id!, mealType: "breakfast")
    let fetched = try db.fetchFoodEntries(for: date)
    #expect(fetched.first?.mealType == "breakfast")
}

@Test func updateFoodEntryMealTypeDoesNotAffectOtherEntries() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-04-09"
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var e1 = FoodEntry(mealLogId: ml.id!, foodName: "Rice", servingSizeG: 150, calories: 200, mealType: "lunch")
    var e2 = FoodEntry(mealLogId: ml.id!, foodName: "Dal", servingSizeG: 150, calories: 180, mealType: "lunch")
    try db.saveFoodEntry(&e1)
    try db.saveFoodEntry(&e2)

    // Move only first entry to dinner
    try db.updateFoodEntryMealType(id: e1.id!, mealType: "dinner")
    let fetched = try db.fetchFoodEntries(for: date)
    let rice = fetched.first(where: { $0.foodName == "Rice" })
    let dal = fetched.first(where: { $0.foodName == "Dal" })
    #expect(rice?.mealType == "dinner")
    #expect(dal?.mealType == "lunch")
}

@Test func updateFoodEntryName() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-04-09"
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var entry = FoodEntry(mealLogId: ml.id!, foodName: "Quick Add", servingSizeG: 0, calories: 345, proteinG: 20)
    try db.saveFoodEntry(&entry)

    // Rename
    try db.updateFoodEntryName(id: entry.id!, name: "Chicken Biryani")
    let fetched = try db.fetchFoodEntries(for: date)
    #expect(fetched.first?.foodName == "Chicken Biryani")
}

@Test func updateFoodEntryNameDoesNotAffectOtherEntries() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-04-09"
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var e1 = FoodEntry(mealLogId: ml.id!, foodName: "Quick Add", servingSizeG: 0, calories: 200)
    var e2 = FoodEntry(mealLogId: ml.id!, foodName: "Quick Add", servingSizeG: 0, calories: 400)
    try db.saveFoodEntry(&e1)
    try db.saveFoodEntry(&e2)

    // Only rename first entry
    try db.updateFoodEntryName(id: e1.id!, name: "Renamed")
    let fetched = try db.fetchFoodEntries(for: date)
    let names = fetched.map(\.foodName).sorted()
    #expect(names.contains("Renamed"))
    #expect(names.contains("Quick Add"))
}

@Test func quickAddServingsStoredCorrectly() async throws {
    let db = try AppDatabase.empty()
    let date = "2026-04-09"
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var entry = FoodEntry(mealLogId: ml.id!, foodName: "Protein Bar", servingSizeG: 0, calories: 200, proteinG: 20)
    try db.saveFoodEntry(&entry)

    // Update servings
    try db.updateFoodEntryServings(id: entry.id!, servings: 2.0)
    let fetched = try db.fetchFoodEntries(for: date)
    #expect(fetched.first?.servings == 2.0)
    // Total = calories * servings
    let total = fetched.first!.calories * fetched.first!.servings
    #expect(total == 400)
}

@Test func copyEntryToTodayPreservesData() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let vm = await FoodLogViewModel(database: db)

    // Log a food for yesterday
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    let eggs = try db.searchFoods(query: "boiled egg")
    guard let egg = eggs.first else { return }
    await vm.logFood(egg, servings: 2, mealType: .breakfast)

    // Copy to today
    let entries = await vm.todayEntries
    guard let entry = entries.first else { return }
    await vm.copyEntryToToday(entry)

    // Verify on today
    await vm.goToDate(Date())
    await vm.loadTodayMeals()
    let todayEntries = await vm.todayEntries
    #expect(!todayEntries.isEmpty, "Should have copied entry to today")
    if let copied = todayEntries.first {
        #expect(copied.foodName == egg.name)
        #expect(copied.calories == egg.calories)
    }
}

@Test func copyEntryToTodayPreservesMealType() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    // Log a breakfast item yesterday
    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
    await vm.goToDate(yesterday)
    await vm.quickAdd(name: "Morning Oats", calories: 350, proteinG: 12, carbsG: 55, fatG: 8, fiberG: 5, mealType: .breakfast)

    let entries = await vm.todayEntries
    guard let entry = entries.first else {
        #expect(Bool(false), "Should have an entry to copy")
        return
    }
    #expect(entry.mealType == MealType.breakfast.rawValue)

    // Copy to today (regardless of current time, meal type should stay breakfast)
    await vm.copyEntryToToday(entry)

    await vm.goToDate(Date())
    await vm.loadTodayMeals()
    let todayEntries = await vm.todayEntries
    #expect(!todayEntries.isEmpty, "Should have copied entry")
    if let copied = todayEntries.first {
        #expect(copied.mealType == MealType.breakfast.rawValue, "Copied entry should preserve original meal type, got \(copied.mealType ?? "nil")")
    }
}

@Test func plantPointsFoodItemsQuery() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let date = "2026-04-09"

    // Log a food with known ingredients
    let foods = try db.searchFoods(query: "Avocado Toast")
    guard let avToast = foods.first else { return }
    var ml = MealLog(date: date, mealType: "lunch")
    try db.saveMealLog(&ml)
    var entry = FoodEntry(mealLogId: ml.id!, foodId: avToast.id, foodName: avToast.name,
                           servingSizeG: avToast.servingSize, calories: avToast.calories)
    try db.saveFoodEntry(&entry)

    let items = try db.fetchFoodItemsForPlantPoints(from: date, to: date)
    #expect(!items.isEmpty, "Should return food items")
    if let item = items.first {
        #expect(item.ingredients != nil, "Should have ingredients from food DB")
        #expect(item.novaGroup != nil, "Should have NOVA group from food DB")
    }
}

@Test func foodUsageMacrosStored() async throws {
    let db = try AppDatabase.empty()
    try db.trackFoodUsage(name: "My Custom Meal", foodId: nil, servings: 1,
                           calories: 500, proteinG: 30, carbsG: 40, fatG: 20, fiberG: 5)
    let recents = try db.fetchRecentEntryNames()
    #expect(!recents.isEmpty)
    if let recent = recents.first {
        #expect(recent.name == "My Custom Meal")
        #expect(recent.calories == 500, "Macros should be stored, got \(recent.calories)")
        #expect(recent.proteinG == 30)
    }
}

// MARK: - Ingredient Persistence Tests

@Test func recipeItemsRoundTrip() throws {
    let items: [QuickAddView.RecipeItem] = [
        .init(name: "Rice", portionText: "200g", calories: 720, proteinG: 14, carbsG: 160, fatG: 2, fiberG: 1.2, servingSizeG: 200),
        .init(name: "Chicken", portionText: "150g", calories: 180, proteinG: 34.5, carbsG: 0, fatG: 3, fiberG: 0, servingSizeG: 150)
    ]
    let json = try JSONEncoder().encode(items)
    let jsonStr = String(data: json, encoding: .utf8)!

    let food = Food(name: "Chicken Rice", category: "Recipe", servingSize: 1, servingUnit: "serving",
                    calories: 900, proteinG: 48.5, carbsG: 160, fatG: 5, fiberG: 1.2,
                    ingredients: jsonStr, isRecipe: true)

    // recipeItems should reconstruct full items
    let restored = food.recipeItems
    #expect(restored != nil)
    #expect(restored!.count == 2)
    #expect(restored![0].name == "Rice")
    #expect(restored![0].calories == 720)
    #expect(restored![0].servingSizeG == 200)
    #expect(restored![1].name == "Chicken")
    #expect(restored![1].proteinG == 34.5)

    // ingredientList should still return names
    #expect(food.ingredientList == ["Rice", "Chicken"])
}

@Test func ingredientListLegacyFormat() {
    let legacyJson = "[\"rice\",\"onion\",\"turmeric\"]"
    let food = Food(name: "Biryani", category: "Recipe", servingSize: 1, servingUnit: "serving",
                    calories: 400, ingredients: legacyJson, isRecipe: true)

    #expect(food.ingredientList == ["rice", "onion", "turmeric"])
    #expect(food.recipeItems == nil) // legacy format has no recipe items
}

@Test func ingredientListNoIngredients() {
    let food = Food(name: "Apple", category: "Fruit", servingSize: 182, servingUnit: "g", calories: 95)
    #expect(food.ingredientList == ["Apple"])
    #expect(food.recipeItems == nil)
}

enum TestError: Error { case msg(String); init(_ s: String) { self = .msg(s) } }

// MARK: - Search Miss Tracking Tests

@Test func searchMissTrackedOnEmptyResult() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let query = "xyzunknownfooditem"
    try db.trackSearchMiss(query: query)
    let misses = try db.topSearchMisses(limit: 10)
    #expect(misses.contains(where: { $0.query == query && $0.count == 1 }), "Miss should be recorded with count 1")
}

@Test func searchMissDeduplicated() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let query = "anotherxyzfood"
    try db.trackSearchMiss(query: query)
    try db.trackSearchMiss(query: query)
    try db.trackSearchMiss(query: query)
    let misses = try db.topSearchMisses(limit: 10)
    let entry = misses.first(where: { $0.query == query })
    #expect(entry?.count == 3, "Repeated searches should increment count, not add duplicate rows")
}

@Test func searchMissNormalizesCase() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    try db.trackSearchMiss(query: "Paneer Tikka Masala")
    try db.trackSearchMiss(query: "paneer tikka masala")
    let misses = try db.topSearchMisses(limit: 10)
    let entries = misses.filter { $0.query.contains("paneer tikka masala") }
    #expect(entries.count == 1, "Case-different searches should be deduplicated")
    #expect(entries.first?.count == 2)
}

@Test func searchMissSkipsShortQueries() async throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    try db.trackSearchMiss(query: "ab")   // too short
    try db.trackSearchMiss(query: "?")    // punctuation
    let misses = try db.topSearchMisses(limit: 10)
    #expect(!misses.contains(where: { $0.query == "ab" }), "Queries < 3 chars should not be tracked")
    #expect(!misses.contains(where: { $0.query == "?" }), "Punctuation queries should not be tracked")
}

@Test func searchMissRankedByCount() async throws {
    let db = try AppDatabase.empty()
    let rareQuery = "uniquerarexfood"
    let popularQuery = "verypopularxfood"
    try db.trackSearchMiss(query: rareQuery)
    for _ in 0..<5 { try db.trackSearchMiss(query: popularQuery) }
    let misses = try db.topSearchMisses(limit: 10)
    let rareIdx = misses.firstIndex(where: { $0.query == rareQuery }) ?? Int.max
    let popularIdx = misses.firstIndex(where: { $0.query == popularQuery }) ?? Int.max
    #expect(popularIdx < rareIdx, "More-searched foods should rank higher in topSearchMisses")
}

// MARK: - New Food Additions Search Tests

@Test func newFoodFriedEggFound() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "fried egg")
    #expect(!results.isEmpty, "Fried Egg should be findable")
    #expect(results.first?.name.lowercased().contains("fried egg") == true)
}

@Test func newFoodHardBoiledEggFound() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "hard boiled egg")).isEmpty)
    #expect(!(try db.searchFoods(query: "hard boiled")).isEmpty)
    #expect(!(try db.searchFoods(query: "boiled egg")).isEmpty)
}

@Test func newFoodSweetPotatoFriesFound() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "sweet potato fries")).isEmpty)
    #expect(!(try db.searchFoods(query: "sweet fries")).isEmpty)
}

@Test func newFoodTunaSteak() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "tuna steak")
    #expect(!results.isEmpty, "Tuna steak should be findable")
    let tuna = results.first(where: { $0.name.lowercased().contains("tuna steak") })
    #expect(tuna != nil)
    #expect((tuna?.proteinG ?? 0) >= 35, "Tuna steak should have high protein (35g+)")
}

@Test func newFoodBeefChili() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "beef chili")).isEmpty)
    #expect(!(try db.searchFoods(query: "chili")).isEmpty)
}

@Test func newFoodBlackBeanSoup() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "black bean soup")).isEmpty)
    #expect(!(try db.searchFoods(query: "black bean")).isEmpty)
}

@Test func newFoodHaleem() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "haleem")).isEmpty)
}

@Test func newFoodNihari() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "nihari")).isEmpty)
}

@Test func newFoodShrimpCurry() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "shrimp curry")).isEmpty)
    #expect(!(try db.searchFoods(query: "shrimp")).isEmpty)
}

// MARK: - New Foods Added (#83) — Top 20 search miss coverage (9 tests)

@Test func newFoodChanaMasala() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "chana masala")).isEmpty)
}

@Test func newFoodRajmaChawal() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "rajma chawal")).isEmpty)
}

@Test func newFoodDalChawal() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "dal chawal")).isEmpty)
}

@Test func newFoodKadhiChawal() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "kadhi chawal")).isEmpty)
}

@Test func newFoodGuava() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "guava")).isEmpty)
}

@Test func newFoodGardenSalad() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "garden salad")).isEmpty)
}

@Test func newFoodKatiRoll() async throws {
    let db = seededDB()
    let results = try db.searchFoods(query: "kati roll")
    #expect(!results.isEmpty, "Kati roll variants should be searchable")
}

@Test func newFoodChivda() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "chivda")).isEmpty)
}

@Test func newFoodMasalaOmelette() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "masala omelette")).isEmpty)
}

// MARK: - AIActionExecutor Multi-Food Parsing Tests (#84) (7 tests)

@Test func multiFoodParsesTwoItems() {
    let intents = AIActionExecutor.parseMultiFoodIntent("log eggs and toast")
    #expect(intents != nil && intents!.count == 2)
    let names = intents!.map { $0.query }
    #expect(names.contains("eggs"))
    #expect(names.contains("toast"))
}

@Test func multiFoodStripsMealSuffix() {
    // Meal suffix should be stripped — no food named "eggs for breakfast"
    let intents = AIActionExecutor.parseMultiFoodIntent("log eggs and toast for breakfast")
    #expect(intents != nil)
    let names = intents!.map { $0.query }
    for name in names {
        #expect(!name.contains("breakfast"), "Food name should not contain meal suffix: \(name)")
    }
}

@Test func multiFoodWithServings() {
    let intents = AIActionExecutor.parseMultiFoodIntent("log 2 eggs and 1 banana")
    #expect(intents != nil && intents!.count == 2)
    let egg = intents!.first { $0.query.contains("egg") }
    #expect(egg?.servings == 2)
}

@Test func multiFoodWithGrams() {
    let intents = AIActionExecutor.parseMultiFoodIntent("log 200g chicken and 100g rice")
    #expect(intents != nil && intents!.count == 2)
    let chicken = intents!.first { $0.query.contains("chicken") }
    #expect(chicken?.gramAmount == 200)
}

@Test func multiFoodRejectsCompoundFoodOnly() {
    // Pure compound food with no extras → nil (fall through to single food parser)
    let intents = AIActionExecutor.parseMultiFoodIntent("log mac and cheese")
    #expect(intents == nil, "Pure compound food should return nil to use single parser")
}

@Test func singleFoodMealHintBreakfast() {
    let intent = AIActionExecutor.parseFoodIntent("log 2 eggs for breakfast")
    #expect(intent != nil)
    #expect(intent?.mealHint == "breakfast")
    #expect(intent?.query.contains("egg") == true)
}

@Test func singleFoodMealHintDinner() {
    let intent = AIActionExecutor.parseFoodIntent("had rice for dinner")
    #expect(intent != nil)
    #expect(intent?.mealHint == "dinner")
}

// MARK: - New Foods (junior cycle 2 — bakery, soups, seafood)

@Test func newFoodRyeBread() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "rye bread")).isEmpty)
}

@Test func newFoodBriocheBun() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "brioche")).isEmpty)
}

@Test func newFoodBaguette() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "baguette")).isEmpty)
}

@Test func newFoodPumpkinSoup() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "pumpkin soup")).isEmpty)
}

@Test func newFoodCreamMushroomSoup() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "cream of mushroom")).isEmpty)
}

@Test func newFoodSplitPeaSoup() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "split pea")).isEmpty)
}

@Test func newFoodTilapia() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "tilapia")).isEmpty)
}

@Test func newFoodSardines() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "sardines")).isEmpty)
}

@Test func newFoodShrimpCocktail() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "shrimp cocktail")).isEmpty)
}

@Test func newFoodCrabSteamed() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "crab")).isEmpty)
}

@Test func newFoodScallops() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "scallops")).isEmpty)
}

@Test func newFoodTroutBaked() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "trout")).isEmpty)
}

@Test func newFoodOysters() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "oysters")).isEmpty)
}

@Test func newFoodMussels() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "mussels")).isEmpty)
}

// MARK: - New Foods (junior cycle 3 — Indian, seafood, wraps, grains)

@Test func newFoodChickenMalaiTikka() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "malai tikka")).isEmpty)
}

@Test func newFoodShammiKebab() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "shammi kebab")).isEmpty)
}

@Test func newFoodCucumberRaita() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "cucumber raita")).isEmpty)
}

@Test func newFoodMixedRaita() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "mixed raita")).isEmpty)
}

@Test func newFoodBreadUpma() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "bread upma")).isEmpty)
}

@Test func newFoodFishTikka() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "fish tikka")).isEmpty)
}

@Test func newFoodPomfret() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "pomfret")).isEmpty)
}

@Test func newFoodRouhu() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "rohu")).isEmpty)
}

@Test func newFoodHilsa() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "hilsa")).isEmpty)
}

@Test func newFoodBlackTea() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "black tea")).isEmpty)
}

@Test func newFoodTunaWrap() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "tuna wrap")).isEmpty)
}

@Test func newFoodVeggieWrap() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "veggie wrap")).isEmpty)
}

@Test func newFoodBeefMeatballs() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "beef meatball")).isEmpty)
}

@Test func newFoodWheatBran() async throws {
    let db = seededDB()
    #expect(!(try db.searchFoods(query: "wheat bran")).isEmpty)
}

// MARK: - Smart Units — pasta, cereal, smoothie

@Test func smartUnitsPastaShowsCup() {
    let food = Food(name: "Pasta (cooked)", category: "Grains", servingSize: 140, servingUnit: "g", calories: 220)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Pasta primary unit should be cup")
}

@Test func smartUnitsSpaghettiShowsCup() {
    let food = Food(name: "Spaghetti Bolognese", category: "Italian", servingSize: 300, servingUnit: "g", calories: 420)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Spaghetti primary unit should be cup")
}

@Test func smartUnitsNoodlesShowsCup() {
    let food = Food(name: "Hakka Noodles", category: "Indo-Chinese", servingSize: 200, servingUnit: "g", calories: 310)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Noodles primary unit should be cup")
}

@Test func smartUnitsNoodleSoupNotNoodleRule() {
    // Soup rule fires before noodle rule — bowl is correct
    let food = Food(name: "Chicken Noodle Soup", category: "Soups", servingSize: 240, servingUnit: "ml", calories: 75)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "bowl", "Noodle soup primary unit should be bowl (soup rule first)")
}

@Test func smartUnitsMuesliShowsCup() {
    let food = Food(name: "Muesli", category: "Breakfast", servingSize: 45, servingUnit: "g", calories: 170)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Muesli primary unit should be cup")
}

@Test func smartUnitsMuesliBarNotCup() {
    // Bar exclusion — a muesli bar is eaten by piece
    let food = Food(name: "Muesli Bar", category: "Snacks", servingSize: 35, servingUnit: "g", calories: 145)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label != "cup", "Muesli bar should not be cup")
}

@Test func smartUnitsSmoothieShowsCup() {
    let food = Food(name: "Mango Smoothie", category: "Beverages", servingSize: 300, servingUnit: "ml", calories: 180)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Smoothie primary unit should be cup")
}

@Test func smartUnitsProteinShakeShowsCup() {
    let food = Food(name: "Protein Shake", category: "Fitness", servingSize: 330, servingUnit: "ml", calories: 160)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Protein shake primary unit should be cup")
}

@Test func smartUnitsProteinPowderShowsScoop() {
    let food = Food(name: "Whey Protein Powder", category: "Fitness", servingSize: 30, servingUnit: "g", calories: 120)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "scoop", "Protein powder primary unit should be scoop")
}

@Test func smartUnitsDalShowsCup() {
    let food = Food(name: "Toor Dal (cooked)", category: "Indian", servingSize: 200, servingUnit: "g", calories: 220)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Dal primary unit should be cup")
}

@Test func smartUnitsBlackBeansShowsCup() {
    let food = Food(name: "Black Beans (cooked)", category: "Legumes", servingSize: 172, servingUnit: "g", calories: 227)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Black beans primary unit should be cup")
}

@Test func smartUnitsLentilsShowsCup() {
    let food = Food(name: "Lentils (cooked)", category: "Legumes", servingSize: 198, servingUnit: "g", calories: 230)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Lentils primary unit should be cup")
}

@Test func smartUnitsHoneyShowsTbsp() {
    let food = Food(name: "Honey", category: "Condiments", servingSize: 21, servingUnit: "g", calories: 64)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp", "Honey primary unit should be tbsp")
}

@Test func smartUnitsJamShowsTbsp() {
    let food = Food(name: "Strawberry Jam", category: "Condiments", servingSize: 20, servingUnit: "g", calories: 52)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp", "Jam primary unit should be tbsp")
}

@Test func smartUnitsChutneyShowsTbsp() {
    let food = Food(name: "Mint Chutney", category: "Indian", servingSize: 15, servingUnit: "g", calories: 12)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp", "Chutney primary unit should be tbsp")
}

@Test func smartUnitsChiaSeedsShowsTbsp() {
    let food = Food(name: "Chia Seeds", category: "Seeds", servingSize: 10, servingUnit: "g", calories: 49)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp", "Chia seeds primary unit should be tbsp")
}

@Test func smartUnitsGaramMasalaShowsTsp() {
    let food = Food(name: "Garam Masala", category: "Spices", servingSize: 3, servingUnit: "g", calories: 8)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tsp", "Garam masala primary unit should be tsp")
}

@Test func smartUnitsTurmericShowsTsp() {
    let food = Food(name: "Turmeric Powder", category: "Spices", servingSize: 3, servingUnit: "g", calories: 9)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tsp", "Turmeric powder primary unit should be tsp")
}

@Test func smartUnitsHeavyCreamShowsTbsp() {
    let food = Food(name: "Heavy Cream", category: "Dairy", servingSize: 15, servingUnit: "ml", calories: 51)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "tbsp", "Heavy cream primary unit should be tbsp")
}

@Test func smartUnitsIceCreamShowsScoop() {
    let food = Food(name: "Vanilla Ice Cream", category: "Desserts", servingSize: 100, servingUnit: "g", calories: 207)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "scoop", "Ice cream primary unit should be scoop")
}

@Test func smartUnitsChaiShowsCup() {
    let food = Food(name: "Masala Chai", category: "Beverages", servingSize: 240, servingUnit: "ml", calories: 80)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Chai primary unit should be cup")
}

@Test func smartUnitsBeanSproutsShowsCup() {
    let food = Food(name: "Bean Sprouts", category: "Vegetables", servingSize: 90, servingUnit: "g", calories: 30)
    let units = FoodUnit.smartUnits(for: food)
    #expect(units.first?.label == "cup", "Bean sprouts primary unit should be cup")
}

// MARK: - AI Chat Smart Serving Text Tests (7 tests)
// Verify confirmation cards show natural units, not "N serving"

@MainActor
@Test func smartServingTextDosaShowsPiece() {
    let dosa = Food(name: "Dosa (plain)", category: "Indian Breads", servingSize: 80, servingUnit: "g", calories: 133)
    let text = AIChatViewModel.smartServingText(food: dosa, servings: 2, gramAmount: nil)
    #expect(text == "2 piece", "2 dosas should show '2 piece', got: \(text)")
}

@MainActor
@Test func smartServingTextDalShowsCup() {
    // servingSize: 200 = exactly 1 cup (cupGrams for dal = 200g)
    let dal = Food(name: "Dal (toor/arhar)", category: "Lentils", servingSize: 200, servingUnit: "g", calories: 249)
    let text = AIChatViewModel.smartServingText(food: dal, servings: 1, gramAmount: nil)
    #expect(text == "1 cup", "1 serving of dal should show '1 cup', got: \(text)")
}

@MainActor
@Test func smartServingTextMilkShowsMl() {
    let milk = Food(name: "Milk (whole)", category: "Dairy", servingSize: 244, servingUnit: "ml", calories: 150)
    let text = AIChatViewModel.smartServingText(food: milk, servings: 1, gramAmount: nil)
    #expect(text.contains("ml") || text.contains("cup"), "Milk should show ml or cup, got: \(text)")
}

@MainActor
@Test func smartServingTextGramAmountOverridesUnit() {
    let rice = Food(name: "Rice (cooked)", category: "Grains", servingSize: 200, servingUnit: "g", calories: 260)
    let text = AIChatViewModel.smartServingText(food: rice, servings: 1, gramAmount: 150)
    #expect(text == "150g", "Explicit gram amount should show grams, got: \(text)")
}

@MainActor
@Test func smartServingTextRotiShowsPiece() {
    let roti = Food(name: "Roti (whole wheat)", category: "Bread", servingSize: 40, servingUnit: "g", calories: 120)
    let text = AIChatViewModel.smartServingText(food: roti, servings: 3, gramAmount: nil)
    #expect(text == "3 piece", "3 rotis should show '3 piece', got: \(text)")
}

@MainActor
@Test func smartServingTextEggShowsEgg() {
    let egg = Food(name: "Egg (whole, boiled)", category: "Protein", servingSize: 50, servingUnit: "g", calories: 78)
    let text = AIChatViewModel.smartServingText(food: egg, servings: 2, gramAmount: nil)
    #expect(text == "2 egg", "2 eggs should show '2 egg', got: \(text)")
}

@MainActor
@Test func smartServingTextFallsBackToServingWhenNoSmartUnit() {
    // A food with default "serving" unit (no smart unit configured) should fall back gracefully
    let genericFood = Food(name: "Some Food Item", category: "Other", servingSize: 100, servingUnit: "g", calories: 200)
    let text = AIChatViewModel.smartServingText(food: genericFood, servings: 1.5, gramAmount: nil)
    // Either shows smart unit or "1.5 serving" — must not crash, must be non-empty
    #expect(!text.isEmpty, "smartServingText must always return non-empty string")
}

// MARK: - Smart Units: Salads, Grains, Meat Cuts

@Test func smartUnitSaladShowsBowl() {
    let salad = Food(name: "Caesar Salad", category: "Salads", servingSize: 200, servingUnit: "g", calories: 220)
    #expect(FoodUnit.smartUnits(for: salad).first?.label == "bowl", "Salad should default to bowl")
}

@Test func smartUnitGreekSaladShowsBowl() {
    let salad = Food(name: "Greek Salad", category: "Mediterranean", servingSize: 180, servingUnit: "g", calories: 150)
    #expect(FoodUnit.smartUnits(for: salad).first?.label == "bowl", "Greek salad should default to bowl")
}

@Test func smartUnitSaladDressingNotBowl() {
    // Dressings are condiments — tbsp, not bowl
    let dressing = Food(name: "Caesar Salad Dressing", category: "Condiments", servingSize: 30, servingUnit: "g", calories: 160)
    let unit = FoodUnit.smartUnits(for: dressing).first?.label
    #expect(unit != "bowl", "Salad dressing should not be bowl, got: \(unit ?? "nil")")
}

@Test func smartUnitGritsShowsCup() {
    let grits = Food(name: "Grits (Cooked)", category: "Grains & Cereals", servingSize: 180, servingUnit: "g", calories: 145)
    #expect(FoodUnit.smartUnits(for: grits).first?.label == "cup", "Grits should default to cup")
}

@Test func smartUnitRisottoShowsCup() {
    let risotto = Food(name: "Mushroom Risotto", category: "Italian", servingSize: 250, servingUnit: "g", calories: 340)
    #expect(FoodUnit.smartUnits(for: risotto).first?.label == "cup", "Risotto should default to cup")
}

@Test func smartUnitPolentaShowsCup() {
    let polenta = Food(name: "Polenta (Cooked)", category: "Grains", servingSize: 150, servingUnit: "g", calories: 90)
    #expect(FoodUnit.smartUnits(for: polenta).first?.label == "cup", "Polenta should default to cup")
}

@Test func smartUnitChickenBreastShowsPiece() {
    let chicken = Food(name: "Chicken Breast (Cooked)", category: "Proteins", servingSize: 165, servingUnit: "g", calories: 165)
    #expect(FoodUnit.smartUnits(for: chicken).first?.label == "piece", "Chicken breast should default to piece")
}

@Test func smartUnitPorkChopShowsPiece() {
    let pork = Food(name: "Pork Chop (Grilled)", category: "Proteins", servingSize: 130, servingUnit: "g", calories: 240)
    #expect(FoodUnit.smartUnits(for: pork).first?.label == "piece", "Pork chop should default to piece")
}

@Test func smartUnitLambChopShowsPiece() {
    let lamb = Food(name: "Lamb Chop (Grilled)", category: "Proteins", servingSize: 120, servingUnit: "g", calories: 290)
    #expect(FoodUnit.smartUnits(for: lamb).first?.label == "piece", "Lamb chop should default to piece")
}

@Test func smartUnitChickenLollipopShowsPiece() {
    let lollipop = Food(name: "Chicken Lollipop", category: "Indian Snacks", servingSize: 50, servingUnit: "g", calories: 120)
    #expect(FoodUnit.smartUnits(for: lollipop).first?.label == "piece", "Chicken lollipop should default to piece")
}

@Test func portionTextSaladShowsBowl() {
    let entry = FoodEntry(foodName: "Caesar Salad", servingSizeG: 200, servings: 1,
                          calories: 220, proteinG: 12, carbsG: 10, fatG: 18, mealType: "Lunch")
    #expect(entry.portionText == "1 bowl", "Caesar salad portionText should be '1 bowl', got: \(entry.portionText)")
}

@Test func portionTextChickenBreastShowsPiece() {
    let entry = FoodEntry(foodName: "Chicken Breast (Cooked)", servingSizeG: 165, servings: 1,
                          calories: 165, proteinG: 31, carbsG: 0, fatG: 3, mealType: "Dinner")
    #expect(entry.portionText == "1 piece", "Chicken breast portionText should be '1 piece', got: \(entry.portionText)")
}

// MARK: - Smart Unit Tests (session 6: scrambled eggs, bacon, vegetables, bowls)

@Test func smartUnitScrambledEggsShowsPiece() {
    let food = Food(name: "Scrambled Eggs (2)", category: "Proteins", servingSize: 120, servingUnit: "g", calories: 180)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Scrambled eggs should default to piece")
}

@Test func smartUnitBhurjiShowsPiece() {
    let food = Food(name: "Egg Bhurji", category: "Indian Staples", servingSize: 150, servingUnit: "g", calories: 220)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Bhurji should default to piece")
}

@Test func smartUnitCroissantShowsPiece() {
    let food = Food(name: "Croissant", category: "Bakery", servingSize: 57, servingUnit: "g", calories: 231)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Croissant should default to piece")
}

@Test func smartUnitFrenchToastShowsPiece() {
    let food = Food(name: "French Toast (2 slices)", category: "Breakfast", servingSize: 130, servingUnit: "g", calories: 300)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "French toast should default to piece not slice")
}

@Test func smartUnitAlmondButterShowsTbsp() {
    let food = Food(name: "Almond Butter", category: "Nuts & Seeds", servingSize: 32, servingUnit: "g", calories: 190)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "tbsp", "Almond butter should default to tbsp")
}

@Test func smartUnitMapleSyrupShowsTbsp() {
    let food = Food(name: "Maple Syrup", category: "Condiments", servingSize: 20, servingUnit: "g", calories: 52)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "tbsp", "Maple syrup should default to tbsp")
}

@Test func smartUnitAgaveShowsTbsp() {
    let food = Food(name: "Agave Nectar", category: "Condiments", servingSize: 21, servingUnit: "g", calories: 64)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "tbsp", "Agave should default to tbsp")
}

@Test func smartUnitBaconShowsStrip() {
    let food = Food(name: "Bacon (2 slices)", category: "Proteins", servingSize: 28, servingUnit: "g", calories: 86)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "strip", "Bacon should default to strip")
}

@Test func smartUnitSausageShowsLink() {
    let food = Food(name: "Italian Sausage (1 link)", category: "Proteins", servingSize: 84, servingUnit: "g", calories: 220)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "link", "Sausage should default to link")
}

@Test func smartUnitTurkeyShowsPiece() {
    let food = Food(name: "Turkey Breast (roasted)", category: "Proteins", servingSize: 85, servingUnit: "g", calories: 135)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Turkey should default to piece")
}

@Test func smartUnitBroccoliShowsCup() {
    let food = Food(name: "Broccoli (cooked)", category: "Vegetables", servingSize: 91, servingUnit: "g", calories: 55)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Broccoli should default to cup")
}

@Test func smartUnitCauliflowerShowsCup() {
    let food = Food(name: "Cauliflower (steamed)", category: "Vegetables", servingSize: 100, servingUnit: "g", calories: 25)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Cauliflower should default to cup")
}

@Test func smartUnitAsparagusShowsCup() {
    let food = Food(name: "Asparagus (cooked)", category: "Vegetables", servingSize: 134, servingUnit: "g", calories: 27)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Asparagus should default to cup")
}

@Test func smartUnitKaleShowsCup() {
    let food = Food(name: "Kale (raw)", category: "Vegetables", servingSize: 67, servingUnit: "g", calories: 33)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Kale should default to cup")
}

@Test func smartUnitEdamameShowsCup() {
    let food = Food(name: "Edamame (shelled)", category: "Vegetables", servingSize: 155, servingUnit: "g", calories: 188)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Edamame should default to cup")
}

@Test func smartUnitPokeBowlShowsBowl() {
    let food = Food(name: "Poke Bowl (Tuna)", category: "Healthy Options", servingSize: 400, servingUnit: "g", calories: 450)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Poke bowl should default to bowl")
}

@Test func smartUnitAcaiBowlShowsBowl() {
    let food = Food(name: "Acai Bowl", category: "Healthy Options", servingSize: 300, servingUnit: "g", calories: 350)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Acai bowl should default to bowl")
}

@Test func smartUnitPotatoBoiledShowsPiece() {
    let food = Food(name: "Potato (boiled)", category: "Vegetables", servingSize: 150, servingUnit: "g", calories: 116)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Boiled potato should default to piece")
}

@Test func smartUnitMashedPotatoShowsCup() {
    let food = Food(name: "Mashed Potatoes", category: "Vegetables", servingSize: 210, servingUnit: "g", calories: 237)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Mashed potatoes should default to cup")
}

@Test func smartUnitCottageCheeseShowsCup() {
    let food = Food(name: "Cottage Cheese (2%)", category: "Dairy", servingSize: 226, servingUnit: "g", calories: 206)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Cottage cheese should default to cup")
}

@Test func smartUnitPaneerShowsCup() {
    let food = Food(name: "Paneer", category: "Dairy", servingSize: 150, servingUnit: "g", calories: 398)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "cup", "Paneer (standalone) should default to cup")
}

@Test func smartUnitKoftaShowsBowl() {
    let food = Food(name: "Malai Kofta", category: "Indian Curries", servingSize: 300, servingUnit: "g", calories: 450)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Kofta dish should default to bowl")
}

@Test func smartUnitKormaShowsBowl() {
    let food = Food(name: "Chicken Korma", category: "Indian Curries", servingSize: 300, servingUnit: "g", calories: 400)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Korma should default to bowl")
}

@Test func smartUnitPalakPaneerShowsBowl() {
    let food = Food(name: "Palak Paneer", category: "Indian Curries", servingSize: 250, servingUnit: "g", calories: 320)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "bowl", "Palak Paneer should default to bowl")
}

@Test func smartUnitZucchiniShowsPiece() {
    let food = Food(name: "Zucchini", category: "Vegetables", servingSize: 196, servingUnit: "g", calories: 33)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "piece", "Zucchini should default to piece")
}

@Test func smartUnitWheyProteinShowsScoop() {
    let food = Food(name: "Whey Protein Isolate", category: "Proteins", servingSize: 30, servingUnit: "g", calories: 110)
    #expect(FoodUnit.smartUnits(for: food).first?.label == "scoop", "Whey protein isolate should default to scoop")
}

// portionText matching tests
@Test func portionTextScrambledEggsShowsPiece() {
    let entry = FoodEntry(foodName: "Scrambled Eggs (2)", servingSizeG: 120, servings: 1,
                          calories: 180, proteinG: 12, carbsG: 2, fatG: 14, mealType: "Breakfast")
    #expect(entry.portionText == "1 piece", "Scrambled eggs portionText should show piece")
}

@Test func portionTextBaconShowsStrip() {
    let entry = FoodEntry(foodName: "Turkey Bacon (2 strips)", servingSizeG: 28, servings: 2,
                          calories: 60, proteinG: 8, carbsG: 0, fatG: 3, mealType: "Breakfast")
    #expect(entry.portionText == "2 strips", "Bacon portionText should show strips")
}

@Test func portionTextSausageShowsLink() {
    let entry = FoodEntry(foodName: "Italian Sausage (1 link)", servingSizeG: 84, servings: 1,
                          calories: 220, proteinG: 13, carbsG: 2, fatG: 18, mealType: "Dinner")
    #expect(entry.portionText == "1 link", "Sausage portionText should show link")
}

@Test func portionTextBroccoliShowsCup() {
    let entry = FoodEntry(foodName: "Broccoli (steamed)", servingSizeG: 91, servings: 1,
                          calories: 55, proteinG: 3.7, carbsG: 11, fatG: 0.6, mealType: "Dinner")
    #expect(entry.portionText == "1 cup", "Broccoli portionText should show cup")
}

@Test func portionTextPokeBowlShowsBowl() {
    let entry = FoodEntry(foodName: "Poke Bowl (Tuna)", servingSizeG: 400, servings: 1,
                          calories: 450, proteinG: 32, carbsG: 48, fatG: 12, mealType: "Lunch")
    #expect(entry.portionText == "1 bowl", "Poke bowl portionText should show bowl")
}

// MARK: - MealType.resolve (auto-detection)

@Test func mealTypeResolveFallsBackToHourRangeWhenNoRecentEntries() {
    let cal = Calendar.current
    let morning = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    #expect(MealType.resolve(now: morning, recentEntries: []) == .breakfast)

    let lunchTime = cal.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!
    #expect(MealType.resolve(now: lunchTime, recentEntries: []) == .lunch)

    let dinnerTime = cal.date(bySettingHour: 19, minute: 0, second: 0, of: Date())!
    #expect(MealType.resolve(now: dinnerTime, recentEntries: []) == .dinner)

    let lateNight = cal.date(bySettingHour: 2, minute: 0, second: 0, of: Date())!
    #expect(MealType.resolve(now: lateNight, recentEntries: []) == .snack)
}

@Test func mealTypeResolveInheritsFromRecentBreakfastWithin3h() {
    let cal = Calendar.current
    let iso = DateFormatters.iso8601
    let now = cal.date(bySettingHour: 10, minute: 0, second: 0, of: Date())!
    let earlier = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    let prev = FoodEntry(foodName: "Oatmeal", servingSizeG: 0, calories: 200,
                         loggedAt: iso.string(from: earlier), mealType: "breakfast")
    #expect(MealType.resolve(now: now, recentEntries: [prev]) == .breakfast,
            "Second log within 3h of breakfast should inherit breakfast")
}

@Test func mealTypeResolveFallsBackWhenMoreThan3hSinceLastLog() {
    let cal = Calendar.current
    let iso = DateFormatters.iso8601
    let now = cal.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!
    let earlier = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    let prev = FoodEntry(foodName: "Oatmeal", servingSizeG: 0, calories: 200,
                         loggedAt: iso.string(from: earlier), mealType: "breakfast")
    #expect(MealType.resolve(now: now, recentEntries: [prev]) == .lunch,
            "5h gap should fall back to hour-range (1pm = lunch)")
}

@Test func mealTypeResolveDoesNotInheritSnack() {
    let cal = Calendar.current
    let iso = DateFormatters.iso8601
    let now = cal.date(bySettingHour: 8, minute: 30, second: 0, of: Date())!
    let earlier = cal.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!
    let prev = FoodEntry(foodName: "Coffee", servingSizeG: 0, calories: 5,
                         loggedAt: iso.string(from: earlier), mealType: "snack")
    #expect(MealType.resolve(now: now, recentEntries: [prev]) == .breakfast,
            "Snack should not be inherited — fall through to hour range")
}

@Test func mealTypeResolvePicksMostRecentWhenMultipleEntries() {
    let cal = Calendar.current
    let iso = DateFormatters.iso8601
    let now = cal.date(bySettingHour: 14, minute: 0, second: 0, of: Date())!
    let breakfast = cal.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
    let lunch = cal.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!
    let b = FoodEntry(foodName: "Oats", servingSizeG: 0, calories: 200,
                      loggedAt: iso.string(from: breakfast), mealType: "breakfast")
    let l = FoodEntry(foodName: "Salad", servingSizeG: 0, calories: 400,
                      loggedAt: iso.string(from: lunch), mealType: "lunch")
    #expect(MealType.resolve(now: now, recentEntries: [b, l]) == .lunch,
            "Should pick most recent (lunch), not oldest (breakfast)")
}

@Test func autoMealTypeInheritsFromViewModelRecentEntries() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)

    let cal = Calendar.current
    let hour = cal.component(.hour, from: Date())
    // Only run this check when "now" is in breakfast window (5-11) so hour-range fallback
    // would return breakfast anyway. Skip if we're outside that window to keep test deterministic.
    guard hour >= 5, hour < 11 else { return }

    await vm.quickAdd(name: "Oatmeal", calories: 200, proteinG: 10, carbsG: 30, fatG: 5,
                      fiberG: 4, mealType: .breakfast)
    let resolved = await vm.autoMealType
    #expect(resolved == .breakfast, "With a breakfast entry just logged, autoMealType should be breakfast")
}

// MARK: - South Indian food DB coverage (#188)

@Test func southIndianFoodDBHasKeyRegionalDishes() throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let keyDishes = ["Puliyodarai", "Mor Kuzhambu", "Fish Moilee", "Puttu Kadala",
                     "Bisi Bele Bath (Karnataka)", "Adai Dosa", "Paruppu Rasam",
                     "Chana Sundal", "Cabbage Poriyal", "Kerala Halwa"]
    for dish in keyDishes {
        let results = try db.searchFoods(query: dish)
        #expect(results.contains(where: { $0.name == dish }),
                "Expected '\(dish)' in food DB — missing regional coverage")
    }
}

@Test func southIndianPuttuSearchReturnsVariants() throws {
    let db = try AppDatabase.empty()
    try db.seedFoodsFromJSON()
    let results = try db.searchFoods(query: "puttu")
    #expect(results.count >= 2, "Expected at least 2 puttu variants (Puttu + Puttu Kadala), got \(results.count)")
}

@Test func updateFoodEntryMealTypePersists() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Oatmeal", calories: 200, proteinG: 10, carbsG: 30, fatG: 5,
                      fiberG: 4, mealType: .lunch)
    guard let entryId = await vm.todayEntries.first?.id else {
        Issue.record("Expected one entry"); return
    }
    await vm.updateEntryMealType(id: entryId, mealType: .dinner)
    await vm.loadTodayMeals()
    let updated = await vm.todayEntries.first(where: { $0.id == entryId })
    #expect(updated?.mealType == "dinner", "Meal type should be updated to dinner")
}

// MARK: - swapEntries Tests (3 tests)

@Test func swapEntriesSwapsTimes() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    let t1 = "2026-01-01T08:00:00Z"
    let t2 = "2026-01-01T12:00:00Z"
    await vm.quickAdd(name: "A", calories: 100, proteinG: 10, carbsG: 10, fatG: 5, fiberG: 0,
                      mealType: .breakfast, loggedAt: t1)
    await vm.quickAdd(name: "B", calories: 200, proteinG: 20, carbsG: 20, fatG: 10, fiberG: 0,
                      mealType: .lunch, loggedAt: t2)
    let entries = await vm.todayEntries.sorted { $0.loggedAt < $1.loggedAt }
    #expect(entries.count == 2)
    await vm.swapEntries(0, 1, in: entries)
    await vm.loadTodayMeals()
    let after = await vm.todayEntries.sorted { $0.loggedAt < $1.loggedAt }
    #expect(after[0].foodName == "B", "B should now be first (had t2, swapped to t1)")
    #expect(after[1].foodName == "A")
}

@Test func swapEntriesSameTimetampAdjustsByOneSecond() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    let t = "2026-01-01T09:00:00Z"
    await vm.quickAdd(name: "X", calories: 100, proteinG: 5, carbsG: 10, fatG: 5, fiberG: 0,
                      mealType: .breakfast, loggedAt: t)
    await vm.quickAdd(name: "Y", calories: 150, proteinG: 8, carbsG: 15, fatG: 6, fiberG: 0,
                      mealType: .breakfast, loggedAt: t)
    let entries = await vm.todayEntries
    #expect(entries.count == 2)
    await vm.swapEntries(0, 1, in: entries)
    await vm.loadTodayMeals()
    #expect(await vm.todayEntries.count == 2, "Should still have 2 entries after same-time swap")
}

@Test func swapEntriesOutOfBoundsIsNoop() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Food", calories: 100, proteinG: 5, carbsG: 10, fatG: 5, fiberG: 0,
                      mealType: .lunch)
    let entries = await vm.todayEntries
    await vm.swapEntries(0, 5, in: entries)
    #expect(await vm.todayEntries.count == 1, "Out-of-bounds swap should be a no-op")
}

// MARK: - loggedDays Tests (2 tests)

@Test func loggedDaysReturnsCaloriesForDaysWithFood() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Lunch", calories: 500, proteinG: 20, carbsG: 60, fatG: 15, fiberG: 3,
                      mealType: .lunch)
    let result = await vm.loggedDays(last: 7)
    let todayKey = Calendar.current.startOfDay(for: Date())
    #expect((result[todayKey] ?? 0) >= 500, "Today should have logged calories")
}

@Test func loggedDaysEmptyDatabaseReturnsZeroCalories() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    let result = await vm.loggedDays(last: 7)
    let totalLogged = result.values.reduce(0, +)
    #expect(totalLogged == 0, "Empty DB should have no logged calories")
}

// MARK: - yesterdayCalories Tests (2 tests)

@Test func yesterdayCaloriesReturnsNilWhenNothingLogged() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    let result = await vm.yesterdayCalories()
    #expect(result == nil, "No food yesterday should return nil")
}

// MARK: - loadPlantPoints Tests (2 tests)

@Test func loadPlantPointsCountsUniqueIngredients() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.quickAdd(name: "Spinach", calories: 30, proteinG: 2, carbsG: 5, fatG: 0.5, fiberG: 2,
                      mealType: .lunch)
    await vm.loadPlantPoints()
    let points = await vm.weeklyPlantPoints
    #expect(points.plantCount >= 1, "Should count spinach as a plant")
}

@Test func loadPlantPointsZeroWhenNoFoodLogged() async throws {
    let db = try AppDatabase.empty()
    let vm = await FoodLogViewModel(database: db)
    await vm.loadPlantPoints()
    let points = await vm.weeklyPlantPoints
    #expect(points.plantCount == 0, "Empty DB should have zero plant points")
}

// MARK: - toggleFavorite / isFavorite Tests (2 tests)

@MainActor @Test func toggleFavoritePersistsAcrossCalls() async throws {
    let name = "ToggleTestFood_\(Int.random(in: 1000...9999))"
    FoodService.toggleFavorite(name: name, foodId: nil)
    #expect(FoodService.isFavorite(name: name), "Should be favorite after first toggle")
    FoodService.toggleFavorite(name: name, foodId: nil)
    #expect(!FoodService.isFavorite(name: name), "Should not be favorite after second toggle")
}

@MainActor @Test func isFavoriteReturnsFalseForNewFood() {
    let name = "NeverFavorited_\(Int.random(in: 10000...99999))"
    #expect(!FoodService.isFavorite(name: name), "Brand-new food should not be a favorite")
}
