import Testing
import Foundation
@testable import DriftCore

/// Simulation harness for the weight-trend → surplus/deficit → calorie-target
/// pipeline (the 2026-05-29 "heal"). Generates many synthetic profiles, data
/// cadences, trajectories, and noise levels, and asserts the SANITY INVARIANTS
/// that must hold for every one of them — the guardrails the field bug violated:
///   • finite numbers (no NaN/Inf)
///   • correct sign (gaining ⇒ surplus, losing ⇒ deficit; direction agrees)
///   • |surplus/deficit| never absurd (the "no 4000 kcal" rule)
///   • calorie target never recommends below the 1200 floor
///   • stability: daily water-weight noise barely moves the reported number
///   • sparse / stale / calibrating data degrade gracefully, never explode
/// Tier 0: pure logic, in-memory only.
@Suite("Weight/TDEE scenario invariants")
struct WeightTDEEScenarioTests {

    // MARK: - Deterministic helpers

    /// Reproducible noise (no Foundation RNG → stable across runs/machines).
    struct LCG {
        var state: UInt64
        mutating func nextUnit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)   // [0,1)
        }
        mutating func symmetric(_ amp: Double) -> Double { (nextUnit() * 2 - 1) * amp }
    }

    /// Build weigh-ins: `days` of history at `cadence`-day spacing, a linear
    /// trajectory of `ratePerDayKg`, plus ±`noiseKg` water jitter.
    static func entries(days: Int, cadence: Int, startKg: Double, ratePerDayKg: Double,
                        noiseKg: Double, seed: UInt64) -> [(date: String, weightKg: Double)] {
        var rng = LCG(state: seed)
        var out: [(String, Double)] = []
        var d = days - 1
        while d >= 0 {
            let dayIndex = days - 1 - d
            let date = Calendar.current.date(byAdding: .day, value: -d, to: Date())!
            let w = startKg + ratePerDayKg * Double(dayIndex) + rng.symmetric(noiseKg)
            out.append((DateFormatters.dateOnly.string(from: date), max(30, w)))
            d -= cadence
        }
        return out
    }

    /// Every invariant a trend must satisfy, whatever the input.
    static func assertSane(_ t: WeightTrendCalculator.WeightTrend, _ label: String) {
        #expect(t.weeklyRateKg.isFinite, "\(label): rate must be finite")
        #expect(t.estimatedDailyDeficit.isFinite, "\(label): deficit must be finite")
        #expect(t.currentEMA.isFinite && t.currentEMA > 0, "\(label): trend weight sane")
        // The "no 4000-kcal surplus" rule — clamped rate ⇒ bounded energy balance.
        #expect(abs(t.weeklyRateKg) <= WeightTrendCalculator.maxAbsWeeklyRateKg + 1e-6,
                "\(label): rate clamped, got \(t.weeklyRateKg)")
        #expect(abs(t.estimatedDailyDeficit) <= 1700,
                "\(label): |daily energy balance| must stay sane, got \(t.estimatedDailyDeficit)")
        if let p = t.projection30Day { #expect(p.isFinite && p > 0, "\(label): projection sane") }
        // Direction must agree with the sign of the rate.
        switch t.trendDirection {
        case .gaining: #expect(t.weeklyRateKg > 0, "\(label): gaining ⇒ rate>0")
        case .losing:  #expect(t.weeklyRateKg < 0, "\(label): losing ⇒ rate<0")
        case .maintaining:
            #expect(abs(t.weeklyRateKg) <= t.config.maintainingThresholdKgPerWeek + 1e-6,
                    "\(label): maintaining ⇒ |rate| small")
        }
        // Deficit sign tracks rate sign (surplus when gaining, deficit when losing).
        if t.weeklyRateKg > 0 { #expect(t.estimatedDailyDeficit >= 0, "\(label): gaining ⇒ surplus") }
        if t.weeklyRateKg < 0 { #expect(t.estimatedDailyDeficit <= 0, "\(label): losing ⇒ deficit") }
    }

    // MARK: - Parameterized sweep (profiles × trajectories × cadence)

    @Test(arguments: [52.0, 70.0, 95.0, 125.0],
                     [-0.12, -0.05, 0.0, 0.05, 0.12])
    func sweep_boundsSignStability(startKg: Double, ratePerDayKg: Double) async throws {
        var caseIndex = 0
        for cadence in [1, 3, 7] {
            for noise in [0.0, 0.8, 1.8] {
                caseIndex += 1
                let seed = UInt64(bitPattern: Int64(startKg * 100) ^ Int64(ratePerDayKg * 1000) ^ Int64(cadence * 31 + caseIndex))
                let es = Self.entries(days: 35, cadence: cadence, startKg: startKg,
                                      ratePerDayKg: ratePerDayKg, noiseKg: noise, seed: seed)
                guard let t = WeightTrendCalculator.calculateTrend(entries: es) else { continue }
                let label = "w=\(startKg) r=\(ratePerDayKg) cad=\(cadence) noise=\(noise)"
                Self.assertSane(t, label)
                // A clearly-directional, low-noise, well-sampled trajectory must
                // not report the WRONG direction (the core bug).
                if cadence <= 3, noise <= 0.8, !t.hasInsufficientData, abs(ratePerDayKg) >= 0.05 {
                    if ratePerDayKg < 0 { #expect(t.weeklyRateKg < 0.05, "\(label): real loss not shown as gain") }
                    if ratePerDayKg > 0 { #expect(t.weeklyRateKg > -0.05, "\(label): real gain not shown as loss") }
                }
            }
        }
    }

    // MARK: - Stability: noise must barely move the number

    @Test(arguments: [-0.08, 0.0, 0.08])
    func stability_addingADayBarelyMovesRate(ratePerDayKg: Double) async throws {
        // The real "changes constantly" complaint is day-to-day jitter: when one
        // more weigh-in lands, the reported surplus/deficit must barely move.
        // Realistic ±1.0 kg daily water noise.
        let full = Self.entries(days: 35, cadence: 1, startKg: 80, ratePerDayKg: ratePerDayKg, noiseKg: 1.0, seed: 3)
        let prior = Array(full.dropLast())   // "yesterday's view"
        guard let a = WeightTrendCalculator.calculateTrend(entries: full),
              let b = WeightTrendCalculator.calculateTrend(entries: prior) else { return }
        let jumpKcal = abs(a.estimatedDailyDeficit - b.estimatedDailyDeficit)
        #expect(jumpKcal < 150, "One new weigh-in moved the deficit by \(jumpKcal) kcal — too jumpy")
        if abs(ratePerDayKg) >= 0.05 {
            #expect((a.weeklyRateKg > 0) == (b.weeklyRateKg > 0), "One day flipped the sign")
        }
    }

    // MARK: - Pathological inputs must never explode

    @Test func pathological_neverAbsurd() async throws {
        let cal = Calendar.current
        let today = Date()
        func d(_ ago: Int) -> String { DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -ago, to: today)!) }

        let cases: [(String, [(date: String, weightKg: Double)])] = [
            ("single huge spike", [(d(20), 80), (d(15), 80), (d(10), 80), (d(5), 140), (d(0), 80)]),
            ("alternating ±5kg", (0..<21).map { (d(20 - $0), 80.0 + ($0 % 2 == 0 ? -5 : 5)) }),
            ("two points 14d apart, 8kg jump", [(d(14), 72), (d(0), 80)]),
            ("stale: all >50d old", [(d(80), 90), (d(70), 88), (d(60), 86), (d(55), 85)]),
            ("one ancient + one fresh", [(d(120), 60), (d(0), 95)]),
            ("crash-diet 10kg in 14d", (0..<15).map { (d(14 - $0), 90.0 - Double($0) * 0.71) }),
        ]
        for (name, es) in cases {
            guard let t = WeightTrendCalculator.calculateTrend(entries: es) else { continue }
            Self.assertSane(t, "pathological:\(name)")
        }
    }

    // MARK: - Sparse / stale / calibrating degrade gracefully

    @Test func sparse_weeklyLogger_getsReasonableRate() async throws {
        // 6 weekly weigh-ins over 35 days, steady ~0.4 kg/wk loss.
        let es = Self.entries(days: 36, cadence: 7, startKg: 82, ratePerDayKg: -0.057, noiseKg: 0.3, seed: 9)
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        #expect(!t.hasInsufficientData, "Weekly logger across 5 weeks should qualify")
        Self.assertSane(t, "sparse-weekly")
        #expect(t.weeklyRateKg < 0.05, "Weekly logger's steady loss should read as loss/flat")
    }

    @Test func stale_dataIsSuppressedNotExploded() async throws {
        let cal = Calendar.current; let today = Date()
        // Everything older than the rate lookback (45d) ⇒ no trustworthy rate.
        let es = (0..<5).map { i -> (date: String, weightKg: Double) in
            (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -(95 - i * 5), to: today)!), 90.0 - Double(i))
        }
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        #expect(t.hasInsufficientData, "Stale-only data must not publish a rate")
        #expect(t.estimatedDailyDeficit == 0, "Stale ⇒ zero deficit placeholder, never a spike")
        #expect(t.projection30Day == nil)
    }

    @Test func calibrating_shortHistoryIsInsufficient() async throws {
        // < 14-day span ⇒ calibrating (can't trust a rate yet).
        let cal = Calendar.current; let today = Date()
        let es = (0..<5).map { i -> (date: String, weightKg: Double) in
            (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -(8 - i * 2), to: today)!), 70.0)
        }
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        #expect(t.hasInsufficientData, "Span < 14 days ⇒ calibrating, no published rate")
    }

    // MARK: - Named field regression: the screenshot bug

    @Test func regression_gainingMonthWithRecentWaterDrop_showsSurplusNotDeficit() async throws {
        // The reported bug: net weight GAIN over the month, but a sharp recent
        // 3-day water drop made the old two-window method report a DEFICIT.
        // Model ~daily logging: steady gain + oscillation, then a 3-day dip.
        var es: [(date: String, weightKg: Double)] = []
        let cal = Calendar.current; let today = Date()
        var rng = LCG(state: 42)
        for day in 0..<28 {
            let ago = 27 - day
            let base = 53.3 + 0.045 * Double(day)          // ≈ +1.2 kg over 28d (real gain)
            var w = base + rng.symmetric(0.6)              // daily water oscillation
            if ago <= 2 { w -= 1.1 }                       // recent 3-day water drop (~2.4 lb)
            es.append((DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -ago, to: today)!), w))
        }
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        Self.assertSane(t, "screenshot-regression")
        #expect(t.weeklyRateKg > 0, "Real monthly gain must read as gain despite the recent water dip. Got \(t.weeklyRateKg) kg/wk")
        #expect(t.estimatedDailyDeficit > 0, "⇒ SURPLUS, not the buggy deficit. Got \(t.estimatedDailyDeficit) kcal/day")
    }

    @Test func regression_waterSpikeDoesNotFlipSign() async throws {
        // Flat-to-slightly-losing trajectory; one +3kg salty-meal day must not
        // flip the reported direction to gaining.
        var es = Self.entries(days: 28, cadence: 1, startKg: 75, ratePerDayKg: -0.03, noiseKg: 0.3, seed: 7)
        es[24].weightKg += 3.0
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        Self.assertSane(t, "water-spike")
        #expect(t.weeklyRateKg < 0.1, "A single salty-meal spike must not flip a flat/losing trend to a gain")
    }

    // MARK: - Calorie target never recommends below the safety floor

    @Test(arguments: [900.0, 1100.0, 1400.0, 1800.0, 2400.0, 3200.0],
                     [1, 2, 4, 9])
    func targetNeverBelow1200(tdee: Double, months: Int) async throws {
        let cal = Calendar.current
        let start = DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -1, to: Date())!)
        // Aggressive cut: target far below start, short horizon → big requested deficit.
        let goal = WeightGoal(targetWeightKg: 60, monthsToAchieve: months, startDate: start, startWeightKg: 95)
        let target = goal.resolvedCalorieTarget(currentWeightKg: 95, actualTDEE: tdee)
        let resolved = try #require(target)
        #expect(resolved >= 1200, "Target \(resolved) must never fall below the 1200 safety floor (tdee=\(tdee), months=\(months))")
        #expect(resolved.isFinite)
    }
}
