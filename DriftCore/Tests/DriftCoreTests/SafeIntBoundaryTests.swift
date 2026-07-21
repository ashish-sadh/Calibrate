import Testing
@testable import DriftCore

struct SafeIntBoundaryTests {
    @Test func exactFloatingPointBoundsClampSafely() {
        #expect(Double(Int.max).safeInt == Int.max)
        #expect(Double(Int.min).safeInt == Int.min)
    }

    @Test func finiteValuesImmediatelyInsideBoundsConvertNormally() {
        let justBelowMaximum = Double(Int.max).nextDown
        let justAboveMinimum = Double(Int.min).nextUp

        #expect(justBelowMaximum.safeInt == Int(justBelowMaximum))
        #expect(justAboveMinimum.safeInt == Int(justAboveMinimum))
    }

    @Test func finiteFractionsTruncateTowardZero() {
        #expect(42.999.safeInt == 42)
        #expect((-42.999).safeInt == -42)
        #expect(Double.leastNonzeroMagnitude.safeInt == 0)
        #expect((-Double.leastNonzeroMagnitude).safeInt == 0)
    }
}
