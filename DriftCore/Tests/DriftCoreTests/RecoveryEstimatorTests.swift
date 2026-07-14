import Foundation
@testable import DriftCore
import Testing

// MARK: - Baselines (3 tests)

@Test func baselinesFromData() {
    let baselines = RecoveryEstimator.calculateBaselines(
        hrvHistory: [(date: Date(), ms: 60), (date: Date(), ms: 80)],
        rhrHistory: [(date: Date(), bpm: 55), (date: Date(), bpm: 65)],
        respHistory: [(date: Date(), rpm: 14), (date: Date(), rpm: 16)],
        sleepHistory: [(date: Date(), hours: 7), (date: Date(), hours: 8)]
    )
    #expect(abs(baselines.hrvMs - 70) < 0.1)
    #expect(abs(baselines.restingHR - 60) < 0.1)
    #expect(abs(baselines.sleepHours - 7.5) < 0.1)
    #expect(baselines.daysOfData == 2)
    #expect(baselines.isEstablished == false) // needs 5 days
}

@Test func baselinesFromEmptyUsesDefaults() {
    let baselines = RecoveryEstimator.calculateBaselines(
        hrvHistory: [], rhrHistory: [], respHistory: [], sleepHistory: []
    )
    #expect(baselines.hrvMs == 45)
    #expect(baselines.restingHR == 65)
    #expect(baselines.respiratoryRate == 15)
    #expect(baselines.sleepHours == 7.5)
    #expect(baselines.daysOfData == 0)
}

@Test func baselinesEstablishedAfter5Days() {
    let dates = (0..<6).map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
    let hrv = dates.map { (date: $0, ms: 60.0) }
    let baselines = RecoveryEstimator.calculateBaselines(
        hrvHistory: hrv, rhrHistory: [], respHistory: [], sleepHistory: []
    )
    #expect(baselines.isEstablished == true)
}

// MARK: - Recovery Score (6 tests)

@Test func recoveryScoreAtBaseline() {
    // HRV = baseline, RHR = baseline, sleep = baseline → should be ~70
    let baselines = RecoveryEstimator.Baselines(
        hrvMs: 60, restingHR: 60, respiratoryRate: 15, sleepHours: 8, daysOfData: 7
    )
    let score = RecoveryEstimator.calculateRecovery(
        hrvMs: 60, restingHR: 60, sleepHours: 8, baselines: baselines
    )
    #expect(score >= 60 && score <= 80)
}

@Test func recoveryScoreHighHRVBoostsScore() {
    // HRV 2x baseline → maximum HRV contribution
    let baselines = RecoveryEstimator.Baselines(
        hrvMs: 45, restingHR: 65, respiratoryRate: 15, sleepHours: 7.5, daysOfData: 7
    )
    let high = RecoveryEstimator.calculateRecovery(
        hrvMs: 90, restingHR: 65, sleepHours: 7.5, baselines: baselines
    )
    let low = RecoveryEstimator.calculateRecovery(
        hrvMs: 22, restingHR: 65, sleepHours: 7.5, baselines: baselines
    )
    #expect(high > low)
}

@Test func recoveryScoreNoHRVRedistributesWeights() {
    // hrvMs = 0 → redistributes 40% weight to RHR+Sleep equally
    let baselines = RecoveryEstimator.Baselines(
        hrvMs: 45, restingHR: 65, respiratoryRate: 15, sleepHours: 7.5, daysOfData: 7
    )
    let scoreNoHRV = RecoveryEstimator.calculateRecovery(
        hrvMs: 0, restingHR: 65, sleepHours: 7.5, baselines: baselines
    )
    // Should still produce a meaningful (non-zero) score from RHR + Sleep
    #expect(scoreNoHRV > 0 && scoreNoHRV <= 100)
}

@Test func recoveryScoreClampsTo0_100() {
    // Extreme inputs should stay within bounds
    let scoreHigh = RecoveryEstimator.calculateRecovery(
        hrvMs: 1000, restingHR: 20, sleepHours: 12, baselines: nil
    )
    let scoreLow = RecoveryEstimator.calculateRecovery(
        hrvMs: 0, restingHR: 200, sleepHours: 0, baselines: nil
    )
    #expect(scoreHigh <= 100)
    #expect(scoreLow >= 0)
}

@Test func recoveryScoreLowSleepReducesScore() {
    let baselines = RecoveryEstimator.Baselines(
        hrvMs: 60, restingHR: 60, respiratoryRate: 15, sleepHours: 8, daysOfData: 7
    )
    let fullSleep = RecoveryEstimator.calculateRecovery(
        hrvMs: 60, restingHR: 60, sleepHours: 8, baselines: baselines
    )
    let halfSleep = RecoveryEstimator.calculateRecovery(
        hrvMs: 60, restingHR: 60, sleepHours: 4, baselines: baselines
    )
    #expect(fullSleep > halfSleep)
}

@Test func recoveryScoreDefaultBaselinesWhenNil() {
    // No baselines passed → uses hardcoded defaults (HRV=45, RHR=65, sleep=7.5)
    let score = RecoveryEstimator.calculateRecovery(
        hrvMs: 45, restingHR: 65, sleepHours: 7.5, baselines: nil
    )
    #expect(score >= 0 && score <= 100)
}

// MARK: - Sleep Score (5 tests)

@Test func sleepScorePerfectDurationAndStages() {
    // 8h sleep / 8h target with ideal REM (22%) and deep (17%)
    let score = RecoveryEstimator.calculateSleepScore(
        totalHours: 8, remHours: 8 * 0.22, deepHours: 8 * 0.17, targetHours: 8
    )
    #expect(score >= 90)
}

@Test func sleepScoreNoStageDataUsesOnlyDuration() {
    // No REM/deep → weight shifts fully to duration
    let score = RecoveryEstimator.calculateSleepScore(
        totalHours: 7, remHours: 0, deepHours: 0, targetHours: 7
    )
    #expect(score == 100) // 7/7 duration, no stage penalty
}

@Test func sleepScoreShortSleepReducesScore() {
    let full = RecoveryEstimator.calculateSleepScore(
        totalHours: 8, remHours: 0, deepHours: 0, targetHours: 8
    )
    let short = RecoveryEstimator.calculateSleepScore(
        totalHours: 5, remHours: 0, deepHours: 0, targetHours: 8
    )
    #expect(full > short)
}

@Test func sleepScoreClampsTo0_100() {
    let score = RecoveryEstimator.calculateSleepScore(
        totalHours: 12, remHours: 5, deepHours: 4, targetHours: 6
    )
    #expect(score <= 100)
}

@Test func sleepScoreZeroHoursIsZero() {
    let score = RecoveryEstimator.calculateSleepScore(
        totalHours: 0, remHours: 0, deepHours: 0, targetHours: 8
    )
    #expect(score == 0)
}

// MARK: - Activity Load (5 tests)

@Test func activityLoadRest() {
    let (load, _) = RecoveryEstimator.calculateActivityLoad(activeCalories: 50, steps: 1000)
    #expect(load == .rest)
}

@Test func activityLoadLight() {
    let (load, _) = RecoveryEstimator.calculateActivityLoad(activeCalories: 200, steps: 4000)
    #expect(load == .light)
}

@Test func activityLoadModerate() {
    let (load, _) = RecoveryEstimator.calculateActivityLoad(activeCalories: 500, steps: 8000)
    #expect(load == .moderate)
}

@Test func activityLoadHeavy() {
    let (load, _) = RecoveryEstimator.calculateActivityLoad(activeCalories: 900, steps: 15000)
    #expect(load == .heavy)
}

@Test func activityLoadExtreme() {
    let (load, raw) = RecoveryEstimator.calculateActivityLoad(activeCalories: 1100, steps: 20000)
    #expect(load == .extreme)
    #expect(raw <= 21.0)
}

// MARK: - Dynamic Sleep Need (3 tests)

@Test func dynamicSleepNeedBaseline() {
    // No strain, no debt → 7.5h
    let need = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: 5, rollingDebtHours: 0)
    #expect(abs(need - 7.5) < 0.1)
}

@Test func dynamicSleepNeedHighStrainAddsExtra() {
    let base = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: 5, rollingDebtHours: 0)
    let high = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: 20, rollingDebtHours: 0)
    #expect(high > base)
    #expect(high <= 9.0) // capped at 9h
}

@Test func dynamicSleepNeedDebtAddsExtra() {
    let base = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: 5, rollingDebtHours: 0)
    let inDebt = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: 5, rollingDebtHours: -5)
    #expect(inDebt > base)
    #expect(inDebt <= 9.0)
}

// MARK: - Sleep Debt (4 tests)

@Test func sleepDebtNoHistory() {
    let debt = RecoveryEstimator.sleepDebt(recentSleep: [], need: 8)
    #expect(debt == 0)
}

@Test func sleepDebtNoPenaltyForSufficientSleep() {
    let dates = (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
    let history = dates.map { (date: $0, hours: 8.0) }
    let debt = RecoveryEstimator.sleepDebt(recentSleep: history, need: 8.0)
    #expect(abs(debt) < 0.2) // near 0
}

@Test func sleepDebtChronicShortSleepIsNegative() {
    let dates = (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
    let history = dates.map { (date: $0, hours: 5.0) } // 3h short every night
    let debt = RecoveryEstimator.sleepDebt(recentSleep: history, need: 8.0)
    #expect(debt < -1.0)
}

@Test func sleepDebtCappedAtMinus3() {
    let dates = (0..<7).map { Calendar.current.date(byAdding: .day, value: -$0, to: Date())! }
    let history = dates.map { (date: $0, hours: 0.0) } // extreme deprivation
    let debt = RecoveryEstimator.sleepDebt(recentSleep: history, need: 8.0)
    #expect(debt >= -3.0)
}

// MARK: - Deviation (3 tests)

@Test func deviationHigherIsBetterPositivePct() {
    let (arrow, pct, favorable) = RecoveryEstimator.deviation(
        current: 70, baseline: 60, higherIsBetter: true
    )
    #expect(pct > 0)
    #expect(favorable == true)
    #expect(arrow == "↑")
}

@Test func deviationLowerIsBetterPositivePct() {
    // RHR went UP (bad for heart rate)
    let (_, _, favorable) = RecoveryEstimator.deviation(
        current: 70, baseline: 60, higherIsBetter: false
    )
    #expect(favorable == false)
}

@Test func deviationZeroBaselineReturnsNeutral() {
    let (arrow, pct, _) = RecoveryEstimator.deviation(current: 50, baseline: 0, higherIsBetter: true)
    #expect(arrow == "—")
    #expect(pct == 0)
}

// MARK: - Recovery history (2026-07-14: Body Rhythm was a one-day snapshot)

@Test func recoveryHistoryJoinsSeriesByDayAndSorts() {
    let cal = Calendar.current
    let base = cal.startOfDay(for: Date(timeIntervalSince1970: 1_784_000_000))
    func day(_ n: Int) -> Date { cal.date(byAdding: .day, value: n, to: base)! }

    let history = RecoveryEstimator.recoveryHistory(
        hrvHistory: [(day(0), 50), (day(2), 40)],
        rhrHistory: [(day(0), 60), (day(1), 62)],
        sleepHistory: [(day(0), 8.0), (day(1), 6.0), (day(3), 7.5)])

    // Days 0-3 all have SOME signal → 4 scored days, ascending.
    #expect(history.count == 4)
    #expect(history.map(\.date) == [day(0), day(1), day(2), day(3)])
    // Full-signal good day beats a short-sleep day.
    let d0 = history[0].score, d1 = history[1].score
    #expect(d0 > d1)
    for entry in history { #expect((0...100).contains(entry.score)) }
}

@Test func recoveryHistoryEmptyWhenNoSignal() {
    #expect(RecoveryEstimator.recoveryHistory(hrvHistory: [], rhrHistory: [], sleepHistory: []).isEmpty)
}
