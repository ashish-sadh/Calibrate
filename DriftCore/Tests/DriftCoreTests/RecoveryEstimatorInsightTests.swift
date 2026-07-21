import Foundation
@testable import DriftCore
import Testing

private func insightRecovery(
    score: Int,
    baselines: RecoveryEstimator.Baselines? = nil
) -> RecoveryEstimator.DailyRecovery {
    RecoveryEstimator.DailyRecovery(
        date: Date(timeIntervalSince1970: 0),
        recoveryScore: score,
        sleepScore: 70,
        activityLoad: .moderate,
        activityRaw: 6,
        activeCalories: 500,
        steps: 8_000,
        sleepHours: 7.5,
        sleepNeeded: 8,
        sleepDebt: 0,
        hrvMs: 50,
        restingHR: 60,
        respiratoryRate: 15,
        sleepDetail: nil,
        baselines: baselines
    )
}

struct RecoveryEstimatorInsightTests {
    @Test func threeConsecutiveHRVIncreasesProduceTrendInsight() {
        let history = [40.0, 45.0, 50.0].enumerated().map {
            (date: Date(timeIntervalSince1970: Double($0.offset) * 86_400), ms: $0.element)
        }

        let insights = RecoveryEstimator.generateInsights(
            recovery: insightRecovery(score: 60),
            hrvHistory: history,
            sleepHistory: []
        )

        #expect(insights == ["HRV has been trending up — consistent with good recovery."])
    }

    @Test func nonMonotonicHRVDoesNotProduceTrendInsight() {
        let history = [40.0, 50.0, 45.0].enumerated().map {
            (date: Date(timeIntervalSince1970: Double($0.offset) * 86_400), ms: $0.element)
        }

        let insights = RecoveryEstimator.generateInsights(
            recovery: insightRecovery(score: 60),
            hrvHistory: history,
            sleepHistory: []
        )

        #expect(insights.isEmpty)
    }

    @Test(arguments: [
        (score: 80, expected: "Strong recovery — good day for high-intensity training."),
        (score: 39, expected: "Low recovery — consider lighter activity or rest today."),
    ])
    func recoveryThresholdsProduceTrainingContext(score: Int, expected: String) {
        let insights = RecoveryEstimator.generateInsights(
            recovery: insightRecovery(score: score),
            hrvHistory: [],
            sleepHistory: []
        )

        #expect(insights == [expected])
    }

    @Test func maximumCappedSleepDebtCurrentlyProducesNoInsight() {
        let baselines = RecoveryEstimator.Baselines(
            hrvMs: 45,
            restingHR: 65,
            respiratoryRate: 15,
            sleepHours: 8,
            daysOfData: 7
        )
        let history = (0..<7).map {
            (date: Date(timeIntervalSince1970: Double($0) * 86_400), hours: 0.0)
        }

        let debt = RecoveryEstimator.sleepDebt(recentSleep: history, need: baselines.sleepHours)
        let insights = RecoveryEstimator.generateInsights(
            recovery: insightRecovery(score: 60, baselines: baselines),
            hrvHistory: [],
            sleepHistory: history
        )

        #expect(debt == -3)
        // TODO(codex): generateInsights checks for debt < -3, but sleepDebt caps at -3.
        #expect(insights.isEmpty)
    }
}
