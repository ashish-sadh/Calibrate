import Testing
@testable import Calibrate

@Test func emaWithSingleEntry() async throws {
    let entries = [
        (date: "2026-03-01", weightKg: 55.0)
    ]
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)
    #expect(trend != nil)
    #expect(trend!.currentEMA == 55.0)
    #expect(trend!.weeklyRateKg == 0)
}

@Test func emaSmoothing() async throws {
    let entries = [
        (date: "2026-03-01", weightKg: 55.0),
        (date: "2026-03-02", weightKg: 54.0),
    ]
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)!

    // EMA: 0.1 * 54.0 + 0.9 * 55.0 = 5.4 + 49.5 = 54.9
    #expect(abs(trend.currentEMA - 54.9) < 0.01)
}

@Test func emaSmoothingMultipleEntries() async throws {
    let entries = [
        (date: "2026-03-01", weightKg: 60.0),
        (date: "2026-03-02", weightKg: 59.0),
        (date: "2026-03-03", weightKg: 58.0),
        (date: "2026-03-04", weightKg: 57.0),
        (date: "2026-03-05", weightKg: 56.0),
    ]
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)!

    // EMA should trail behind actual values
    #expect(trend.currentEMA > 56.0)
    #expect(trend.currentEMA < 60.0)
    #expect(trend.trendDirection == .losing)
}

@Test func losingTrend() async throws {
    // 14+ days of consistent weight loss
    var entries: [(date: String, weightKg: Double)] = []
    for day in 0..<20 {
        let date = String(format: "2026-03-%02d", day + 1)
        entries.append((date: date, weightKg: 60.0 - Double(day) * 0.1))
    }
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)!

    #expect(trend.trendDirection == .losing)
    #expect(trend.weeklyRateKg < 0)
    #expect(trend.estimatedDailyDeficit < 0)
}

@Test func gainingTrend() async throws {
    var entries: [(date: String, weightKg: Double)] = []
    for day in 0..<20 {
        let date = String(format: "2026-03-%02d", day + 1)
        entries.append((date: date, weightKg: 55.0 + Double(day) * 0.1))
    }
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)!

    #expect(trend.trendDirection == .gaining)
    #expect(trend.weeklyRateKg > 0)
    #expect(trend.estimatedDailyDeficit > 0)
}

@Test func maintainingTrend() async throws {
    let entries = [
        (date: "2026-03-01", weightKg: 55.0),
        (date: "2026-03-02", weightKg: 55.1),
        (date: "2026-03-03", weightKg: 54.9),
        (date: "2026-03-04", weightKg: 55.0),
        (date: "2026-03-05", weightKg: 55.1),
        (date: "2026-03-06", weightKg: 55.0),
        (date: "2026-03-07", weightKg: 54.9),
        (date: "2026-03-08", weightKg: 55.0),
        (date: "2026-03-09", weightKg: 55.1),
        (date: "2026-03-10", weightKg: 55.0),
        (date: "2026-03-11", weightKg: 55.0),
        (date: "2026-03-12", weightKg: 55.0),
        (date: "2026-03-13", weightKg: 55.1),
        (date: "2026-03-14", weightKg: 55.0),
    ]
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)!
    #expect(trend.trendDirection == .maintaining)
}

@Test func weightChangesCalculation() async throws {
    var entries: [(date: String, weightKg: Double)] = []
    for day in 0..<100 {
        let date = Calendar.current.date(byAdding: .day, value: -99 + day, to: Date())!
        let dateStr = DateFormatters.dateOnly.string(from: date)
        entries.append((date: dateStr, weightKg: 60.0 - Double(day) * 0.05))
    }
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)!

    #expect(trend.weightChanges.sevenDay != nil)
    #expect(trend.weightChanges.sevenDay! < 0)
    #expect(trend.weightChanges.thirtyDay != nil)
    #expect(trend.weightChanges.thirtyDay! < 0)
    #expect(trend.weightChanges.ninetyDay != nil)
}

@Test func projection30Day() async throws {
    var entries: [(date: String, weightKg: Double)] = []
    for day in 0..<20 {
        let date = String(format: "2026-03-%02d", day + 1)
        entries.append((date: date, weightKg: 60.0 - Double(day) * 0.1))
    }
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)!

    #expect(trend.projection30Day != nil)
    #expect(trend.projection30Day! < trend.currentEMA) // should be lower since losing
}

@Test func emptyEntriesReturnsNil() async throws {
    let entries: [(date: String, weightKg: Double)] = []
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)
    #expect(trend == nil)
}

@Test func deficitCalculation() async throws {
    // Losing ~0.5 kg/week = ~550 kcal/day deficit (7700 * 0.5 / 7)
    var entries: [(date: String, weightKg: Double)] = []
    for day in 0..<21 {
        let date = String(format: "2026-03-%02d", day + 1)
        // ~0.5kg per week = ~0.071 kg/day
        entries.append((date: date, weightKg: 60.0 - Double(day) * 0.071))
    }
    let trend = WeightTrendCalculator.calculateTrend(entries: entries)!

    // Deficit should be roughly -550 kcal/day (give or take EMA smoothing)
    #expect(trend.estimatedDailyDeficit < 0)
    #expect(trend.estimatedDailyDeficit > -1000) // sanity check
}

@Test func linearRegressionFlat() async throws {
    let points = [
        WeightTrendCalculator.WeightDataPoint(date: Date(), dateString: "2026-03-01", actualWeight: 55, emaWeight: 55),
        WeightTrendCalculator.WeightDataPoint(date: Date().addingTimeInterval(86400), dateString: "2026-03-02", actualWeight: 55, emaWeight: 55),
    ]
    let slope = WeightTrendCalculator.linearRegressionSlope(points: points)
    #expect(abs(slope) < 0.001)
}
