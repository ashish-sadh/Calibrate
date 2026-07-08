import Testing
@testable import DriftCore

// #1036: Double.safeInt clamps instead of trapping on NaN / ±∞ / out-of-Int64-range values.
struct SafeIntTests {
    @Test func clampsBeyondInt64Range() {
        #expect((1e20).safeInt == Int.max)
        #expect((-1e20).safeInt == Int.min)
    }

    @Test func handlesNonFinite() {
        #expect(Double.nan.safeInt == 0)
        #expect(Double.infinity.safeInt == Int.max)
        #expect((-Double.infinity).safeInt == Int.min)
    }

    @Test func passesThroughNormalValues() {
        #expect((42.7).safeInt == 42)
        #expect((0.0).safeInt == 0)
        #expect((-3.2).safeInt == -3)
    }
}
