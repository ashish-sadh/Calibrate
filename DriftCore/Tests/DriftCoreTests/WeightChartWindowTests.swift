import XCTest
@testable import DriftCore

/// The invariant these pin is #1220's fix: a range chip sets the visible window
/// (anchored at the last data point) instead of filtering the series, so no
/// chip can ever resolve to a window with no data in it.
final class WeightChartWindowTests: XCTestCase {

    private func day(_ offset: Int, from ref: Date) -> Date {
        ref.addingTimeInterval(Double(offset) * 86_400)
    }

    func testAllRangeSpansTheWholeSeries() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let start = day(-90, from: end)
        let w = WeightChartWindow.resolve(firstDate: start, lastDate: end, rangeStart: nil)

        XCTAssertEqual(w.seconds, 90 * 86_400, accuracy: 1)
        // The 4% trailing pad puts the last point inside, not on, the edge.
        XCTAssertGreaterThan(w.end, end)
        XCTAssertLessThanOrEqual(w.start, start)
    }

    func testWindowAlwaysContainsTheLastPointEvenWhenItIsOld() {
        // The #1220 repro: last weigh-in a week ago, user taps 1W. Anchoring at
        // Date() would produce a window with nothing in it; anchoring at the
        // last point cannot.
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lastWeighIn = day(-7, from: now)
        let firstWeighIn = day(-120, from: now)
        let rangeStart = day(-7, from: now)

        let w = WeightChartWindow.resolve(firstDate: firstWeighIn, lastDate: lastWeighIn,
                                          rangeStart: rangeStart)

        XCTAssertLessThan(w.start, lastWeighIn)
        XCTAssertGreaterThan(w.end, lastWeighIn)
    }

    func testShortRangeIsFlooredAtSevenDays() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let w = WeightChartWindow.resolve(firstDate: day(-60, from: end), lastDate: end,
                                          rangeStart: day(-3, from: end))

        XCTAssertEqual(w.seconds, 7 * 86_400, accuracy: 1)
    }

    func testRangeWiderThanTheDataClampsToTheSeriesSpan() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let w = WeightChartWindow.resolve(firstDate: day(-20, from: end), lastDate: end,
                                          rangeStart: day(-365, from: end))

        XCTAssertEqual(w.seconds, 20 * 86_400, accuracy: 1)
    }

    func testSinglePointSeriesStillHasAMeasurableWindow() {
        let only = Date(timeIntervalSince1970: 1_800_000_000)
        let w = WeightChartWindow.resolve(firstDate: only, lastDate: only, rangeStart: nil)

        XCTAssertEqual(w.seconds, 86_400, accuracy: 1)
        XCTAssertLessThan(w.start, only)
        XCTAssertGreaterThan(w.end, only)
    }
}
