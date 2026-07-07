import Foundation
import Testing
@testable import DriftCore

/// Tier-0 gate for the #932 chart redesign: the raw-reading series and the
/// EMA series must each produce the exact expected point set for a fixed
/// input — every scale reading lands on the raw series at its converted
/// value, every day carries its EMA, weekly aggregation averages within
/// calendar weeks.
struct WeightChartSeriesTests {

    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday — deterministic across environments
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func point(_ y: Int, _ m: Int, _ d: Int, actual: Double?, ema: Double) -> WeightTrendCalculator.WeightDataPoint {
        WeightTrendCalculator.WeightDataPoint(
            date: date(y, m, d), dateString: String(format: "%04d-%02d-%02d", y, m, d),
            actualWeight: actual, emaWeight: ema)
    }

    // MARK: - Daily

    @Test func dailyMapsEveryReadingToItsOwnValue() {
        let series = WeightChartSeries.daily([
            point(2026, 7, 1, actual: 80.0, ema: 80.2),
            point(2026, 7, 2, actual: nil, ema: 80.1),   // no weigh-in — EMA only
            point(2026, 7, 3, actual: 79.4, ema: 80.0),
        ], unit: .kg)

        #expect(series.count == 3)
        #expect(series[0].actual == 80.0)
        #expect(series[0].ema == 80.2)
        #expect(series[1].actual == nil, "day without a weigh-in must not synthesize a reading")
        #expect(series[1].ema == 80.1)
        #expect(series[2].actual == 79.4)
        #expect(series.map(\.date) == [date(2026, 7, 1), date(2026, 7, 2), date(2026, 7, 3)])
    }

    @Test func dailyConvertsToDisplayUnits() {
        let series = WeightChartSeries.daily([point(2026, 7, 1, actual: 80.0, ema: 80.5)], unit: .lbs)
        #expect(abs((series[0].actual ?? 0) - 80.0 * 2.20462) < 0.001)
        #expect(abs(series[0].ema - 80.5 * 2.20462) < 0.001)
    }

    // MARK: - Weekly

    @Test func weeklyAveragesWithinCalendarWeeks() {
        // 2026-07-06 is a Monday: days 6+8 share a week; day 13 starts the next.
        let series = WeightChartSeries.weekly([
            point(2026, 7, 6, actual: 80.0, ema: 80.4),
            point(2026, 7, 8, actual: 81.0, ema: 80.2),
            point(2026, 7, 13, actual: 79.0, ema: 80.0),
        ], unit: .kg, calendar: cal)

        #expect(series.count == 2)
        #expect(series[0].date == date(2026, 7, 6), "week anchored to its start")
        #expect(series[0].actual == 80.5, "actuals averaged within the week")
        #expect(abs(series[0].ema - 80.3) < 0.0001)
        #expect(series[1].actual == 79.0)
    }

    @Test func weeklyWeekWithoutWeighInsHasNilActual() {
        let series = WeightChartSeries.weekly([
            point(2026, 7, 6, actual: nil, ema: 80.0),
            point(2026, 7, 7, actual: nil, ema: 79.9),
        ], unit: .kg, calendar: cal)
        #expect(series.count == 1)
        #expect(series[0].actual == nil, "EMA-only week must not fabricate a scale reading")
        #expect(abs(series[0].ema - 79.95) < 0.0001)
    }
}
