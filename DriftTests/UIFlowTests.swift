import Foundation
import Testing
@testable import Drift

// MARK: - Weight Entry CRUD (6 tests)

@Test func weightInsertAndFetch() async throws {
    let db = try AppDatabase.empty()
    var e = WeightEntry(date: "2026-03-28", weightKg: 54.5)
    try db.saveWeightEntry(&e)
    let all = try db.fetchWeightEntries()
    #expect(all.count == 1 && all[0].weightKg == 54.5)
}

@Test func weightUpsertSameDate() async throws {
    let db = try AppDatabase.empty()
    var e1 = WeightEntry(date: "2026-03-28", weightKg: 54.5)
    try db.saveWeightEntry(&e1)
    var e2 = WeightEntry(date: "2026-03-28", weightKg: 55.0) // same date
    try db.saveWeightEntry(&e2)
    let all = try db.fetchWeightEntries()
    #expect(all.count == 1, "Upsert should not create duplicate")
    #expect(all[0].weightKg == 55.0, "Should have updated weight")
}

@Test func weightDelete() async throws {
    let db = try AppDatabase.empty()
    var e = WeightEntry(date: "2026-03-28", weightKg: 54.5)
    try db.saveWeightEntry(&e)
    let fetched = try db.fetchWeightEntries()
    try db.deleteWeightEntry(id: fetched[0].id!)
    #expect(try db.fetchWeightEntries().isEmpty)
}

@Test func weightFetchWithDateRange() async throws {
    let db = try AppDatabase.empty()
    for d in ["2026-01-01", "2026-02-01", "2026-03-01"] {
        var e = WeightEntry(date: d, weightKg: 60.0)
        try db.saveWeightEntry(&e)
    }
    let filtered = try db.fetchWeightEntries(from: "2026-02-01")
    #expect(filtered.count == 2) // Feb + Mar
}

@Test func weightOrderDescByDate() async throws {
    let db = try AppDatabase.empty()
    for d in ["2026-03-01", "2026-01-01", "2026-02-01"] {
        var e = WeightEntry(date: d, weightKg: 60.0)
        try db.saveWeightEntry(&e)
    }
    let all = try db.fetchWeightEntries()
    #expect(all[0].date == "2026-03-01")
    #expect(all[2].date == "2026-01-01")
}

@Test func weightLatestFetch() async throws {
    let db = try AppDatabase.empty()
    for (d, w) in [("2026-01-01", 60.0), ("2026-03-01", 55.0)] {
        var e = WeightEntry(date: d, weightKg: w)
        try db.saveWeightEntry(&e)
    }
    let latest = try db.fetchLatestWeight()
    #expect(latest?.date == "2026-03-01")
    #expect(latest?.weightKg == 55.0)
}

// MARK: - Food Logging (8 tests)

@Test func foodLoggingFlow() async throws {
    let db = try AppDatabase.empty()
    var meal = MealLog(date: "2026-03-28", mealType: "lunch")
    try db.saveMealLog(&meal)
    var entry = FoodEntry(mealLogId: meal.id!, foodName: "Dal", servingSizeG: 200, servings: 2, calories: 210, proteinG: 14, carbsG: 36, fatG: 1, fiberG: 8)
    try db.saveFoodEntry(&entry)
    let nutrition = try db.fetchDailyNutrition(for: "2026-03-28")
    #expect(nutrition.calories == 420) // 210 * 2
    #expect(nutrition.proteinG == 28)
}

@Test func foodMultipleMeals() async throws {
    let db = try AppDatabase.empty()
    var b = MealLog(date: "2026-03-28", mealType: "breakfast")
    var l = MealLog(date: "2026-03-28", mealType: "lunch")
    try db.saveMealLog(&b); try db.saveMealLog(&l)
    var e1 = FoodEntry(mealLogId: b.id!, foodName: "Oats", servingSizeG: 100, servings: 1, calories: 150)
    var e2 = FoodEntry(mealLogId: l.id!, foodName: "Rice", servingSizeG: 200, servings: 1, calories: 260)
    try db.saveFoodEntry(&e1); try db.saveFoodEntry(&e2)
    let n = try db.fetchDailyNutrition(for: "2026-03-28")
    #expect(n.calories == 410)
}

@Test func foodDeleteEntry() async throws {
    let db = try AppDatabase.empty()
    var m = MealLog(date: "2026-03-28", mealType: "lunch")
    try db.saveMealLog(&m)
    var e = FoodEntry(mealLogId: m.id!, foodName: "X", servingSizeG: 100, servings: 1, calories: 500)
    try db.saveFoodEntry(&e)
    let fetched = try db.fetchFoodEntries(forMealLog: m.id!)
    try db.deleteFoodEntry(id: fetched[0].id!)
    let n = try db.fetchDailyNutrition(for: "2026-03-28")
    #expect(n.calories == 0)
}

@Test func foodSearchFindsResults() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var f = Food(name: "Moong Dal", category: "Indian", servingSize: 200, servingUnit: "g", calories: 210, proteinG: 14, carbsG: 36, fatG: 1, fiberG: 8)
        try f.insert(dbConn)
    }
    let results = try db.searchFoods(query: "dal")
    #expect(results.count == 1 && results[0].name == "Moong Dal")
}

@Test func foodSearchCaseInsensitive() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var f = Food(name: "Chicken Breast", category: "Protein", servingSize: 150, servingUnit: "g", calories: 248, proteinG: 46)
        try f.insert(dbConn)
    }
    #expect(try db.searchFoods(query: "chicken").count == 1)
    #expect(try db.searchFoods(query: "CHICKEN").count == 1)
}

@Test func foodSearchEmpty() async throws {
    let db = try AppDatabase.empty()
    #expect(try db.searchFoods(query: "").isEmpty)
    #expect(try db.searchFoods(query: "nonexistent").isEmpty)
}

@Test func foodNutritionZeroForNoEntries() async throws {
    let db = try AppDatabase.empty()
    let n = try db.fetchDailyNutrition(for: "2026-03-28")
    #expect(n.calories == 0 && n.proteinG == 0)
}

@Test func foodServingsMultiply() async throws {
    let db = try AppDatabase.empty()
    var m = MealLog(date: "2026-03-28", mealType: "lunch")
    try db.saveMealLog(&m)
    var e = FoodEntry(mealLogId: m.id!, foodName: "Rice", servingSizeG: 200, servings: 3, calories: 260, proteinG: 5, carbsG: 57, fatG: 0.5, fiberG: 0.6)
    try db.saveFoodEntry(&e)
    let n = try db.fetchDailyNutrition(for: "2026-03-28")
    #expect(abs(n.calories - 780) < 1) // 260 * 3
    #expect(abs(n.proteinG - 15) < 1) // 5 * 3
}

// MARK: - Supplements (6 tests)

@Test func supplementCreate() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "Creatine", dosage: "5", unit: "g")
    try db.saveSupplement(&s)
    let all = try db.fetchActiveSupplements()
    #expect(all.count == 1 && all[0].name == "Creatine")
}

@Test func supplementToggle() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "Creatine", dosage: "5", unit: "g")
    try db.saveSupplement(&s)
    let sid = try db.fetchActiveSupplements()[0].id!

    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-28")
    #expect(try db.fetchSupplementLogs(for: "2026-03-28")[0].taken == true)

    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-28")
    #expect(try db.fetchSupplementLogs(for: "2026-03-28")[0].taken == false)
}

@Test func supplementMultiple() async throws {
    let db = try AppDatabase.empty()
    for name in ["A", "B", "C"] {
        var s = Supplement(name: name, sortOrder: 0)
        try db.saveSupplement(&s)
    }
    #expect(try db.fetchActiveSupplements().count == 3)
}

@Test func supplementLogDateRange() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "Test")
    try db.saveSupplement(&s)
    let sid = try db.fetchActiveSupplements()[0].id!

    for d in ["2026-03-25", "2026-03-26", "2026-03-27", "2026-03-28"] {
        try db.toggleSupplementTaken(supplementId: sid, date: d)
    }
    let logs = try db.fetchSupplementLogs(from: "2026-03-26", to: "2026-03-28")
    #expect(logs.count == 3)
}

@Test func supplementDifferentDays() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "X")
    try db.saveSupplement(&s)
    let sid = try db.fetchActiveSupplements()[0].id!
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-27")
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-28")
    #expect(try db.fetchSupplementLogs(for: "2026-03-27").count == 1)
    #expect(try db.fetchSupplementLogs(for: "2026-03-28").count == 1)
}

@Test func supplementDosageDisplay() async throws {
    let s = Supplement(name: "Mg", dosage: "400", unit: "mg")
    #expect(s.dosageDisplay == "400 mg")
    let s2 = Supplement(name: "X")
    #expect(s2.dosageDisplay == "")
}

// MARK: - DEXA Scans (6 tests)

@Test func dexaInsertAndFetch() async throws {
    let db = try AppDatabase.empty()
    var scan = DEXAScan(scanDate: "2026-03-06", fatMassKg: 9.0, leanMassKg: 43.3, bodyFatPct: 16.4)
    try db.saveDEXAScan(&scan)
    let all = try db.fetchDEXAScans()
    #expect(all.count == 1 && all[0].bodyFatPct == 16.4)
}

@Test func dexaUpsertByDate() async throws {
    let db = try AppDatabase.empty()
    var s1 = DEXAScan(scanDate: "2026-03-06", bodyFatPct: 16.4)
    try db.saveDEXAScan(&s1)
    var s2 = DEXAScan(scanDate: "2026-03-06", bodyFatPct: 17.0) // same date
    try db.saveDEXAScan(&s2)
    let all = try db.fetchDEXAScans()
    #expect(all.count == 1, "Upsert by date")
    #expect(all[0].bodyFatPct == 17.0)
}

@Test func dexaMultipleScansOrdered() async throws {
    let db = try AppDatabase.empty()
    for (d, bf) in [("2025-09-26", 25.2), ("2026-01-25", 21.0), ("2026-03-06", 16.4)] {
        var s = DEXAScan(scanDate: d, bodyFatPct: bf)
        try db.saveDEXAScan(&s)
    }
    let all = try db.fetchDEXAScans()
    #expect(all[0].scanDate == "2026-03-06") // most recent first
    #expect(all[2].scanDate == "2025-09-26")
}

@Test func dexaDelete() async throws {
    let db = try AppDatabase.empty()
    var s = DEXAScan(scanDate: "2026-03-06", bodyFatPct: 16.4)
    try db.saveDEXAScan(&s)
    let id = try db.fetchDEXAScans()[0].id!
    try db.deleteDEXAScan(id: id)
    #expect(try db.fetchDEXAScans().isEmpty)
}

@Test func dexaDeleteAll() async throws {
    let db = try AppDatabase.empty()
    for d in ["2025-09-26", "2026-01-25", "2026-03-06"] {
        var s = DEXAScan(scanDate: d, bodyFatPct: 20.0)
        try db.saveDEXAScan(&s)
    }
    try db.deleteAllDEXAScans()
    #expect(try db.fetchDEXAScans().isEmpty)
}

@Test func dexaLbsConversions() async throws {
    let s = DEXAScan(scanDate: "2026-03-06", fatMassKg: 9.0, leanMassKg: 43.3, visceralFatKg: 0.3)
    #expect(abs(s.fatMassLbs! - 19.84) < 0.1)
    #expect(abs(s.leanMassLbs! - 95.5) < 0.1)
    #expect(abs(s.visceralFatLbs! - 0.66) < 0.1)
}

// MARK: - Glucose Import (4 tests)

@Test func glucoseImport() async throws {
    let db = try AppDatabase.empty()
    let readings = [
        GlucoseReading(timestamp: "2026-03-15T08:00:00Z", glucoseMgdl: 95, importBatch: "b1"),
        GlucoseReading(timestamp: "2026-03-15T08:05:00Z", glucoseMgdl: 102, importBatch: "b1"),
        GlucoseReading(timestamp: "2026-03-15T08:10:00Z", glucoseMgdl: 118, importBatch: "b1"),
    ]
    try db.saveGlucoseReadings(readings)
    let f = try db.fetchGlucoseReadings(from: "2026-03-15T00:00:00Z", to: "2026-03-16T00:00:00Z")
    #expect(f.count == 3 && f[0].glucoseMgdl == 95)
}

@Test func glucoseZones() async throws {
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 60).zone == .low)
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 85).zone == .normal)
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 120).zone == .elevated)
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 160).zone == .high)
}

@Test func glucoseEmptyRange() async throws {
    let db = try AppDatabase.empty()
    let f = try db.fetchGlucoseReadings(from: "2026-03-15T00:00:00Z", to: "2026-03-16T00:00:00Z")
    #expect(f.isEmpty)
}

@Test func glucoseOrdering() async throws {
    let db = try AppDatabase.empty()
    try db.saveGlucoseReadings([
        GlucoseReading(timestamp: "2026-03-15T10:00:00Z", glucoseMgdl: 110),
        GlucoseReading(timestamp: "2026-03-15T08:00:00Z", glucoseMgdl: 90),
    ])
    let f = try db.fetchGlucoseReadings(from: "2026-03-15T00:00:00Z", to: "2026-03-16T00:00:00Z")
    #expect(f[0].glucoseMgdl == 90) // earlier first
}

// MARK: - Weight Goal (6 tests)

@Test func goalEncodeDecode() async throws {
    let g = WeightGoal(targetWeightKg: 52.0, monthsToAchieve: 3, startDate: "2026-03-29", startWeightKg: 55.0)
    let data = try JSONEncoder().encode(g)
    let decoded = try JSONDecoder().decode(WeightGoal.self, from: data)
    #expect(decoded.targetWeightKg == 52.0)
    #expect(decoded.monthsToAchieve == 3)
    #expect(decoded.startDate == "2026-03-29")
    #expect(decoded.startWeightKg == 55.0)
}

@Test func goalPersistence() async throws {
    // Save, load, clear - sequential
    let g = WeightGoal(targetWeightKg: 50.0, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 60.0)
    g.save()
    #expect(WeightGoal.load()?.targetWeightKg == 50.0)
    WeightGoal.clear()
    #expect(WeightGoal.load() == nil)
}

@Test func goalProgress() async throws {
    let g = WeightGoal(targetWeightKg: 50.0, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 60.0)
    #expect(abs(g.progress(currentWeightKg: 55.0) - 0.5) < 0.01) // halfway
    #expect(abs(g.progress(currentWeightKg: 60.0) - 0.0) < 0.01) // no progress
    #expect(abs(g.progress(currentWeightKg: 50.0) - 1.0) < 0.01) // done
}

@Test func goalWeeklyRate() async throws {
    // Lose 10kg in 6 months ≈ 26 weeks → -0.385 kg/week
    let g = WeightGoal(targetWeightKg: 50.0, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 60.0)
    #expect(g.requiredWeeklyRateKg < -0.3 && g.requiredWeeklyRateKg > -0.5)
}

@Test func goalOnTrack() async throws {
    let g = WeightGoal(targetWeightKg: 50.0, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 60.0)
    #expect(g.isOnTrack(actualWeeklyRateKg: g.requiredWeeklyRateKg) == .onTrack)
    #expect(g.isOnTrack(actualWeeklyRateKg: g.requiredWeeklyRateKg * 2) == .ahead)
    #expect(g.isOnTrack(actualWeeklyRateKg: 0) == .behind)
}

@Test func goalGaining() async throws {
    let g = WeightGoal(targetWeightKg: 70.0, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 60.0)
    #expect(g.totalChangeKg > 0)
    #expect(g.requiredWeeklyRateKg > 0)
    #expect(g.requiredDailyDeficit > 0) // surplus
}

// MARK: - CSV Parser (4 tests)

@Test func csvSimple() async throws {
    let r = CSVParser.parse(content: "a,b\n1,2\n3,4")
    #expect(r.headers == ["a", "b"])
    #expect(r.rows.count == 2)
}

@Test func csvEmpty() async throws { #expect(CSVParser.parse(content: "").rows.isEmpty) }
@Test func csvHeaderOnly() async throws { #expect(CSVParser.parse(content: "a,b,c").rows.isEmpty) }

@Test func csvQuoted() async throws {
    let r = CSVParser.parse(content: "name,v\n\"hello, world\",42")
    #expect(r.rows[0]["name"] == "hello, world")
}

// MARK: - Lingo CGM Import (2 tests)

@Test func lingoRealFormat() async throws {
    let csv = "Time of Glucose Reading [T=(local time) +/- (time zone offset)], Measurement(mg/dL)\n2026-02-04T20:33-08:00,101\n2026-02-04T18:43-08:00,99\n2026-02-04T17:18-08:00,87"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test_lingo.csv")
    try csv.write(to: url, atomically: true, encoding: .utf8)
    let db = try AppDatabase.empty()
    let result = try CGMImportService.importLingoCSV(url: url, database: db)
    #expect(result.imported == 3 && result.errors == 0)
    try FileManager.default.removeItem(at: url)
}

@Test func lingoTimestampNormalization() async throws {
    let csv = "Time of Glucose Reading [T=(local time) +/- (time zone offset)], Measurement(mg/dL)\n2026-02-04T20:33-08:00,101"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("test2.csv")
    try csv.write(to: url, atomically: true, encoding: .utf8)
    let db = try AppDatabase.empty()
    let r = try CGMImportService.importLingoCSV(url: url, database: db)
    #expect(r.imported == 1)
    try FileManager.default.removeItem(at: url)
}

// MARK: - Model Helpers (5 tests)

@Test func weightEntryLbsConversion() async throws {
    let e = WeightEntry(date: "2026-03-28", weightKg: 54.5)
    #expect(abs(e.weightLbs - 120.15) < 0.1)
}

@Test func foodMacroSummary() async throws {
    let f = Food(name: "Test", category: "X", servingSize: 100, servingUnit: "g", calories: 200, proteinG: 20, carbsG: 30, fatG: 5)
    #expect(f.macroSummary == "200cal 20P 30C 5F")
}

@Test func foodEntryTotals() async throws {
    let e = FoodEntry(mealLogId: 1, foodName: "X", servingSizeG: 100, servings: 2.5, calories: 200, proteinG: 10, carbsG: 30, fatG: 5, fiberG: 3)
    #expect(e.totalCalories == 500)
    #expect(e.totalProtein == 25)
    #expect(e.totalFiber == 7.5)
}

@Test func dailyNutritionZero() async throws {
    let n = DailyNutrition.zero
    #expect(n.calories == 0 && n.proteinG == 0 && n.fatG == 0)
}

@Test func mealTypeProperties() async throws {
    #expect(MealType.breakfast.displayName == "Breakfast")
    #expect(MealType.allCases.count == 4)
}

// MARK: - Database Migrations (2 tests)

@Test func appLaunches() async throws {
    let db = try AppDatabase.empty()
    // Verify all migrations ran without error
    let _ = try db.fetchWeightEntries()
    let _ = try db.fetchActiveSupplements()
    let _ = try db.fetchDEXAScans()
    #expect(true)
}

@Test func emptyDbNoCrash() async throws {
    let db = try AppDatabase.empty()
    #expect(try db.fetchDailyNutrition(for: "2026-03-28").calories == 0)
    #expect(try db.fetchWeightEntries().isEmpty)
    #expect(try db.fetchActiveSupplements().isEmpty)
    #expect(try db.fetchDEXAScans().isEmpty)
    #expect(try db.fetchGlucoseReadings(from: "2026-01-01", to: "2026-12-31").isEmpty)
}
