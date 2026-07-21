import Testing
@testable import DriftCore

/// Tier-0 boundary coverage for lifted-weight display formatting.
@Suite struct WeightFormatterBoundaryTests {
    @Test func halfTenthRoundsAwayFromZero() {
        #expect(WeightFormatter.plain(42.049) == "42")
        #expect(WeightFormatter.plain(42.05) == "42.1")
        #expect(WeightFormatter.plain(-42.049) == "-42")
        #expect(WeightFormatter.plain(-42.05) == "-42.1")
    }

    @Test func valuesNearZeroDoNotRenderNegativeZero() {
        #expect(WeightFormatter.plain(0.04) == "0")
        #expect(WeightFormatter.plain(-0.04) == "0")
        #expect(WeightFormatter.plain(0.05) == "0.1")
        #expect(WeightFormatter.plain(-0.05) == "-0.1")
    }

    @Test func roundingAcrossIntegerBoundaryDropsDecimal() {
        #expect(WeightFormatter.plain(1.96) == "2")
        #expect(WeightFormatter.plain(-1.96) == "-2")
    }

    @Test func extremeFiniteValuesClampToIntegerRange() {
        #expect(WeightFormatter.plain(.greatestFiniteMagnitude) == "\(Int.max)")
        #expect(WeightFormatter.plain(-.greatestFiniteMagnitude) == "\(Int.min)")
    }
}
