import Testing
@testable import DriftCore

/// Tier 0 — exact policy boundaries for the pure TDEE calculator.
@Suite struct TDEEEstimatorBoundaryTests {

    @Test func activityLabelsChangeAtDocumentedCutoffs() {
        let cases: [(multiplier: Double, expected: String)] = [
            (24, "Lightly Active"),
            (27, "Moderately Active"),
            (30, "Very Active"),
            (33, "Athlete"),
        ]

        for testCase in cases {
            var config = TDEEEstimator.TDEEConfig.default
            config.activityMultiplier = testCase.multiplier
            #expect(config.activityLabel == testCase.expected)
        }
    }

    @Test func valuesImmediatelyBelowCutoffsRemainInPriorBucket() {
        let cases: [(multiplier: Double, expected: String)] = [
            (24.0.nextDown, "Sedentary"),
            (27.0.nextDown, "Lightly Active"),
            (30.0.nextDown, "Moderately Active"),
            (33.0.nextDown, "Very Active"),
        ]

        for testCase in cases {
            var config = TDEEEstimator.TDEEConfig.default
            config.activityMultiplier = testCase.multiplier
            #expect(config.activityLabel == testCase.expected)
        }
    }

    @Test func trendAnchorRequiresMedianIntakeAboveFiveHundred() {
        let exactlyAtThreshold = TDEEEstimator.trendAnchoredTDEE(
            qualifiedDailyTotals: Array(repeating: 500, count: 5),
            estimatedDailyDeficit: 0,
            plausibilityFloor: 0
        )
        let justAboveThreshold = TDEEEstimator.trendAnchoredTDEE(
            qualifiedDailyTotals: Array(repeating: 500.0.nextUp, count: 5),
            estimatedDailyDeficit: 0,
            plausibilityFloor: 0
        )

        #expect(exactlyAtThreshold == nil)
        #expect(justAboveThreshold == 500.0.nextUp)
    }

    @Test func trendAnchorMustStrictlyExceedPlausibilityFloor() {
        let exactlyAtFloor = TDEEEstimator.trendAnchoredTDEE(
            qualifiedDailyTotals: Array(repeating: 1_800, count: 5),
            estimatedDailyDeficit: 0,
            plausibilityFloor: 1_800
        )
        let justAboveFloor = TDEEEstimator.trendAnchoredTDEE(
            qualifiedDailyTotals: Array(repeating: 1_800.0.nextUp, count: 5),
            estimatedDailyDeficit: 0,
            plausibilityFloor: 1_800
        )

        #expect(exactlyAtFloor == nil)
        #expect(justAboveFloor == 1_800.0.nextUp)
    }
}
