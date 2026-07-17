import XCTest
import SwiftUI
@testable import Drift
import DriftCore

/// Goal-aware color mapping shared by the chart trend line, its legend, and
/// (since the 2026-07-17 field report) the header "Difference" value. A
/// hardcoded down=green in the header painted "+1.0 lbs" red beside a green
/// "30-day +1.0 Increase" on a GAINING goal — same number, same screen,
/// opposite colors.
final class WeightChartTrendColorTests: XCTestCase {

    func testGainGoalColorsIncreaseAsAligned() {
        XCTAssertEqual(WeightChartView.trendColor(emaDelta: 1.0, goalChangeKg: 5), Theme.deficit)
        XCTAssertEqual(WeightChartView.trendColor(emaDelta: -1.0, goalChangeKg: 5), Theme.surplus)
    }

    func testLoseGoalColorsDecreaseAsAligned() {
        XCTAssertEqual(WeightChartView.trendColor(emaDelta: -1.0, goalChangeKg: -5), Theme.deficit)
        XCTAssertEqual(WeightChartView.trendColor(emaDelta: 1.0, goalChangeKg: -5), Theme.surplus)
    }

    func testNoGoalDefaultsToLosing() {
        XCTAssertEqual(WeightChartView.trendColor(emaDelta: -1.0, goalChangeKg: nil), Theme.deficit)
        XCTAssertEqual(WeightChartView.trendColor(emaDelta: 1.0, goalChangeKg: nil), Theme.surplus)
    }

    func testFlatIsNeutral() {
        XCTAssertEqual(WeightChartView.trendColor(emaDelta: 0.0, goalChangeKg: -5), Theme.chartTrend)
        XCTAssertEqual(WeightChartView.trendColor(emaDelta: nil, goalChangeKg: -5), Theme.chartTrend)
    }
}
