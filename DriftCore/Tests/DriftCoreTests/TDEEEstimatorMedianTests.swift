import XCTest
@testable import DriftCore

/// V7 #3 — `TDEEEstimator.median` is the new aggregator over qualified-
/// log daily kcals. Mean was sensitive to outlier days (one feast or one
/// fast threw the average); median is robust to both ends.
final class TDEEEstimatorMedianTests: XCTestCase {

    func testMedianOfEmptyIsNil() {
        XCTAssertNil(TDEEEstimator.median([]))
    }

    func testMedianOfSingletonReturnsTheValue() {
        XCTAssertEqual(TDEEEstimator.median([2_000]), 2_000)
    }

    func testMedianOfOddCount() {
        // Sorted: 1800, 2000, 2200 — middle = 2000.
        XCTAssertEqual(TDEEEstimator.median([2_200, 1_800, 2_000]), 2_000)
    }

    func testMedianOfEvenCount() {
        // Sorted: 1800, 1900, 2100, 2200 — avg of two middles = 2000.
        XCTAssertEqual(TDEEEstimator.median([2_200, 1_900, 1_800, 2_100]), 2_000)
    }

    func testMedianIsOrderIndependent() {
        let v1: [Double] = [1500, 1700, 1800, 2000, 2100, 2400, 3500]
        let v2 = v1.shuffled()
        XCTAssertEqual(TDEEEstimator.median(v1), TDEEEstimator.median(v2))
    }

    func testMedianResistsHighOutlier() {
        // One cheat day at 4500 next to six steady 2000s. Mean would
        // jump to ~2357; median stays at 2000 (the actual signal).
        let totals: [Double] = [2_000, 2_000, 2_000, 4_500, 2_000, 2_000, 2_000]
        XCTAssertEqual(TDEEEstimator.median(totals), 2_000)
        let mean = totals.reduce(0, +) / Double(totals.count)
        XCTAssertGreaterThan(mean, 2_350) // mean is pulled up
    }

    func testMedianResistsLowOutlier() {
        // One barely-logged day at 600 next to six 2000s. Mean drops
        // to ~1800; median stays at 2000. This is the exact failure
        // mode users reported on TestFlight (#3 in V7 UI review).
        let totals: [Double] = [2_000, 2_000, 2_000, 600, 2_000, 2_000, 2_000]
        XCTAssertEqual(TDEEEstimator.median(totals), 2_000)
        let mean = totals.reduce(0, +) / Double(totals.count)
        XCTAssertLessThan(mean, 1_850) // mean is dragged down
    }
}
