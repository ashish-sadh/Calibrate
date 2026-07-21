import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — deterministic boundary coverage for chart-series mapping and aggregation.
@Suite struct WeightChartSeriesEdgeCaseTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func point(
        _ year: Int, _ month: Int, _ day: Int,
        actual: Double?, ema: Double
    ) -> WeightTrendCalculator.WeightDataPoint {
        WeightTrendCalculator.WeightDataPoint(
            date: date(year, month, day),
            dateString: String(format: "%04d-%02d-%02d", year, month, day),
            actualWeight: actual,
            emaWeight: ema
        )
    }

    @Test func emptyInputsProduceNoChartPoints() {
        #expect(WeightChartSeries.daily([], unit: .kg).isEmpty)
        #expect(WeightChartSeries.weekly([], unit: .kg, calendar: calendar).isEmpty)
    }

    @Test func weeklySortsUnorderedInputAcrossYearBoundary() {
        let series = WeightChartSeries.weekly([
            point(2027, 1, 4, actual: 78, ema: 78.5),
            point(2026, 12, 31, actual: 80, ema: 79.5),
            point(2026, 12, 28, actual: 79, ema: 79),
        ], unit: .kg, calendar: calendar)

        #expect(series.count == 2)
        #expect(series.map(\.date) == [date(2026, 12, 28), date(2027, 1, 4)])
        #expect(series[0].actual == 79.5)
        #expect(series[0].ema == 79.25)
        #expect(series[1].actual == 78)
    }

    @Test func weeklyExcludesMissingActualsButIncludesEveryEmaAndConvertsUnits() {
        let series = WeightChartSeries.weekly([
            point(2026, 7, 6, actual: 80, ema: 80),
            point(2026, 7, 7, actual: nil, ema: 79),
            point(2026, 7, 8, actual: 78, ema: 78),
        ], unit: .lbs, calendar: calendar)

        let week = series[0]
        #expect(series.count == 1)
        #expect(abs((week.actual ?? 0) - 79 * 2.20462) < 0.000_001)
        #expect(abs(week.ema - 79 * 2.20462) < 0.000_001)
    }
}
