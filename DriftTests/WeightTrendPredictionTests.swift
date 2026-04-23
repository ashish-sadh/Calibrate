import Foundation
import Testing
@testable import Drift

private func makeEntries(startDate: String, weightKgByDay: [Double]) -> [WeightEntry] {
    let fmt = DateFormatters.dateOnly
    guard let base = fmt.date(from: startDate) else { return [] }
    return weightKgByDay.enumerated().compactMap { (i, kg) in
        guard let d = Calendar.current.date(byAdding: .day, value: i, to: base) else { return nil }
        return WeightEntry(date: fmt.string(from: d), weightKg: kg, source: "manual")
    }
}

// MARK: - Regression math

@Test func weightTrend_steadyLoss_negativeSlopeHighR2() {
    let entries = makeEntries(startDate: "2026-03-01", weightKgByDay: [80, 79.9, 79.8, 79.7, 79.6, 79.5, 79.4, 79.3, 79.2, 79.1])
    let result = WeightTrendPredictionTool.linearRegression(entries: entries)
    #expect(result != nil)
    #expect((result?.slopePerDay ?? 0) < 0, "losing weight → negative slope")
    #expect((result?.r2 ?? 0) > 0.95, "steady loss → high R²")
}

@Test func weightTrend_steadyGain_positiveSlopeHighR2() {
    let entries = makeEntries(startDate: "2026-03-01", weightKgByDay: [70, 70.1, 70.2, 70.3, 70.4, 70.5, 70.6, 70.7])
    let result = WeightTrendPredictionTool.linearRegression(entries: entries)
    #expect(result != nil)
    #expect((result?.slopePerDay ?? 0) > 0, "gaining weight → positive slope")
    #expect((result?.r2 ?? 0) > 0.95, "steady gain → high R²")
}

@Test func weightTrend_flatData_nearZeroSlope() {
    let entries = makeEntries(startDate: "2026-03-01", weightKgByDay: [75, 75, 75, 75, 75, 75, 75, 75])
    let result = WeightTrendPredictionTool.linearRegression(entries: entries)
    #expect(result != nil)
    #expect(abs(result!.slopePerDay) < 0.001, "flat weight → slope ≈ 0")
}

@Test func weightTrend_tooFewEntries_returnsNil() {
    let one = makeEntries(startDate: "2026-03-01", weightKgByDay: [80])
    #expect(WeightTrendPredictionTool.linearRegression(entries: one) == nil)
    #expect(WeightTrendPredictionTool.linearRegression(entries: []) == nil)
}

@Test func weightTrend_noisyData_r2LessThanSteady() {
    let entries = makeEntries(startDate: "2026-03-01", weightKgByDay: [80, 79, 81, 78, 82, 77, 80, 79, 78, 77])
    let result = WeightTrendPredictionTool.linearRegression(entries: entries)
    let steady = makeEntries(startDate: "2026-03-01", weightKgByDay: [80, 79.9, 79.8, 79.7, 79.6, 79.5, 79.4, 79.3, 79.2, 79.1])
    let steadyResult = WeightTrendPredictionTool.linearRegression(entries: steady)
    #expect((result?.r2 ?? 1) < (steadyResult?.r2 ?? 0), "noisy series has lower R² than steady series")
}

@Test func weightTrend_r2Label_correctBuckets() {
    #expect(WeightTrendPredictionTool.r2Label(0.8) == "high")
    #expect(WeightTrendPredictionTool.r2Label(0.7) == "high")
    #expect(WeightTrendPredictionTool.r2Label(0.5) == "moderate")
    #expect(WeightTrendPredictionTool.r2Label(0.4) == "moderate")
    #expect(WeightTrendPredictionTool.r2Label(0.3) == "low")
    #expect(WeightTrendPredictionTool.r2Label(0.0) == "low")
}

@Test func weightTrend_slopeMatchesExpectedRate() {
    // 10 days, losing exactly 0.1 kg/day → slope should be -0.1 kg/day
    let entries = makeEntries(startDate: "2026-03-01", weightKgByDay: [80, 79.9, 79.8, 79.7, 79.6, 79.5, 79.4, 79.3, 79.2, 79.1])
    let result = WeightTrendPredictionTool.linearRegression(entries: entries)
    #expect(result != nil)
    #expect(abs((result?.slopePerDay ?? 0) - (-0.1)) < 0.001, "slope should be -0.1 kg/day")
}
