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
