import Testing
@testable import DriftCore

/// Tier 0 — deterministic rounding boundaries for compact fiber display.
@Suite struct MacroFormatterBoundaryTests {
    @Test func nonPositiveAndNaNValuesDisplayAsZero() {
        #expect(MacroFormatter.fiber(-0.1) == "0")
        #expect(MacroFormatter.fiber(-100) == "0")
        #expect(MacroFormatter.fiber(.nan) == "0")
    }

    @Test func tenthGramThresholdControlsWhetherATraceAmountAppears() {
        #expect(MacroFormatter.fiber(0.049) == "0")
        #expect(MacroFormatter.fiber(0.05) == "0.1")
    }

    @Test func valuesBelowTenCanRoundToAWholeTen() {
        #expect(MacroFormatter.fiber(9.94) == "9.9")
        #expect(MacroFormatter.fiber(9.96) == "10")
    }

    @Test func valuesAtOrAboveTenRoundToWholeGrams() {
        #expect(MacroFormatter.fiber(10.49) == "10")
        #expect(MacroFormatter.fiber(10.5) == "11")
    }
}
