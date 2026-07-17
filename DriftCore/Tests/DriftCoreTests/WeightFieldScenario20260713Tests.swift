import Foundation
@testable import DriftCore
import Testing

// Field scenario 2026-07-13: a month of flat-to-slightly-rising weight with a
// classic post-peak water plunge in the last 5 days (raw scale −1.6 kg,
// Jul 8→13). The reference app the operator trusts reports the 3-week energy
// balance as ≈ +60 kcal/day (+0.05 kg/wk); Drift screamed ≈ −400 kcal/day
// because the OLS tail chased the plunge. A water swing must not read as a
// 400-kcal deficit.

enum FieldScenario20260713 {
    /// Raw daily scale weights, oldest→newest, reconstructed from the field
    /// chart (30 days ending "today").
    static let weights: [Double] = [
        54.4, 54.0, 53.5, 53.4, 54.3, 54.4, 54.3, 54.2, 54.1,   // Jun 14–22 (dip + recovery)
        56.1,                                                    // Jun 23 spike
        55.4, 54.5, 54.4, 54.5, 54.55, 54.6, 54.7, 54.75, 54.8, // Jun 24–Jul 2
        54.9, 54.95, 55.0, 55.0, 55.05, 55.2,                    // Jul 3–8 plateau/peak
        54.1, 53.95, 54.1, 53.9, 53.6,                           // Jul 9–13 water plunge
    ]

    static func entries() -> [(date: String, weightKg: Double)] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let count = weights.count
        return weights.enumerated().map { (i, kg) in
            let date = Calendar.current.date(byAdding: .day, value: -(count - 1 - i), to: Date())!
            return (formatter.string(from: date), kg)
        }
    }
}

// MARK: - energySignalConflicts (short-window rate vs 30-day change)

private func makeTrend(rateKgPerWeek: Double, thirtyDayKg: Double?,
                       longWindowKg: Double? = nil) -> WeightTrendCalculator.WeightTrend {
    WeightTrendCalculator.WeightTrend(
        currentEMA: 54.0, previousEMA: 54.0,
        weeklyRateKg: rateKgPerWeek,
        estimatedDailyDeficit: rateKgPerWeek * 7700 / 7,
        trendDirection: rateKgPerWeek < 0 ? .losing : (rateKgPerWeek > 0 ? .gaining : .maintaining),
        projection30Day: nil, dataPoints: [],
        weightChanges: .init(threeDay: nil, sevenDay: nil, fourteenDay: nil,
                             thirtyDay: thirtyDayKg, ninetyDay: nil),
        config: .default, rateWindowDays: 20,
        longWindowWeeklyRateKg: longWindowKg)
}

@Test func conflictWhenShortRateOpposesThirtyDay() {
    // The field screen: −0.34 lbs/wk (−0.15 kg/wk) next to 30-day +1.0 lbs (+0.45 kg)
    #expect(makeTrend(rateKgPerWeek: -0.15, thirtyDayKg: 0.45).energySignalConflicts)
    #expect(makeTrend(rateKgPerWeek: 0.2, thirtyDayKg: -0.5).energySignalConflicts)
}

// Trigger 2 (field 2026-07-17): the 35-day window slope as second opinion.
// A week-long water rise on a losing body kept the 30-day EMA delta inside
// the dead-band (the rise dragged the current EMA up), so trigger 1 missed
// the phantom "Est. Surplus +204, confident".

@Test func conflictWhenShortRateOpposesLongWindowSlope() {
    // The 2026-07-17 field shape: short +0.19 vs 35d −0.07, EMA delta quiet.
    #expect(makeTrend(rateKgPerWeek: 0.19, thirtyDayKg: -0.1, longWindowKg: -0.07).energySignalConflicts)
    // Mirror: phantom deficit on a gaining body.
    #expect(makeTrend(rateKgPerWeek: -0.15, thirtyDayKg: 0.1, longWindowKg: 0.08).energySignalConflicts)
}

@Test func noConflictWhenLongWindowAgreesOrIsQuiet() {
    #expect(!makeTrend(rateKgPerWeek: 0.19, thirtyDayKg: nil, longWindowKg: 0.15).energySignalConflicts,
            "agreeing long-window slope publishes normally")
    #expect(!makeTrend(rateKgPerWeek: 0.19, thirtyDayKg: nil, longWindowKg: -0.03).energySignalConflicts,
            "a sub-band long-window slope is flat, not an opposing trend")
    #expect(!makeTrend(rateKgPerWeek: 0.19, thirtyDayKg: nil, longWindowKg: nil).energySignalConflicts,
            "no long-window data → nothing to conflict with")
}

@Test func noConflictWhenSignsAgreeOrThirtyDayIsQuiet() {
    #expect(!makeTrend(rateKgPerWeek: -0.2, thirtyDayKg: -0.6).energySignalConflicts,
            "agreeing signals publish normally")
    #expect(!makeTrend(rateKgPerWeek: -0.15, thirtyDayKg: 0.1).energySignalConflicts,
            "a near-zero 30-day is a young trend, not a conflict (dead-band)")
    #expect(!makeTrend(rateKgPerWeek: -0.15, thirtyDayKg: nil).energySignalConflicts,
            "no 30-day data → nothing to conflict with")
    #expect(!makeTrend(rateKgPerWeek: 0, thirtyDayKg: 0.5).energySignalConflicts,
            "maintaining has no sign to conflict")
}

@Test func waterPlungeMustNotReadAsLargeDeficit() {
    let t = WeightTrendCalculator.calculateTrend(
        entries: FieldScenario20260713.entries(),
        config: .default)!
    // Pre-fix (OLS on the 8d-smoothed tail): rawRate −0.41 kg/wk → −447
    // kcal/day. Post-fix (Theil–Sen on raw window pairs): rawRate ≈ −0.24,
    // published rate suppressed by the Mann–Kendall ramp → deficit ≈ 0.
    // Margins are loose on purpose — the pin is "a 5-day water swing after a
    // flat month must not scream a −400 deficit", not an exact number.
    #expect(t.rawWeeklyRateKg > -0.30,
            "raw rate chased the water plunge: \(t.rawWeeklyRateKg) kg/wk")
    #expect(t.estimatedDailyDeficit > -200,
            "published deficit screams on a water swing: \(t.estimatedDailyDeficit) kcal/day")
    #expect(!t.trendIsSignificant,
            "a flat month + 5-day swing is not a confident trend")
}
