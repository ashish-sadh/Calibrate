import Foundation
import Testing
import GRDB
@testable import Drift

// MARK: - Weight Trend Robustness (6 tests)

@Test func weightTrendSingleEntry() async throws {
    let entries: [(String, Double)] = [("2026-03-30", 70.0)]
    let t = WeightTrendCalculator.calculateTrend(entries: entries)
    // Single entry might or might not produce a trend depending on min entries
    // But it should NOT crash
    if let t {
        #expect(t.currentEMA > 0)
    }
}

@Test func weightTrendTwoEntries() async throws {
    let entries: [(String, Double)] = [("2026-03-29", 70.0), ("2026-03-30", 69.8)]
    let t = WeightTrendCalculator.calculateTrend(entries: entries)
    if let t {
        #expect(t.currentEMA > 0)
        #expect(t.dataPoints.count == 2)
    }
}

@Test func weightTrendEmptyEntries() async throws {
    let entries: [(String, Double)] = []
    let t = WeightTrendCalculator.calculateTrend(entries: entries)
    #expect(t == nil, "Empty entries should return nil")
}

@Test func weightTrendWithDuplicateDates() async throws {
    let entries: [(String, Double)] = [
        ("2026-03-30", 70.0),
        ("2026-03-30", 70.5), // duplicate date
        ("2026-03-29", 70.2)
    ]
    // Should not crash
    let t = WeightTrendCalculator.calculateTrend(entries: entries)
    #expect(t != nil || t == nil) // just verify no crash
}

@Test func weightTrendExtremeValues() async throws {
    let entries: [(String, Double)] = (0..<7).map {
        (String(format: "2026-03-%02d", $0 + 1), 500.0) // extremely heavy
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)
    if let t {
        #expect(t.currentEMA > 400)
    }
}

@Test func weightTrendConfigCustomAlpha() async throws {
    var config = WeightTrendCalculator.AlgorithmConfig.default
    config.emaAlpha = 0.5
    let entries: [(String, Double)] = (0..<14).map {
        (String(format: "2026-03-%02d", $0 + 1), 70.0 - Double($0) * 0.1)
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries, config: config)
    #expect(t != nil)
    if let t {
        #expect(t.trendDirection == .losing)
    }
}

// MARK: - Barcode Cache Tests (3 tests)

@Test func barcodeCacheSaveAndRetrieve() async throws {
    let db = try AppDatabase.empty()
    let product = OpenFoodFactsService.Product(
        barcode: "1234567890", name: "Test Product", brand: "Test Brand",
        servingSize: "100g", calories: 200, proteinG: 10, carbsG: 30, fatG: 8, fiberG: 5, servingSizeG: 100
    )
    try db.cacheBarcodeProduct(BarcodeCache(from: product))

    let fetched = try db.fetchCachedBarcode("1234567890")
    #expect(fetched != nil)
    #expect(fetched?.name == "Test Product")
    #expect(fetched?.caloriesPer100g == 200)
}

@Test func barcodeCacheReturnsNilOnMiss() async throws {
    let db = try AppDatabase.empty()
    let fetched = try db.fetchCachedBarcode("nonexistent")
    #expect(fetched == nil)
}

@Test func barcodeCacheRecentList() async throws {
    let db = try AppDatabase.empty()
    for i in 0..<5 {
        let product = OpenFoodFactsService.Product(
            barcode: "00000\(i)", name: "Product \(i)", brand: nil,
            servingSize: nil, calories: Double(i * 100), proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, servingSizeG: nil
        )
        try db.cacheBarcodeProduct(BarcodeCache(from: product))
    }
    let recent = try db.fetchRecentBarcodes(limit: 3)
    #expect(recent.count == 3)
}

// MARK: - Supplement Tests (4 tests)

@Test func supplementSaveAndFetch() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "Vitamin D", dosage: "5000", unit: "IU", sortOrder: 0)
    try db.saveSupplement(&s)
    #expect(s.id != nil)

    let all = try db.fetchActiveSupplements()
    #expect(all.count == 1)
    #expect(all[0].name == "Vitamin D")
}

@Test func supplementToggleTaken() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "Creatine", dosage: "5", unit: "g", sortOrder: 0)
    try db.saveSupplement(&s)
    let sid = s.id!

    // Toggle on
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-30")
    var logs = try db.fetchSupplementLogs(for: "2026-03-30")
    #expect(logs.count == 1)
    #expect(logs[0].taken == true)

    // Toggle off
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-30")
    logs = try db.fetchSupplementLogs(for: "2026-03-30")
    #expect(logs[0].taken == false)
}

@Test func supplementLogsByDateRange() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "Fish Oil", dosage: "1", unit: "g", sortOrder: 0)
    try db.saveSupplement(&s)
    let sid = s.id!

    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-28")
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-29")
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-30")

    let logs = try db.fetchSupplementLogs(from: "2026-03-29", to: "2026-03-30")
    #expect(logs.count == 2, "Should get 2 logs in range: \(logs.count)")
}

@Test func supplementDifferentDates() async throws {
    let db = try AppDatabase.empty()
    var s = Supplement(name: "Zinc", dosage: "15", unit: "mg", sortOrder: 0)
    try db.saveSupplement(&s)
    let sid = s.id!

    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-29")
    try db.toggleSupplementTaken(supplementId: sid, date: "2026-03-30")

    let logs29 = try db.fetchSupplementLogs(for: "2026-03-29")
    let logs30 = try db.fetchSupplementLogs(for: "2026-03-30")
    #expect(logs29.count == 1)
    #expect(logs30.count == 1)
}

// MARK: - Recovery Estimator Tests (3 tests)

@Test func recoveryEstimatorNormalValues() async throws {
    let (score, level) = RecoveryEstimator.calculateRecovery(hrvMs: 50, restingHR: 60, sleepHours: 7.5)
    #expect(score > 0 && score <= 100)
    #expect(level == .green || level == .yellow)
}

@Test func recoveryEstimatorLowValues() async throws {
    let (score, level) = RecoveryEstimator.calculateRecovery(hrvMs: 15, restingHR: 80, sleepHours: 4)
    #expect(score < 60, "Low inputs should give low recovery: \(score)")
    #expect(level == .red || level == .yellow)
}

@Test func recoveryEstimatorZeroInputs() async throws {
    let (score, _) = RecoveryEstimator.calculateRecovery(hrvMs: 0, restingHR: 0, sleepHours: 0)
    #expect(score >= 0, "Should not crash or go negative")
}

// MARK: - Date Formatter Tests (2 tests)

@Test func dateFormatterTodayString() async throws {
    let today = DateFormatters.todayString
    #expect(!today.isEmpty)
    #expect(today.count == 10, "Should be YYYY-MM-DD format: \(today)")
    #expect(today.contains("-"))
}

@Test func dateFormatterRoundTrip() async throws {
    let dateStr = "2026-03-30"
    let date = DateFormatters.dateOnly.date(from: dateStr)
    #expect(date != nil)
    if let date {
        let back = DateFormatters.dateOnly.string(from: date)
        #expect(back == dateStr)
    }
}
