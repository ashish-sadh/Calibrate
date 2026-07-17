import Foundation
@testable import DriftCore
import Testing

// Field scenario 2026-07-17: the operator's real weigh-in history (read off
// the History log screenshots). A June bulk (~118 → 121, with the Jun 23
// 123.6 lb spike) followed by a genuine cut from Jul 5 (121.5 → ~118.5) —
// but a 10-day logging gap (Jun 26 – Jul 4) left the 21-day window with 9
// points spanning only 12 days. The old span-only sufficiency rule (≥14d)
// called that insufficient and widened straight to 45 days, so Drift
// published the BULK's climb as the current trend: "+0.20 lbs/wk ↗ gaining,
// Est. Surplus +100" — while the operator's reference app read the same
// three weeks as −0.15 kg/wk / −165 kcal/day. Dense short runs (≥6 points,
// ≥10 days) are now sufficient, so the recent cut is measured directly.

enum FieldScenario20260717 {
    static let lbsByDaysAgo: [(ago: Int, lb: Double)] = [
        (0, 120.0), (1, 118.8), (2, 118.1), (3, 119.0), (4, 117.9),
        (8, 118.8), (9, 119.7), (11, 120.2), (12, 121.5),
        // 10-day logging gap (Jun 26 – Jul 4)
        (22, 120.4), (23, 121.8), (24, 123.6), (25, 119.8), (26, 119.3),
        (28, 119.3), (29, 118.4), (30, 117.7), (32, 117.2), (33, 119.0),
        (34, 119.3), (35, 119.7), (36, 119.4), (37, 118.3), (38, 118.5),
        (43, 116.8), (44, 118.2),
    ]

    static func entries() -> [(date: String, weightKg: Double)] {
        let cal = Calendar.current; let today = Date()
        return lbsByDaysAgo.map { e in
            (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -e.ago, to: today)!),
             e.lb / 2.20462)
        }
    }
}

@Test func gapBeforeRegimeChange_mustNotPublishThePriorRegime() {
    let t = WeightTrendCalculator.calculateTrend(
        entries: FieldScenario20260717.entries(),
        config: .default)!
    // The pin: the published state must never be the OLD regime's direction.
    // The recent three weeks are a real cut; "gaining / +100 surplus" is the
    // one reading the data cannot support.
    #expect(t.trendDirection != .gaining,
            "bulk-era window leaked into the current trend: \(t.trendDirection), \(t.weeklyRateKg) kg/wk")
    #expect(t.weeklyRateKg <= 0,
            "published rate must not be surplus-side: \(t.weeklyRateKg) kg/wk")
    #expect(t.estimatedDailyDeficit <= 0,
            "published balance must not read a surplus: \(t.estimatedDailyDeficit) kcal/day")
    // The raw (pre-ramp) rate must point where the reference app points:
    // deficit side, from the RECENT dense window — not the 45-day fallback.
    #expect(t.rawWeeklyRateKg < -0.1,
            "raw rate should read the recent cut (~−0.2 kg/wk), got \(t.rawWeeklyRateKg)")
    #expect(t.rateWindowDays <= 14,
            "rate must come from the recent dense run, not the 45d fallback: \(t.rateWindowDays)d")
}

@Test func denseShortRun_isSufficient_sparseShortRunIsNot() {
    let cal = Calendar.current; let today = Date()
    func pts(_ agos: [Int]) -> [WeightTrendCalculator.WeightDataPoint] {
        agos.map { ago in
            let d = cal.date(byAdding: .day, value: -ago, to: today)!
            return WeightTrendCalculator.WeightDataPoint(
                date: d, dateString: DateFormatters.dateOnly.string(from: d),
                actualWeight: 54, emaWeight: 54)
        }.sorted { $0.date < $1.date }
    }
    // 9 points over 12 days: dense — sufficient.
    #expect(WeightTrendCalculator.isSufficient(pts([0, 1, 2, 3, 4, 8, 9, 11, 12])))
    // 2 points 12 days apart: sparse short span — still insufficient (#842).
    #expect(!WeightTrendCalculator.isSufficient(pts([0, 12])))
    // 5 points over 8 days: not enough of either — insufficient (calibrating).
    #expect(!WeightTrendCalculator.isSufficient(pts([0, 2, 4, 6, 8])))
    // 2 points ≥14 days apart: the fortnightly logger keeps qualifying.
    #expect(WeightTrendCalculator.isSufficient(pts([0, 14])))
}
