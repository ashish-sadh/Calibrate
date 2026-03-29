import Foundation
import Testing
@testable import Drift

// MARK: - EMA Core (12 tests)

@Test func emaWithSingleEntry() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: [(date: "2026-03-01", weightKg: 55.0)])!
    #expect(t.currentEMA == 55.0)
    #expect(t.weeklyRateKg == 0)
}

@Test func emaSmoothing() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (date: "2026-03-01", weightKg: 55.0), (date: "2026-03-02", weightKg: 54.0)
    ])!
    #expect(abs(t.currentEMA - 54.9) < 0.01) // 0.1*54 + 0.9*55
}

@Test func emaSmoothingMultipleEntries() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<5).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 60.0 - Double($0))
    })!
    #expect(t.currentEMA > 56.0 && t.currentEMA < 60.0)
}

@Test func emaLagsBehindDrop() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (date: "2026-03-01", weightKg: 80.0), (date: "2026-03-02", weightKg: 70.0)
    ])!
    #expect(abs(t.currentEMA - 79.0) < 0.01) // heavily lagged
}

@Test func emptyEntriesReturnsNil() async throws {
    #expect(WeightTrendCalculator.calculateTrend(entries: []) == nil)
}

@Test func invalidDatesSkipped() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (date: "bad", weightKg: 55.0), (date: "2026-03-01", weightKg: 55.0)
    ])!
    #expect(t.dataPoints.count == 1)
}

@Test func unsortedInputGetsSorted() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (date: "2026-03-05", weightKg: 54.0), (date: "2026-03-01", weightKg: 56.0), (date: "2026-03-03", weightKg: 55.0)
    ])!
    #expect(t.dataPoints[0].dateString == "2026-03-01")
    #expect(t.dataPoints.last?.dateString == "2026-03-05")
}

@Test func emaWithConstantWeight() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<20).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 70.0)
    })!
    #expect(abs(t.currentEMA - 70.0) < 0.01)
    #expect(t.trendDirection == .maintaining)
}

@Test func emaWith2kgNoise() async throws {
    // True weight 65, noise ±1kg
    let entries: [(String, Double)] = (0..<30).map { day in
        let date = Calendar.current.date(byAdding: .day, value: -29 + day, to: Date())!
        return (DateFormatters.dateOnly.string(from: date), 65.0 + (day % 2 == 0 ? 1.0 : -1.0))
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(abs(t.currentEMA - 65.0) < 1.5, "EMA should be near 65 despite noise")
}

@Test func emaVeryHighAlpha() async throws {
    let config = WeightTrendCalculator.AlgorithmConfig(emaAlpha: 0.5, regressionWindowDays: 21, kcalPerKg: 6000, maintainingThresholdKgPerWeek: 0.05)
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (date: "2026-03-01", weightKg: 80.0), (date: "2026-03-02", weightKg: 70.0)
    ], config: config)!
    #expect(abs(t.currentEMA - 75.0) < 0.01) // 0.5*70 + 0.5*80
}

@Test func emaVeryLowAlpha() async throws {
    let config = WeightTrendCalculator.AlgorithmConfig(emaAlpha: 0.01, regressionWindowDays: 21, kcalPerKg: 6000, maintainingThresholdKgPerWeek: 0.05)
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (date: "2026-03-01", weightKg: 80.0), (date: "2026-03-02", weightKg: 70.0)
    ], config: config)!
    #expect(abs(t.currentEMA - 79.9) < 0.01) // barely moves
}

@Test func ema365DaysData() async throws {
    let entries: [(String, Double)] = (0..<365).map { day in
        let date = Calendar.current.date(byAdding: .day, value: -364 + day, to: Date())!
        return (DateFormatters.dateOnly.string(from: date), 80.0 - Double(day) * 0.02)
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.dataPoints.count == 365)
    #expect(t.trendDirection == .losing)
}

// MARK: - Trend Direction (5 tests)

@Test func losingTrend() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<20).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 60.0 - Double($0) * 0.1)
    })!
    #expect(t.trendDirection == .losing)
    #expect(t.weeklyRateKg < 0)
}

@Test func gainingTrend() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<20).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 55.0 + Double($0) * 0.1)
    })!
    #expect(t.trendDirection == .gaining)
    #expect(t.weeklyRateKg > 0)
}

@Test func maintainingTrend() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<14).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 55.0 + ($0 % 2 == 0 ? 0.02 : -0.02))
    })!
    #expect(t.trendDirection == .maintaining)
}

@Test func waterWeightSpikeDoesntChangeTrend() async throws {
    let today = Date()
    var entries: [(String, Double)] = (0..<14).map { day in
        let d = Calendar.current.date(byAdding: .day, value: -13 + day, to: today)!
        return (DateFormatters.dateOnly.string(from: d), 60.0 - Double(day) * 0.05)
    }
    entries[11] = (entries[11].0, entries[11].1 + 2.0) // +2kg spike
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.trendDirection == .losing, "Single spike shouldn't change direction")
}

@Test func twoEntriesNoTrendCrash() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (date: "2026-03-01", weightKg: 55.0), (date: "2026-03-28", weightKg: 54.0)
    ])!
    #expect(t.weeklyRateKg < 0)
}

// MARK: - Weight Changes (actual scale weight) (12 tests)

func makeEntries(days: Int, startKg: Double, ratePerDay: Double) -> [(date: String, weightKg: Double)] {
    let today = Date()
    return (0..<days).map { day in
        let d = Calendar.current.date(byAdding: .day, value: -(days - 1) + day, to: today)!
        return (date: DateFormatters.dateOnly.string(from: d), weightKg: startKg + Double(day) * ratePerDay)
    }
}

@Test func changesDecreasing() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: makeEntries(days: 15, startKg: 65, ratePerDay: -0.2))!
    if let v = t.weightChanges.sevenDay { #expect(v < 0, "Should decrease: \(v)") }
    if let v = t.weightChanges.fourteenDay { #expect(v < 0, "Should decrease: \(v)") }
}

@Test func changesIncreasing() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: makeEntries(days: 15, startKg: 55, ratePerDay: 0.2))!
    if let v = t.weightChanges.sevenDay { #expect(v > 0, "Should increase: \(v)") }
}

@Test func changesFlat() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: makeEntries(days: 15, startKg: 70, ratePerDay: 0))!
    if let v = t.weightChanges.sevenDay { #expect(abs(v) < 0.1, "Should be ~0: \(v)") }
}

@Test func changesSparseDecreasing() async throws {
    let today = Date()
    let cal = Calendar.current
    let entries: [(String, Double)] = [
        (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -21, to: today)!), 63.5),
        (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -14, to: today)!), 63.0),
        (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -7, to: today)!), 62.5),
        (DateFormatters.dateOnly.string(from: today), 62.2),
    ]
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    if let v = t.weightChanges.sevenDay { #expect(v < 0, "Sparse decrease: \(v)") }
    if let v = t.weightChanges.fourteenDay { #expect(v < 0, "Sparse 14d: \(v)") }
}

@Test func changesNilForShortData() async throws {
    let today = Date()
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (DateFormatters.dateOnly.string(from: Calendar.current.date(byAdding: .day, value: -1, to: today)!), 70.0),
        (DateFormatters.dateOnly.string(from: today), 69.5),
    ])!
    #expect(t.weightChanges.thirtyDay == nil)
    #expect(t.weightChanges.ninetyDay == nil)
}

@Test func changes3dayMagnitude() async throws {
    let today = Date()
    let cal = Calendar.current
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -3, to: today)!), 70.0),
        (DateFormatters.dateOnly.string(from: today), 68.0),
    ])!
    if let v = t.weightChanges.threeDay {
        #expect(abs(v - (-2.0)) < 0.1, "3-day should be -2.0, got \(v)")
    }
}

@Test func changes90dayWithFullData() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: makeEntries(days: 100, startKg: 80, ratePerDay: -0.05))!
    #expect(t.weightChanges.ninetyDay != nil)
    if let v = t.weightChanges.ninetyDay { #expect(v < -3, "90-day should be significant loss: \(v)") }
}

@Test func changesHandleBounceback() async throws {
    // Weight goes down then bounces back up
    let today = Date()
    let cal = Calendar.current
    let entries: [(String, Double)] = [
        (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -14, to: today)!), 65.0),
        (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -7, to: today)!), 63.0), // dip
        (DateFormatters.dateOnly.string(from: today), 64.5), // bounce back
    ]
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    if let v = t.weightChanges.sevenDay { #expect(v > 0, "Bounceback: 7d should be positive: \(v)") }
    if let v = t.weightChanges.fourteenDay { #expect(v < 0, "But 14d still negative: \(v)") }
}

// MARK: - Deficit (6 tests)

@Test func deficitCalculation() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<21).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 60.0 - Double($0) * 0.071)
    })!
    #expect(t.estimatedDailyDeficit < 0 && t.estimatedDailyDeficit > -1000)
}

@Test func deficitZeroForFlat() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<21).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 70.0)
    })!
    #expect(abs(t.estimatedDailyDeficit) < 50)
}

@Test func deficitPositiveForGaining() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<21).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 55.0 + Double($0) * 0.05)
    })!
    #expect(t.estimatedDailyDeficit > 0)
}

@Test func deficitRespondsToConfig() async throws {
    let entries: [(String, Double)] = (0..<21).map {
        (String(format: "2026-03-%02d", $0+1), 60.0 - Double($0) * 0.1)
    }
    let c = WeightTrendCalculator.calculateTrend(entries: entries, config: .conservative)!
    let r = WeightTrendCalculator.calculateTrend(entries: entries, config: .responsive)!
    #expect(abs(r.estimatedDailyDeficit) > abs(c.estimatedDailyDeficit))
}

@Test func deficitReasonableFor500calCut() async throws {
    // 500 cal/day deficit ≈ 0.58 kg/week at 6000 kcal/kg
    // So 0.58/7 = 0.083 kg/day loss
    let entries: [(String, Double)] = (0..<21).map {
        (String(format: "2026-03-%02d", $0+1), 70.0 - Double($0) * 0.083)
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.estimatedDailyDeficit < -300 && t.estimatedDailyDeficit > -700,
            "Expected ~-500 kcal deficit, got \(t.estimatedDailyDeficit)")
}

@Test func surplusReasonableFor300calExcess() async throws {
    // 300 cal surplus ≈ 0.35 kg/week gain
    let entries: [(String, Double)] = (0..<21).map {
        (String(format: "2026-03-%02d", $0+1), 60.0 + Double($0) * 0.05)
    }
    let t = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(t.estimatedDailyDeficit > 100 && t.estimatedDailyDeficit < 500,
            "Expected ~300 kcal surplus, got \(t.estimatedDailyDeficit)")
}

// MARK: - Projection (3 tests)

@Test func projection30Day() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<20).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 60.0 - Double($0) * 0.1)
    })!
    #expect(t.projection30Day != nil && t.projection30Day! < t.currentEMA)
}

@Test func projectionNilForFewEntries() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: [
        (date: "2026-03-01", weightKg: 55.0), (date: "2026-03-02", weightKg: 54.8)
    ])!
    #expect(t.projection30Day == nil)
}

@Test func projectionGaining() async throws {
    let t = WeightTrendCalculator.calculateTrend(entries: (0..<20).map {
        (date: String(format: "2026-03-%02d", $0+1), weightKg: 55.0 + Double($0) * 0.1)
    })!
    #expect(t.projection30Day! > t.currentEMA)
}

// MARK: - Linear Regression (3 tests)

@Test func linearRegressionFlat() async throws {
    let pts = [
        WeightTrendCalculator.WeightDataPoint(date: Date(), dateString: "", actualWeight: 55, emaWeight: 55),
        WeightTrendCalculator.WeightDataPoint(date: Date().addingTimeInterval(86400), dateString: "", actualWeight: 55, emaWeight: 55),
    ]
    #expect(abs(WeightTrendCalculator.linearRegressionSlope(points: pts)) < 0.001)
}

@Test func linearRegressionNegative() async throws {
    let base = Date()
    let pts = (0..<10).map {
        WeightTrendCalculator.WeightDataPoint(date: base.addingTimeInterval(Double($0)*86400), dateString: "", actualWeight: nil, emaWeight: 60.0 - Double($0)*0.5)
    }
    let slope = WeightTrendCalculator.linearRegressionSlope(points: pts)
    #expect(slope < 0 && abs(slope - (-0.5)) < 0.05)
}

@Test func linearRegressionSingle() async throws {
    #expect(WeightTrendCalculator.linearRegressionSlope(points: [
        WeightTrendCalculator.WeightDataPoint(date: Date(), dateString: "", actualWeight: 55, emaWeight: 55)
    ]) == 0)
}

// MARK: - Config (3 tests)

@Test func configDefaults() async throws {
    let c = WeightTrendCalculator.AlgorithmConfig.default
    #expect(c.emaAlpha == 0.1 && c.regressionWindowDays == 21 && c.kcalPerKg == 6000)
}

@Test func configSaveLoad() async throws {
    var c = WeightTrendCalculator.AlgorithmConfig.default
    c.kcalPerKg = 7777
    WeightTrendCalculator.saveConfig(c)
    #expect(WeightTrendCalculator.loadConfig().kcalPerKg == 7777)
    WeightTrendCalculator.saveConfig(.default)
}

@Test func configPresetOrdering() async throws {
    #expect(WeightTrendCalculator.AlgorithmConfig.conservative.kcalPerKg < WeightTrendCalculator.AlgorithmConfig.responsive.kcalPerKg)
}
