import XCTest
@testable import DriftCore

/// #1080: `Int(weight)` truncated fractional weights everywhere they were shown
/// or prefilled, which silently rewrote stored data on save. These pin the
/// contract the two call paths (display + Edit Set prefill) share.
final class WeightFormatterTests: XCTestCase {

    func testWholeNumbersRenderWithoutDecimal() {
        // The common case must be byte-identical to the old `Int(x)` output.
        XCTAssertEqual(WeightFormatter.plain(135), "135")
        XCTAssertEqual(WeightFormatter.plain(0), "0")
        XCTAssertEqual(WeightFormatter.plain(225.0), "225")
    }

    func testFractionalWeightsKeepOneDecimal() {
        XCTAssertEqual(WeightFormatter.plain(137.5), "137.5")
        XCTAssertEqual(WeightFormatter.plain(2.5), "2.5")
        XCTAssertEqual(WeightFormatter.plain(62.6), "62.6")
    }

    func testNearIntegerValuesReadAsWholeNumbers() {
        // Rounding happens before the whole-number test, so float noise and
        // sub-0.05 remainders don't produce a pointless "137.0".
        XCTAssertEqual(WeightFormatter.plain(137.04), "137")
        XCTAssertEqual(WeightFormatter.plain(136.98), "137")
    }

    func testRoundsToOneDecimal() {
        XCTAssertEqual(WeightFormatter.plain(137.55), "137.6")
        XCTAssertEqual(WeightFormatter.plain(137.44), "137.4")
    }

    func testNegativeWeights() {
        XCTAssertEqual(WeightFormatter.plain(-45), "-45")
        XCTAssertEqual(WeightFormatter.plain(-2.5), "-2.5")
    }

    /// #1036: `Int(x)` is an uncatchable trap on NaN/±∞. The formatter feeds
    /// unvalidated DB + model JSON, so it must degrade instead of crashing.
    func testNonFiniteValuesDoNotTrap() {
        XCTAssertEqual(WeightFormatter.plain(.nan), "0")
        XCTAssertEqual(WeightFormatter.plain(.infinity), "0")
        XCTAssertEqual(WeightFormatter.plain(-.infinity), "0")
    }

    /// #1022 asked the previous-set ghost to trim trailing zeros, and was
    /// implemented with `String(format: "%g")`. That trims zeros but keeps SIX
    /// significant digits, so a kg-entered set round-tripped to lbs rendered
    /// "88.1848 lbs" on screen. These pin #1022's actual intent while closing
    /// the case it never considered.
    func testTrimsTrailingZerosPer1022() {
        XCTAssertEqual(WeightFormatter.plain(42.5), "42.5")
        XCTAssertEqual(WeightFormatter.plain(40.0), "40")
    }

    func testKgConvertedWeightDoesNotLeakSixSignificantDigits() {
        // 40 kg → lbs, the value that appeared verbatim in the iOS UI.
        XCTAssertEqual(WeightFormatter.plain(40 * 2.20462), "88.2")
    }

    /// The #1080 repro, at the layer that lost the data: a 137.5 lb set round
    /// trips through the Edit Set prefill unchanged, so saving a rep-count fix
    /// can no longer write the weight down half a pound.
    func testEditSetPrefillRoundTripPreservesHalfPound() {
        let stored = 137.5
        let prefilled = WeightFormatter.plain(stored)
        XCTAssertEqual(prefilled, "137.5")
        XCTAssertEqual(Double(prefilled), stored)
    }

    /// `WorkoutSet.display` is the row the user reads before tapping to edit —
    /// it truncated too, which is why the prefill bug looked consistent.
    func testSetDisplayShowsFractionalWeight() {
        let set = WorkoutSet(workoutId: 1, exerciseName: "Bench Press",
                             setOrder: 1, weightLbs: 137.5, reps: 8)
        XCTAssertEqual(set.display(in: .lbs), "137.5 lbs × 8")
    }

    func testSetDisplayKeepsWholeWeightsUnchanged() {
        let set = WorkoutSet(workoutId: 1, exerciseName: "Bench Press",
                             setOrder: 1, weightLbs: 135, reps: 8)
        XCTAssertEqual(set.display(in: .lbs), "135 lbs × 8")
    }
}
