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

    @Test func regression_recentWaterDrop_neverShowsDeficit() async throws {
        // The reported bug: net weight GAIN over the month, but a sharp recent
        // 3-day water drop made the old method report a DEFICIT. Model ~daily
        // logging: steady gain + oscillation, then a 3-day dip.
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
        Self.assertSane(t, "recent-water-drop")
        // The invariant: a recent water dip must NEVER flip a gaining/flat
        // trajectory to a DEFICIT. With the significance gate (2026-05-29), this
        // case reads MAINTAINING over the responsive window — the recent 3 weeks
        // net flat once the dip cancels the in-window gain, so a confident
        // "surplus" isn't warranted, but it is correctly NOT a deficit. (Showing
        // surplus would require trusting the gain through the recent dip; the
        // responsive window can't, and a wider window that could would blind the
        // rate to genuine recent regime changes — see regimeChange_* tests.)
        #expect(t.estimatedDailyDeficit >= 0, "A recent water dip must never produce a phantom DEFICIT on a gaining/flat trajectory. Got \(t.estimatedDailyDeficit) kcal/day")
        #expect(t.trendDirection != .losing, "Must not read as losing after a recent water dip on a gaining trend. Got \(t.trendDirection)")
    }

    // MARK: - Field regression 2026-07-17: the mirror of recentWaterDrop

    /// 28 days of genuine steady loss (~−0.3 kg/wk — a real ~−350 kcal/day
    /// deficit, which the operator's reference app showed) with a recent
    /// multi-day water/refeed RISE. Pre-fix, the 21-day window read the
    /// V-shape as a CONFIDENT goal-red "Est. Surplus +204/day" and the
    /// conflict gate missed it: the rise dragged the current EMA up, so the
    /// 30-day EMA delta sat inside the ±0.15 dead-band. The fix adds the
    /// 35-day window slope as a second conflict trigger — a surplus-side rate
    /// may still be PUBLISHED (the chart's tail does climb), but it must
    /// carry the soft/conflicted treatment, never confident goal colors.
    static func losingWithRecentRise(riseKg: Double, riseDays: Int, seed: UInt64) -> [(date: String, weightKg: Double)] {
        var es: [(date: String, weightKg: Double)] = []
        let cal = Calendar.current; let today = Date()
        var rng = LCG(state: seed)
        for day in 0..<28 {
            let ago = 27 - day
            var w = 84.0 - 0.045 * Double(day) + rng.symmetric(0.6)
            if ago < riseDays { w += riseKg }
            es.append((DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -ago, to: today)!), w))
        }
        return es
    }

    @Test(arguments: [UInt64(42), 7, 99])
    func regression_recentWaterRise_neverConfidentSurplusOnLosingTrend(seed: UInt64) async throws {
        for (riseKg, riseDays) in [(1.1, 3), (1.5, 4), (1.2, 7), (1.8, 7), (1.0, 10)] {
            let es = Self.losingWithRecentRise(riseKg: riseKg, riseDays: riseDays, seed: seed)
            let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
            let label = "loss+rise \(riseKg)kg x\(riseDays)d seed=\(seed)"
            Self.assertSane(t, label)
            if t.weeklyRateKg > 0 {
                #expect(t.energySignalConflicts,
                        "\(label): a water rise on a genuinely losing body published a CONFIDENT surplus (+\(Int(t.estimatedDailyDeficit)) kcal/day) — must carry the soft/conflicted treatment")
            }
        }
    }

    @Test(arguments: [UInt64(42), 7, 99])
    func steadyTrends_areNotSoftenedByLongWindowCheck(seed: UInt64) async throws {
        // The new conflict trigger must not soften genuine sustained trends:
        // over 35 days the wide window's slope agrees in sign with the short
        // rate for both steady gain and steady loss.
        for rate in [0.05, -0.05] {
            let es = Self.entries(days: 35, cadence: 1, startKg: 80, ratePerDayKg: rate, noiseKg: 0.5, seed: seed)
            let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
            #expect(!t.energySignalConflicts,
                    "steady \(rate > 0 ? "gain" : "loss") seed=\(seed) must publish confidently, got conflicted (rate \(t.weeklyRateKg), long \(String(describing: t.longWindowWeeklyRateKg)))")
        }
    }

    @Test func sustainedRegimeChange_publishesGainConfidently() async throws {
        // 19 days of loss then a REAL 21-day bulk: by the time the short rate
        // flips positive, the 35-day slope has flipped too — a sustained
        // regime change must NOT be stuck in the soft/conflicted state.
        var es: [(date: String, weightKg: Double)] = []
        let cal = Calendar.current; let today = Date()
        var rng = LCG(state: 42)
        for day in 0..<40 {
            let ago = 39 - day
            var w: Double
            if ago < 21 {
                w = 80 - 0.045 * 19 + 0.8 + 0.05 * Double(21 - ago)
            } else {
                w = 80 - 0.045 * Double(day)
            }
            w += rng.symmetric(0.5)
            es.append((DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -ago, to: today)!), w))
        }
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        Self.assertSane(t, "sustained regime change")
        #expect(!t.energySignalConflicts,
                "a 3-week sustained bulk must publish confidently, got conflicted (rate \(t.weeklyRateKg), long \(String(describing: t.longWindowWeeklyRateKg)))")
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

    @Test func regression_flatNoisyMaintainer_reportsHoldingNotInventedDeficit() async throws {
        // 2026-05-29 field report — the user's FULL real weigh-in history (read off
        // the History log, Mar 27 → May 29). Monthly means: Mar ~119.0, Apr ~117.2,
        // May ~118.7 — down then back up, net flat over the quarter with an April
        // dip, oscillating ±2-3 lb throughout. Definitively NOT losing. With no
        // significance gate the calculator fit a confident slope to this noise, so
        // the 1M view showed "Est. Deficit −248" while 3M showed "Est. Surplus +185"
        // — same DB, opposite signs. The fix: a deficit needs the robust window to
        // slope significantly DOWN, which this data never does — so it reads
        // maintaining or a mild surplus, NEVER a deficit. Dates relative (newest =
        // today) so the case stays valid on any run date.
        let realLbsByDaysAgo: [(ago: Int, lb: Double)] = [
            (0, 120.5), (1, 117.9), (2, 119.2), (3, 120.4), (8, 118.2), (10, 116.6),
            (11, 117.8), (12, 118.7), (14, 116.7), (18, 119.6), (19, 120.3), (20, 120.9),
            (21, 118.2), (22, 119.4), (24, 117.5), (29, 115.2), (32, 117.6), (33, 118.6),
            (35, 117.3), (36, 116.4), (37, 117.4), (38, 115.9), (39, 117.3), (40, 120.0),
            (41, 118.7), (42, 117.0), (43, 115.9), (44, 115.5), (45, 114.8), (46, 117.2),
            (47, 116.5), (51, 118.5), (52, 117.3), (53, 115.5), (54, 117.4), (55, 116.0),
            (56, 117.1), (57, 117.1), (58, 118.5), (59, 119.6), (60, 116.5), (61, 117.0),
            (62, 117.5), (63, 116.5),
        ]
        let cal = Calendar.current; let today = Date()
        let es = realLbsByDaysAgo.map { e -> (date: String, weightKg: Double) in
            (DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -e.ago, to: today)!), e.lb / 2.20462)
        }
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        Self.assertSane(t, "flat-noisy-maintainer")
        #expect(!t.hasInsufficientData, "44 weigh-ins over 2 months is plenty of data — not a calibrating state")
        #expect(t.estimatedDailyDeficit >= 0, "Flat/oscillating, non-losing weight must NEVER read as a calorie DEFICIT (the field bug). Got \(t.estimatedDailyDeficit) kcal/day")
        #expect(t.weeklyRateKg >= 0, "Must not report a maintaining/gaining user as losing. Got \(t.weeklyRateKg) kg/wk")
        #expect(t.weeklyRateKg < 0.6, "Must not over-read flat-noisy data as a strong gain. Got \(t.weeklyRateKg) kg/wk")
    }

    @Test(arguments: [UInt64(1), 7, 13, 42, 99, 256, 1024])
    func flatNoise_reportsMaintaining_notWindowDependentSign(seed: UInt64) async throws {
        // The fix in isolation: pure maintenance — zero real trend, heavy ±1.5 kg
        // daily water noise, 45 daily weigh-ins. The OLS slope's sign here is pure
        // chance; before the significance gate it produced a confident, window- and
        // noise-dependent surplus/deficit (the −248 vs +185 flip). The gate must
        // collapse it to maintaining (rate 0, zero balance) for genuinely flat data.
        let es = Self.entries(days: 45, cadence: 1, startKg: 54, ratePerDayKg: 0, noiseKg: 1.5, seed: seed)
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        Self.assertSane(t, "flat-noise seed=\(seed)")
        // At a 95% gate, ~5% of pure-noise samples are chance-"significant" — that's
        // inherent, not a bug. The win is that the WIDE window keeps any such reading
        // TINY (noise averages out over 45 points): never the dramatic ±200 the old
        // short-window slope produced. So the robust invariant is "no dramatic
        // phantom balance", not "exactly zero every time".
        #expect(abs(t.estimatedDailyDeficit) < 100, "Pure noise must never produce a dramatic surplus/deficit; got \(t.estimatedDailyDeficit) kcal/day (seed \(seed), \(t.weeklyRateKg) kg/wk)")
    }

    // MARK: - TDEE sanity band across weight groups (the "lb×15" complaint)

    /// Sex-averaged Mifflin (moderate activity 1.55, defaults age 30 / 170cm)
    /// — the physiologically defensible reference the base must track.
    static func mifflinSexAveraged(weightKg: Double, activityFactor: Double = 1.55) -> Double {
        (10 * weightKg + 6.25 * 170 - 150 + (5.0 - 161.0) / 2) * activityFactor
    }

    @Test(arguments: [45.0, 55.0, 70.0, 85.0, 100.0, 120.0, 140.0])
    func base_tracksMifflinAcrossWeightGroups(weightKg: Double) async throws {
        // No profile filled in: the base must sit within ±15% of sex-averaged
        // Mifflin. The old 2000·√(w/70) curve failed this from 85kg up (−22%
        // at 85kg, −30% at 120kg) — the top field complaint from heavier
        // users and users who never completed their profile.
        let base = TDEEEstimator.computeBase(weightKg: weightKg, activityMultiplier: 29)
        let reference = Self.mifflinSexAveraged(weightKg: weightKg)
        let deviation = abs(base - reference) / reference
        #expect(deviation < 0.15,
                "\(Int(weightKg))kg no-profile base \(Int(base)) deviates \(Int(deviation * 100))% from Mifflin \(Int(reference))")
        #expect(base >= 1200)
    }

    @Test(arguments: [45.0, 55.0, 70.0, 85.0, 100.0, 120.0],
                     [TDEEEstimator.Sex.male, TDEEEstimator.Sex.female])
    func fullProfile_landsNearMifflin(weightKg: Double, sex: TDEEEstimator.Sex) async throws {
        // With a complete profile the estimate must land close to the real
        // Mifflin for that person — the profile is the best information we
        // have before measured data arrives.
        var config = TDEEEstimator.TDEEConfig.default
        config.age = 35
        config.heightCm = sex == .male ? 175 : 162
        config.sex = sex
        let (mifflin, _) = TDEEEstimator.computeMifflin(weightKg: weightKg, config: config)!
        let r = TDEEEstimator.blend(weightKg: weightKg, config: config, appleHealthTDEE: nil, weightTrendTDEE: nil)
        let deviation = abs(r.tdee - mifflin) / mifflin
        #expect(deviation < 0.12,
                "\(Int(weightKg))kg \(sex.rawValue) full-profile \(Int(r.tdee)) deviates \(Int(deviation * 100))% from Mifflin \(Int(mifflin))")
    }

    @Test func base_isMonotonicInWeight() async throws {
        // Heavier must never mean a LOWER estimate, at any activity level.
        for act in [22.0, 29.0, 36.0] {
            var prev = 0.0
            for w in stride(from: 40.0, through: 180.0, by: 5) {
                let base = TDEEEstimator.computeBase(weightKg: w, activityMultiplier: act)
                #expect(base > prev, "base(\(w)kg, act \(act)) = \(base) not > base(\(w - 5)kg) = \(prev)")
                prev = base
            }
        }
    }

    // MARK: - Sparse weigh-ins must not drag TDEE toward intake

    @Test func insufficientTrend_neverAnchorsTDEEToIntake() async throws {
        // A calibrating trend (<14d span) publishes deficit 0 as a PLACEHOLDER.
        // Anchoring TDEE = intake − 0 against it tells a dieter their
        // maintenance IS their (deficit) intake. The blend must not see a
        // trend anchor at all in that state — mirrored here through the same
        // pure pieces the estimator composes.
        let cal = Calendar.current; let today = Date()
        func d(_ ago: Int) -> String { DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -ago, to: today)!) }
        // Two weigh-ins 5 days apart: insufficient span.
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: [(d(5), 80.0), (d(0), 79.8)]))
        #expect(t.hasInsufficientData)
        // The estimator's guard: insufficient trend ⇒ no trend TDEE ⇒ blend
        // falls back to base, NOT toward the 1500 kcal the user is eating.
        let base = TDEEEstimator.computeBase(weightKg: 80, activityMultiplier: 29)
        let r = TDEEEstimator.blend(weightKg: 80, config: .default, appleHealthTDEE: nil, weightTrendTDEE: nil)
        #expect(abs(r.tdee - base) < 0.001,
                "With no real trend the estimate must stay at base \(Int(base)), got \(Int(r.tdee))")
    }

    // MARK: - EMA-slope rate (2026-07-07 operator decision: always report)

    @Test func emaSlopeRate_isAlwaysReportedWithConfidenceFlag() async throws {
        // A gentle real drift (+0.056 kg/wk-ish) through heavy noise: the
        // published rate is the EMA slope — reported even when the raw
        // weigh-ins don't clear statistical significance. Confidence rides
        // the trendIsSignificant flag instead of zeroing the number.
        let es = Self.entries(days: 40, cadence: 1, startKg: 54.5, ratePerDayKg: 0.008, noiseKg: 1.2, seed: 21)
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        #expect(t.rawWeeklyRateKg.isFinite)
        #expect(abs(t.rawWeeklyRateKg) <= WeightTrendCalculator.maxAbsWeeklyRateKg + 1e-6)
        if t.trendDirection == .maintaining {
            #expect(t.weeklyRateKg == 0, "Sub-band slope collapses to 0 (genuinely flat)")
        } else {
            #expect(t.weeklyRateKg == t.rawWeeklyRateKg, "Published rate IS the (clamped) EMA slope — no significance zeroing")
        }
        #expect(t.rawEstimatedDailyDeficit == t.rawWeeklyRateKg * t.config.kcalPerKg / 7)
    }

    @Test func emaSlopeRate_calmOnSpikeButPresentOnRealTrend() async throws {
        // The 622-vs-418 field case in miniature: a steady gain with one big
        // water spike. The EMA slope must (a) still REPORT a surplus-side
        // rate (no "holding steady" hedge on a real climb), (b) not be
        // dramatically inflated by the single spike day.
        var es = Self.entries(days: 35, cadence: 1, startKg: 53.5, ratePerDayKg: 0.055, noiseKg: 0.4, seed: 11)
        es[30].weightKg += 1.7   // one salty-meal / water spike near the end
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        Self.assertSane(t, "spiked-gain")
        #expect(t.weeklyRateKg > 0.1, "A real gain must be reported, got \(t.weeklyRateKg) kg/wk")
        // True rate is 0.385 kg/wk; the spike must not balloon it (the old
        // light-smooth slope overshot ~60% on this shape).
        #expect(t.weeklyRateKg < 0.55, "Spike inflated the EMA slope too much: \(t.weeklyRateKg) kg/wk")
    }

    @Test func insufficientData_rawRateIsZeroPlaceholder() async throws {
        let cal = Calendar.current; let today = Date()
        func d(_ ago: Int) -> String { DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -ago, to: today)!) }
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: [(d(5), 80.0), (d(0), 79.8)]))
        #expect(t.hasInsufficientData)
        #expect(t.rawWeeklyRateKg == 0, "Calibrating state must not publish a raw rate either")
    }

    // MARK: - Field regression 2026-07-08: gap+spike real trend must report

    @Test func regression_gapAndSpikeRealTrend_reportsNotHoldingSteady() async throws {
        // The operator's EXACT weigh-in window that exposed the OLS-t gate:
        // 9 points — a steady climb, one +3.8 lb water spike (day -15), and a
        // 10-day logging gap — while the 14d/30d trend deltas both showed
        // "+1.4/+1.6 Increase" on the same screen. OLS-t scored 0.96 (below
        // the pure-noise ceiling of ~0.9, unreportable); Mann–Kendall scores
        // Z≈1.68 (clear monotonic trend). The cards must report a gain, not
        // "Holding steady" under a visibly climbing chart.
        let cal = Calendar.current; let today = Date()
        func d(_ ago: Int) -> String { DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -ago, to: today)!) }
        let lbs: [(ago: Int, lb: Double)] = [
            (20, 118.4), (19, 119.3), (17, 119.3), (16, 119.8), (15, 123.6),
            (14, 121.8), (13, 120.4), (3, 121.5), (2, 120.2),
        ]
        let es = lbs.map { (d($0.ago), $0.lb / 2.20462) }
        let t = try #require(WeightTrendCalculator.calculateTrend(entries: es))
        Self.assertSane(t, "gap-and-spike real trend")
        #expect(!t.hasInsufficientData)
        #expect(t.trendDirection == .gaining,
                "A consistent climb through a spike + logging gap must READ as gaining, got \(t.trendDirection)")
        #expect(t.weeklyRateKg > 0.08,
                "Rate must be reported (not ramp-zeroed), got \(t.weeklyRateKg) kg/wk")
        #expect(t.estimatedDailyDeficit > 50,
                "A visible surplus must be shown, got \(t.estimatedDailyDeficit) kcal/day")
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
