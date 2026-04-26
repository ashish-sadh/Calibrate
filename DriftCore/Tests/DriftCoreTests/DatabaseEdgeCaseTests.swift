import Foundation
@testable import DriftCore
import Testing
import GRDB

// MARK: - Glucose Reading Tests (5 tests)

@Test func glucoseReadingSaveAndFetch() async throws {
    let db = try AppDatabase.empty()
    let readings = [
        GlucoseReading(timestamp: "2026-03-30T10:00:00Z", glucoseMgdl: 95),
        GlucoseReading(timestamp: "2026-03-30T12:00:00Z", glucoseMgdl: 120),
        GlucoseReading(timestamp: "2026-03-30T14:00:00Z", glucoseMgdl: 88),
    ]
    try db.saveGlucoseReadings(readings)

    let fetched = try db.fetchGlucoseReadings(from: "2026-03-30T00:00:00Z", to: "2026-03-31T00:00:00Z")
    #expect(fetched.count == 3)
    #expect(fetched[0].glucoseMgdl == 95) // ordered by timestamp ascending: 10:00 first
}

@Test func glucoseZoneClassification() async throws {
    let low = GlucoseReading(timestamp: "", glucoseMgdl: 55)
    #expect(low.zone == .low)

    let normal = GlucoseReading(timestamp: "", glucoseMgdl: 85)
    #expect(normal.zone == .normal)

    let elevated = GlucoseReading(timestamp: "", glucoseMgdl: 130)
    #expect(elevated.zone == .elevated)

    let high = GlucoseReading(timestamp: "", glucoseMgdl: 180)
    #expect(high.zone == .high)
}

@Test func glucoseZoneBoundaryValues() async throws {
    let at70 = GlucoseReading(timestamp: "", glucoseMgdl: 70)
    #expect(at70.zone == .normal, "70 should be normal, not low")

    let at100 = GlucoseReading(timestamp: "", glucoseMgdl: 100)
    #expect(at100.zone == .elevated, "100 should be elevated")

    let at140 = GlucoseReading(timestamp: "", glucoseMgdl: 140)
    #expect(at140.zone == .high, "140 should be high")
}

@Test func glucoseEmptyDateRange() async throws {
    let db = try AppDatabase.empty()
    let fetched = try db.fetchGlucoseReadings(from: "2026-01-01", to: "2026-01-02")
    #expect(fetched.isEmpty)
}

@Test func glucoseReadingDateFiltering() async throws {
    let db = try AppDatabase.empty()
    let readings = [
        GlucoseReading(timestamp: "2026-03-29T10:00:00Z", glucoseMgdl: 90),
        GlucoseReading(timestamp: "2026-03-30T10:00:00Z", glucoseMgdl: 100),
        GlucoseReading(timestamp: "2026-03-31T10:00:00Z", glucoseMgdl: 110),
    ]
    try db.saveGlucoseReadings(readings)

    let march30Only = try db.fetchGlucoseReadings(from: "2026-03-30T00:00:00Z", to: "2026-03-30T23:59:59Z")
    #expect(march30Only.count == 1)
    #expect(march30Only[0].glucoseMgdl == 100)
}

// MARK: - DEXA Scan Tests (4 tests)

@Test func dexaScanSaveAndFetch() async throws {
    let db = try AppDatabase.empty()
    var scan = DEXAScan(
        scanDate: "2026-03-30",
        location: "BodySpec",
        totalMassKg: 70, fatMassKg: 14, leanMassKg: 53, boneMassKg: 3,
        bodyFatPct: 20
    )
    try db.saveDEXAScan(&scan)
    #expect(scan.id != nil)

    let scans = try db.fetchDEXAScans()
    #expect(scans.count == 1)
    #expect(scans[0].bodyFatPct == 20)
}

@Test func dexaScanUpsertSameDate() async throws {
    let db = try AppDatabase.empty()
    var scan1 = DEXAScan(scanDate: "2026-03-30", bodyFatPct: 20)
    try db.saveDEXAScan(&scan1)

    var scan2 = DEXAScan(scanDate: "2026-03-30", bodyFatPct: 19) // same date, updated
    try db.saveDEXAScan(&scan2)

    let scans = try db.fetchDEXAScans()
    #expect(scans.count == 1, "Should upsert, not create duplicate")
    #expect(scans[0].bodyFatPct == 19, "Should have updated value")
}

@Test func dexaScanDelete() async throws {
    let db = try AppDatabase.empty()
    var scan = DEXAScan(scanDate: "2026-03-30", bodyFatPct: 20)
    try db.saveDEXAScan(&scan)
    guard let id = scan.id else { Issue.record("No scan ID"); return }

    try db.deleteDEXAScan(id: id)
    let scans = try db.fetchDEXAScans()
    #expect(scans.isEmpty)
}

@Test func dexaRegionsCascadeOnScanDelete() async throws {
    let db = try AppDatabase.empty()
    var scan = DEXAScan(scanDate: "2026-03-30", bodyFatPct: 20)
    try db.saveDEXAScan(&scan)
    guard let scanId = scan.id else { Issue.record("No scan ID"); return }

    let regions = [
        DEXARegion(scanId: scanId, region: "Left Arm", fatPct: 15),
        DEXARegion(scanId: scanId, region: "Right Arm", fatPct: 16),
    ]
    try db.saveDEXARegions(regions, forScanId: scanId)

    let fetchedRegions = try db.fetchDEXARegions(forScanId: scanId)
    #expect(fetchedRegions.count == 2)

    // Delete scan should cascade to regions
    try db.deleteDEXAScan(id: scanId)
    let remainingRegions = try db.fetchDEXARegions(forScanId: scanId)
    #expect(remainingRegions.isEmpty, "Regions should cascade delete")
}

// MARK: - Favorite Food Tests (3 tests)

@Test func favoriteFoodSaveAndFetch() async throws {
    let db = try AppDatabase.empty()
    var fav = SavedFood(name: "Morning Oats", calories: 350, proteinG: 15, carbsG: 50, fatG: 10, fiberG: 6)
    try db.saveFavorite(&fav)
    #expect(fav.id != nil)

    let all = try db.fetchFavorites()
    #expect(all.count == 1)
    #expect(all[0].name == "Morning Oats")
}

@Test func favoriteFoodDelete() async throws {
    let db = try AppDatabase.empty()
    var fav = SavedFood(name: "Smoothie", calories: 280)
    try db.saveFavorite(&fav)
    guard let id = fav.id else { Issue.record("No fav ID"); return }

    try db.deleteFavorite(id: id)
    let all = try db.fetchFavorites()
    #expect(all.isEmpty)
}

@Test func favoriteFoodMacroSummary() async throws {
    let fav = SavedFood(name: "Test", calories: 500, proteinG: 30, carbsG: 45, fatG: 20)
    #expect(fav.macroSummary == "500cal 30P 45C 20F")
}

// MARK: - Lab Report Tests (3 tests)

@Test func labReportSaveAndFetch() async throws {
    let db = try AppDatabase.empty()
    var report = LabReport(
        reportDate: "2026-03-30",
        labName: "Quest Diagnostics",
        fileName: "test.pdf"
    )
    try db.saveLabReport(&report)
    #expect(report.id != nil)

    let reports = try db.fetchLabReports()
    #expect(reports.count == 1)
    #expect(reports[0].labName == "Quest Diagnostics")
}

@Test func labReportDeleteCascadesBiomarkers() async throws {
    let db = try AppDatabase.empty()
    var report = LabReport(reportDate: "2026-03-30", labName: "Quest", fileName: "test.pdf")
    try db.saveLabReport(&report)
    guard let reportId = report.id else { Issue.record("No report ID"); return }

    let results = [
        BiomarkerResult(reportId: reportId, biomarkerId: "glucose", value: 95, unit: "mg/dL"),
        BiomarkerResult(reportId: reportId, biomarkerId: "hba1c", value: 5.2, unit: "%"),
    ]
    try db.saveBiomarkerResults(results)

    let fetched = try db.fetchBiomarkerResults(forReportId: reportId)
    #expect(fetched.count == 2)

    try db.deleteLabReport(id: reportId)
    let remaining = try db.fetchBiomarkerResults(forReportId: reportId)
    #expect(remaining.isEmpty, "Biomarker results should cascade delete")
}

@Test func biomarkerResultsByBiomarkerId() async throws {
    let db = try AppDatabase.empty()
    var report1 = LabReport(reportDate: "2026-01-01", labName: "Lab1", fileName: "1.pdf")
    var report2 = LabReport(reportDate: "2026-03-01", labName: "Lab2", fileName: "2.pdf")
    try db.saveLabReport(&report1)
    try db.saveLabReport(&report2)

    let results = [
        BiomarkerResult(reportId: report1.id!, biomarkerId: "glucose", value: 95, unit: "mg/dL"),
        BiomarkerResult(reportId: report2.id!, biomarkerId: "glucose", value: 90, unit: "mg/dL"),
        BiomarkerResult(reportId: report1.id!, biomarkerId: "hba1c", value: 5.2, unit: "%"),
    ]
    try db.saveBiomarkerResults(results)

    let glucoseResults = try db.fetchBiomarkerResults(forBiomarkerId: "glucose")
    #expect(glucoseResults.count == 2, "Should find 2 glucose results")
}

// MARK: - CSV Parser Tests (3 tests)

@Test func csvParserEmptyContent() async throws {
    let result = CSVParser.parse(content: "")
    #expect(result.headers.isEmpty)
    #expect(result.rows.isEmpty)
}

@Test func csvParserQuotedCommas() async throws {
    let csv = """
    Name,Description
    "Bench Press","Chest, shoulders, triceps"
    Squat,Legs
    """
    let result = CSVParser.parse(content: csv)
    #expect(result.rows.count == 2)
    #expect(result.rows[0]["Description"] == "Chest, shoulders, triceps")
}

@Test func csvParserMissingColumns() async throws {
    let csv = """
    A,B,C
    1,2
    """
    let result = CSVParser.parse(content: csv)
    #expect(result.rows.count == 1)
    #expect(result.rows[0]["A"] == "1")
    #expect(result.rows[0]["B"] == "2")
    #expect(result.rows[0]["C"] == nil, "Missing column should be nil")
}

// MARK: - Micronutrient fields (#442)

@Test func foodEntryMicronutrientsNilByDefault() {
    let entry = FoodEntry(foodName: "Egg", servingSizeG: 50, calories: 70)
    #expect(entry.sodiumMg == nil)
    #expect(entry.sugarG == nil)
    #expect(entry.totalSodium == 0, "totalSodium should COALESCE nil to 0")
    #expect(entry.totalSugar == 0, "totalSugar should COALESCE nil to 0")
}

@Test func foodEntryMicronutrientsScaleWithServings() {
    var entry = FoodEntry(foodName: "Chips", servingSizeG: 30, servings: 2, calories: 150,
                          sodiumMg: 200, sugarG: 1)
    #expect(entry.totalSodium == 400)
    #expect(entry.totalSugar == 2)
    entry.servings = 0.5
    #expect(entry.totalSodium == 100)
    #expect(entry.totalSugar == 0.5)
}

@Test func foodEntryConvenienceInitCopiesMicronutrients() {
    let food = Food(name: "Banana", category: "Fruit", servingSize: 120,
                    servingUnit: "medium", calories: 105, proteinG: 1.3,
                    carbsG: 27, fatG: 0.4, fiberG: 3.1,
                    sodiumMg: 1, sugarG: 14)
    let entry = FoodEntry(food: food, servings: 1.5, mealType: "snack")
    #expect(entry.sodiumMg == 1)
    #expect(entry.sugarG == 14)
    #expect(entry.totalSodium == 1.5)
    #expect(entry.totalSugar == 21)
    #expect(entry.mealType == "snack")
    #expect(entry.foodName == "Banana")
}

@Test func foodEntryConvenienceInitWithNilMicronutrients() {
    let food = Food(name: "Rice", category: "Grains", servingSize: 186,
                    servingUnit: "cup cooked", calories: 242)
    let entry = FoodEntry(food: food, servings: 1)
    #expect(entry.sodiumMg == nil)
    #expect(entry.sugarG == nil)
    #expect(entry.totalSodium == 0)
    #expect(entry.totalSugar == 0)
}

@Test func foodMicronutrientsNilByDefault() {
    let food = Food(name: "Plain food", category: "Other", servingSize: 100,
                    servingUnit: "g", calories: 100)
    #expect(food.sodiumMg == nil)
    #expect(food.sugarG == nil)
}

@Test func foodMicronutrientsRoundTripViaJSON() throws {
    let food = Food(name: "Soup", category: "Soups", servingSize: 240,
                    servingUnit: "cup", calories: 80, sodiumMg: 480, sugarG: 3)
    let data = try JSONEncoder().encode(food)
    let decoded = try JSONDecoder().decode(Food.self, from: data)
    #expect(decoded.sodiumMg == 480)
    #expect(decoded.sugarG == 3)
}
