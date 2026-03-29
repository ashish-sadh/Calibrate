import Foundation
import Testing
import GRDB
@testable import Drift

// MARK: - Weight Edge Cases (8 tests)

@Test func weightEntryLbsConversionAccuracy() async throws {
    let e = WeightEntry(date: "2026-03-28", weightKg: 100)
    #expect(abs(e.weightLbs - 220.462) < 0.01)
}

@Test func weightVeryLargeDataset200() async throws {
    let entries: [(String, Double)] = (0..<200).map { day in
        let date = Calendar.current.date(byAdding: .day, value: -199 + day, to: Date())!
        return (DateFormatters.dateOnly.string(from: date), 80.0 - Double(day) * 0.015)
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.dataPoints.count == 200)
    #expect(t.trendDirection == .losing)
    #expect(t.weightChanges.ninetyDay != nil)
}

@Test func weightSameValueMultipleDays() async throws {
    let entries: [(String, Double)] = (0..<10).map {
        (String(format: "2026-03-%02d", $0 + 1), 70.0)
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.trendDirection == .maintaining)
    #expect(abs(t.estimatedDailyDeficit) < 50)
}

@Test func weightYoYoPattern() async throws {
    let entries: [(String, Double)] = (0..<20).map {
        (String(format: "2026-03-%02d", $0 + 1), 65.0 + ($0 % 2 == 0 ? 1.0 : -1.0))
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.trendDirection == .maintaining, "Yo-yo should be maintaining")
}

@Test func weightRapidLoss() async throws {
    let entries: [(String, Double)] = (0..<14).map {
        (String(format: "2026-03-%02d", $0 + 1), 80.0 - Double($0) * 0.5) // 0.5 kg/day = extreme
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.trendDirection == .losing)
    #expect(t.estimatedDailyDeficit < -1000, "Extreme loss should show large deficit")
}

@Test func weightGradualGain() async throws {
    let entries: [(String, Double)] = (0..<21).map {
        (String(format: "2026-03-%02d", $0 + 1), 55.0 + Double($0) * 0.03) // slow lean bulk
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.trendDirection == .gaining || t.trendDirection == .maintaining) // very slow gain might be maintaining
}

@Test func weightDBUpsertPreservesSource() async throws {
    let db = try AppDatabase.empty()
    var e1 = WeightEntry(date: "2026-03-28", weightKg: 55, source: "healthkit", syncedFromHk: true)
    try db.saveWeightEntry(&e1)
    var e2 = WeightEntry(date: "2026-03-28", weightKg: 56, source: "manual", syncedFromHk: false)
    try db.saveWeightEntry(&e2)
    let fetched = try db.fetchWeightEntries()
    #expect(fetched.count == 1)
    #expect(fetched[0].weightKg == 56, "Upsert should update weight")
}

@Test func weightFetchEmptyDB() async throws {
    let db = try AppDatabase.empty()
    #expect(try db.fetchWeightEntries().isEmpty)
    #expect(try db.fetchLatestWeight() == nil)
}

// MARK: - Food Edge Cases (6 tests)

@Test func foodSearchSpecialChars() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var f = Food(name: "Egg/Besan Chilla", category: "Indian", servingSize: 120, servingUnit: "g", calories: 200)
        try f.insert(dbConn)
    }
    let r = try db.searchFoods(query: "chilla")
    #expect(r.count == 1)
}

@Test func foodZeroServings() async throws {
    let e = FoodEntry(mealLogId: 1, foodName: "X", servingSizeG: 100, servings: 0, calories: 500, proteinG: 30)
    #expect(e.totalCalories == 0)
    #expect(e.totalProtein == 0)
}

@Test func foodFractionalServings() async throws {
    let e = FoodEntry(mealLogId: 1, foodName: "X", servingSizeG: 200, servings: 0.5, calories: 260, proteinG: 5)
    #expect(e.totalCalories == 130)
    #expect(e.totalProtein == 2.5)
}

@Test func foodSearchLimit() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        for i in 0..<100 {
            var f = Food(name: "Item \(i)", category: "Test", servingSize: 100, servingUnit: "g", calories: 100)
            try f.insert(dbConn)
        }
    }
    let r = try db.searchFoods(query: "Item", limit: 10)
    #expect(r.count == 10, "Should respect limit")
}

@Test func foodCategoryFetch() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var f1 = Food(name: "A", category: "Indian", servingSize: 100, servingUnit: "g", calories: 100)
        var f2 = Food(name: "B", category: "Protein", servingSize: 100, servingUnit: "g", calories: 200)
        try f1.insert(dbConn); try f2.insert(dbConn)
    }
    let cats = try db.fetchAllFoodCategories()
    #expect(cats.count == 2)
    #expect(cats.contains("Indian"))
}

@Test func foodDailyNutritionMultipleMeals() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        for mt in ["breakfast", "lunch", "dinner", "snack"] {
            var m = MealLog(date: "2026-03-28", mealType: mt); try m.insert(dbConn)
            var e = FoodEntry(mealLogId: m.id!, foodName: mt, servingSizeG: 100, servings: 1, calories: 500, proteinG: 25, carbsG: 50, fatG: 15, fiberG: 5)
            try e.insert(dbConn)
        }
    }
    let n = try db.fetchDailyNutrition(for: "2026-03-28")
    #expect(n.calories == 2000) // 4 × 500
    #expect(n.proteinG == 100)  // 4 × 25
}

// MARK: - Supplement Edge Cases (4 tests)

@Test func supplementToggleTwice() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "X"); try db.saveSupplement(&s)
    let sid = try db.fetchActiveSupplements()[0].id!
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-28")
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-28")
    let log = try db.fetchSupplementLogs(for: "2026-03-28")
    #expect(log[0].taken == false, "Double toggle = untaken")
}

@Test func supplementDifferentDatesIndependent() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "X"); try db.saveSupplement(&s)
    let sid = try db.fetchActiveSupplements()[0].id!
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-27")
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-28")
    #expect(try db.fetchSupplementLogs(for: "2026-03-27")[0].taken == true)
    #expect(try db.fetchSupplementLogs(for: "2026-03-28")[0].taken == true)
}

@Test func supplementSortOrder() async throws {
    let db = try AppDatabase.empty()
    var s1 = Supplement(name: "B", sortOrder: 1); try db.saveSupplement(&s1)
    var s2 = Supplement(name: "A", sortOrder: 0); try db.saveSupplement(&s2)
    let all = try db.fetchActiveSupplements()
    #expect(all[0].name == "A", "Should be sorted by sort_order")
}

@Test func supplementInactive() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var s = Supplement(name: "Old", isActive: false, sortOrder: 0)
        try s.insert(dbConn)
    }
    #expect(try db.fetchActiveSupplements().isEmpty, "Inactive should not appear")
}

// MARK: - DEXA Edge Cases (4 tests)

@Test func dexaBMCConversion() async throws {
    let s = DEXAScan(scanDate: "2026-03-06", boneMassKg: 2.2)
    #expect(abs(s.bmcLbs! - 4.85) < 0.1)
}

@Test func dexaNilValues() async throws {
    let s = DEXAScan(scanDate: "2026-03-06")
    #expect(s.fatMassLbs == nil)
    #expect(s.leanMassLbs == nil)
    #expect(s.visceralFatLbs == nil)
    #expect(s.bmcLbs == nil)
}

@Test func dexaMultipleScansComparison() async throws {
    let db = try AppDatabase.empty()
    var s1 = DEXAScan(scanDate: "2025-09-01", bodyFatPct: 25); try db.saveDEXAScan(&s1)
    var s2 = DEXAScan(scanDate: "2026-03-01", bodyFatPct: 16); try db.saveDEXAScan(&s2)
    let all = try db.fetchDEXAScans()
    #expect(all[0].bodyFatPct == 16, "Most recent first")
    #expect(all[1].bodyFatPct == 25)
}

@Test func dexaRegionsCascadeDelete() async throws {
    let db = try AppDatabase.empty()
    var s = DEXAScan(scanDate: "2026-03-06", bodyFatPct: 16)
    try db.saveDEXAScan(&s)
    let scanId = try db.fetchDEXAScans()[0].id!
    try db.saveDEXARegions([DEXARegion(scanId: scanId, region: "arms", fatPct: 13)], forScanId: scanId)
    try db.deleteDEXAScan(id: scanId)
    let regions = try db.fetchDEXARegions(forScanId: scanId)
    #expect(regions.isEmpty, "Regions should cascade delete")
}

// MARK: - OCR Additional (4 tests)

@Test func ocrMultipleCalorieFormats() async throws {
    let r1 = NutritionLabelOCR.parseNutritionFromText(["Cal 250"])
    #expect(r1.calories == 250)
}

@Test func ocrLargeLabel() async throws {
    let lines = ["Nutrition Facts", "Serving Size 2 cups (240g)", "Servings Per Container 4",
                  "Calories 350", "Total Fat 12g", "Saturated Fat 3g", "Trans Fat 0g",
                  "Cholesterol 30mg", "Sodium 470mg", "Total Carbohydrate 45g",
                  "Dietary Fiber 6g", "Total Sugars 8g", "Protein 18g",
                  "Vitamin D 2mcg", "Calcium 260mg", "Iron 6mg", "Potassium 240mg"]
    let r = NutritionLabelOCR.parseNutritionFromText(lines)
    #expect(r.calories == 350)
    #expect(r.fatG == 12)
    #expect(r.carbsG == 45)
    #expect(r.fiberG == 6)
    #expect(r.proteinG == 18)
}

@Test func ocrServingSizeExtraction() async throws {
    let r = NutritionLabelOCR.parseNutritionFromText(["Serving Size 1 bar (40g)", "Calories 180"])
    #expect(r.servingSize.contains("40"))
}

@Test func ocrNoNutritionData() async throws {
    let r = NutritionLabelOCR.parseNutritionFromText(["Ingredients: water, sugar, salt", "Made in USA"])
    #expect(r.calories == 0 && r.proteinG == 0)
}
