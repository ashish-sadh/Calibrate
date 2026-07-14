import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for KalmanWeightTrend — the estimation-unification P1 engine
// (issue #1052, Docs/refactor/estimation-unification.md). The engine is
// OPT-IN (AlgorithmConfig.engine default .heuristic) until the calibration
// closes the two known-open regime scenarios pinned at the bottom.
//
// Calibration matrix measured 2026-07-13 with the default config
// (σ_r 0.016, σ_obs 0.35, water 0.55 kg @ 3.5d half-life):
//   steady −0.35 kg/wk daily ... rate −0.38  z 1.00
//   flat ±1.0 noise .......... rate −0.06  z 0.17   (seeds 13/99: 0.24–0.51 @ 2-state)
//   sparse 4 pts / 2 wks ..... rate −0.43  z 1.03
//   weekly logger 6/35d ...... rate −0.31  z 0.81
//   FIELD water plunge ....... rate −0.26  z 0.69   (2-state filter said z 1.37!)
//   regime 20d gain→10d loss . rate −0.06  z 0.16   ← known-open: water state absorbs it

private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: Date())! }

private func kalmanObs(_ series: [(Int, Double)]) -> [(date: Date, weightKg: Double)] {
    series.sorted { $0.0 > $1.0 }.map { (daysAgo($0.0), $0.1) }
}

private func kalmanPoints(_ series: [(Int, Double)]) -> [WeightTrendCalculator.WeightDataPoint] {
    series.sorted { $0.0 > $1.0 }.map {
        WeightTrendCalculator.WeightDataPoint(
            date: daysAgo($0.0), dateString: "d\($0.0)", actualWeight: $0.1, emaWeight: $0.1)
    }
}

@Test func kalman_convergesOnCleanTrend() {
    let series = (0..<30).map { ago in (ago, 60.0 + Double(ago) * 0.05) }  // −0.35 kg/wk
    let out = KalmanWeightTrend.run(observations: kalmanObs(series))!
    #expect(abs(out.weeklyRateKg - (-0.35)) < 0.12, "rate should track truth: \(out.weeklyRateKg)")
    #expect(out.rateZ > 0.95, "a clean month-long trend must be publishable: z \(out.rateZ)")
}

@Test func kalman_flatNoiseStaysUnconfident() {
    var rng: UInt64 = 42
    func noise() -> Double {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return (Double((rng >> 33) % 1000) / 1000.0 - 0.5) * 2.0
    }
    let series = (0..<30).map { ago in (ago, 60.0 + noise()) }
    let out = KalmanWeightTrend.run(observations: kalmanObs(series))!
    #expect(out.rateZ < WeightTrendCalculator.kalmanRampStartZ,
            "flat noise must stay below the publication ramp: z \(out.rateZ)")
}

@Test func kalman_waterStateAbsorbsASpike() {
    var series = (1..<20).map { ago in (ago, 60.0) }
    series.insert((0, 63.0), at: 0)   // today: +3 kg salt/water day
    let out = KalmanWeightTrend.run(observations: kalmanObs(series))!
    #expect(out.waterKg > 0.2, "the spike should load into the water state: u \(out.waterKg)")
    // z lands low in the ramp (measured 0.69) and the ramped rate falls under
    // the maintaining band -> published 0. Assert the publication-chain truth.
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
    let entries = series.map { (date: formatter.string(from: daysAgo($0.0)), weightKg: $0.1) }
    var config = WeightTrendCalculator.AlgorithmConfig.default
    config.engine = .kalman
    let t = WeightTrendCalculator.calculateTrend(entries: entries, config: config)!
    #expect(t.trendDirection == .maintaining,
            "one spike day must publish as holding steady, got \(t.weeklyRateKg)")
}

@Test func kalman_fieldWaterPlungeStaysSubConfident() {
    // The 2026-07-13 field month: the 2-state filter scored this z=1.37
    // (its most confident signal!); the water state absorbs the plunge.
    let obs = FieldScenario20260713.entries().compactMap { e -> (date: Date, weightKg: Double)? in
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: e.date) else { return nil }
        return (d, e.weightKg)
    }
    let out = KalmanWeightTrend.run(observations: obs)!
    #expect(out.rateZ < WeightTrendCalculator.kalmanRampFullZ,
            "a 5-day water plunge after a flat month must not reach full confidence: z \(out.rateZ)")
    #expect(out.weeklyRateKg > -0.35, "the plunge must not own the rate: \(out.weeklyRateKg)")
}

@Test func kalman_gapGrowsUncertainty() {
    let dense = (0..<20).map { ago in (ago, 60.0 - Double(ago) * 0.03) }
    let withGap = dense.map { ($0.0 >= 10 ? $0.0 + 20 : $0.0, $0.1) }  // 20-day hole
    let a = KalmanWeightTrend.run(observations: kalmanObs(dense))!
    let b = KalmanWeightTrend.run(observations: kalmanObs(withGap))!
    #expect(b.weeklyRateStd > a.weeklyRateStd,
            "a 20-day gap must widen the rate uncertainty (\(b.weeklyRateStd) vs \(a.weeklyRateStd))")
}

@Test func kalmanEngine_endToEnd_publishesCleanTrend() {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX")
    let entries = (0..<30).map { ago in
        (date: formatter.string(from: daysAgo(ago)), weightKg: 60.0 + Double(ago) * 0.05)
    }
    var config = WeightTrendCalculator.AlgorithmConfig.default
    config.engine = .kalman
    let t = WeightTrendCalculator.calculateTrend(entries: entries, config: config)!
    #expect(t.trendDirection == .losing)
    #expect(t.weeklyRateKg < -0.2)
}

// MARK: - Known-open calibration gaps (issue #1052 P1)
// The water state absorbs 10–14-day regime changes at the current tuning —
// the disagreement-resolution layer between engines is the P1 remainder.
// These stay visible as known issues, not silent skips.

@Test func kalman_knownOpen_regimeChangeAfterOppositeTrend() {
    withKnownIssue("#1052: water state absorbs 10-day regime changes at current tuning") {
        var series: [(Int, Double)] = []
        for ago in 10..<30 { series.append((ago, 60.0 + Double(30 - ago) * 0.06)) }
        for ago in 0..<10 { series.append((ago, 61.2 - Double(10 - ago) * 0.09)) }
        let out = KalmanWeightTrend.run(observations: kalmanObs(series))!
        #expect(out.weeklyRateKg < -0.05 && out.rateZ >= WeightTrendCalculator.kalmanRampStartZ,
                "a 10-day genuine reversal should publish: rate \(out.weeklyRateKg) z \(out.rateZ)")
    }
}
