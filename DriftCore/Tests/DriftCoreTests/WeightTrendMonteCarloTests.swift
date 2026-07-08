import Foundation
@testable import DriftCore
import Testing

/// Tier-4 Monte-Carlo validation of the weight-trend report gate (env-gated:
/// `DRIFT_MONTE_CARLO=1 swift test --filter MonteCarlo`). One real user can't
/// validate a population algorithm — this generates thousands of synthetic
/// trajectories with KNOWN ground truth across the population space (noise
/// model × amplitude × cadence × trajectory family) and measures the gate's
/// actual error rates:
///   • false-positive rate — flat-truth trajectories reported as trending,
///     split into "any report" and "dramatic phantom" (|balance| ≥ 100 kcal,
///     the May-2026 field-bug threshold)
///   • sign-error rate — real trends reported with the WRONG direction
///     (the worst failure: "+1.2 lbs but −213 kcal deficit")
///   • detection rate + latency — how many real trends are reported by day
///     N after onset
/// Bounds below were MEASURED (2026-07-08) then pinned with headroom; a gate
/// change that degrades any of them fails this suite. Two noise nulls:
/// iid (worst-case textbook null) and AR(1) φ=0.6 (persistent multi-day
/// water-retention episodes — the realistic and HARDER null for trend tests).
@Suite("Weight trend Monte-Carlo",
       .enabled(if: ProcessInfo.processInfo.environment["DRIFT_MONTE_CARLO"] == "1"))
struct WeightTrendMonteCarloTests {

    // MARK: - Deterministic generator

    struct LCG {
        var state: UInt64
        mutating func nextUnit() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func symmetric(_ amp: Double) -> Double { (nextUnit() * 2 - 1) * amp }
    }

    enum Noise {
        case iid(amp: Double)              // independent daily draws
        case ar1(phi: Double, amp: Double) // persistent water episodes
    }

    enum Cadence {
        case daily
        case adherence(Double)   // logs each day with probability p
        case everyN(Int)
        case dailyWithGap(start: Int, len: Int)
    }

    /// Generate weigh-ins for `days` days ending today. `base` maps day index
    /// (0 = oldest) to true weight; noise/spikes/cadence layer on top.
    static func trajectory(days: Int, seed: UInt64, base: (Int) -> Double,
                           noise: Noise, cadence: Cadence,
                           spikeProb: Double = 0) -> [(date: String, weightKg: Double)] {
        var rng = LCG(state: seed &* 2654435761 &+ 12345)
        var w = 0.0
        let cal = Calendar.current; let today = Date()
        var out: [(String, Double)] = []
        var sinceLog = 99
        for day in 0..<days {
            switch noise {
            case .iid(let amp): w = rng.symmetric(amp)
            case .ar1(let phi, let amp):
                // innovation scaled so stationary sd ≈ amp
                w = phi * w + rng.symmetric(amp * (1 - phi * phi).squareRoot())
            }
            let logs: Bool
            switch cadence {
            case .daily: logs = true
            case .adherence(let p): logs = rng.nextUnit() < p
            case .everyN(let n): logs = sinceLog >= n
            case .dailyWithGap(let start, let len): logs = !(day >= start && day < start + len)
            }
            sinceLog = logs ? 1 : sinceLog + 1
            guard logs else { continue }
            var v = base(day) + w
            if spikeProb > 0, rng.nextUnit() < spikeProb {
                v += (rng.nextUnit() > 0.5 ? 1 : -1) * (0.9 + rng.nextUnit() * 0.9) // ±0.9–1.8 kg
            }
            let ago = days - 1 - day
            guard let d = cal.date(byAdding: .day, value: -ago, to: today) else { continue }
            out.append((DateFormatters.dateOnly.string(from: d), max(30, v)))
        }
        return out
    }

    struct Tally {
        var runs = 0, reported = 0, dramatic = 0, signErrors = 0, detected = 0
        var pctReported: Double { runs == 0 ? 0 : Double(reported) / Double(runs) * 100 }
        var pctDramatic: Double { runs == 0 ? 0 : Double(dramatic) / Double(runs) * 100 }
        var pctSignError: Double { runs == 0 ? 0 : Double(signErrors) / Double(runs) * 100 }
        var pctDetected: Double { runs == 0 ? 0 : Double(detected) / Double(runs) * 100 }
    }

    static func run(_ es: [(date: String, weightKg: Double)], truthSign: Int, tally: inout Tally) {
        guard let t = WeightTrendCalculator.calculateTrend(entries: es), !t.hasInsufficientData else { return }
        tally.runs += 1
        let r = t.weeklyRateKg
        if r != 0 { tally.reported += 1 }
        if truthSign == 0 {
            if abs(t.estimatedDailyDeficit) >= 100 { tally.dramatic += 1 }
        } else {
            if r != 0 && (r > 0) != (truthSign > 0) { tally.signErrors += 1 }
            if r != 0 && (r > 0) == (truthSign > 0) { tally.detected += 1 }
        }
    }

    // MARK: - False positives on flat-truth families

    @Test func falsePositives_flatFamilies() async throws {
        let amps = [0.4, 0.8, 1.4]                       // daily noise sd, kg
        let cadences: [(String, Cadence)] = [("daily", .daily), ("60%", .adherence(0.6)), ("every3", .everyN(3))]
        var results: [String: Tally] = [:]

        for (ci, cad) in cadences {
            for amp in amps {
                for seed in 0..<60 {
                    var t1 = results["flat-iid \(ci)", default: Tally()]
                    Self.run(Self.trajectory(days: 40, seed: UInt64(seed) &+ 1, base: { _ in 62 },
                                             noise: .iid(amp: amp), cadence: cad), truthSign: 0, tally: &t1)
                    results["flat-iid \(ci)"] = t1

                    var t2 = results["flat-ar1 \(ci)", default: Tally()]
                    Self.run(Self.trajectory(days: 40, seed: UInt64(seed) &+ 7000, base: { _ in 62 },
                                             noise: .ar1(phi: 0.6, amp: amp), cadence: cad), truthSign: 0, tally: &t2)
                    results["flat-ar1 \(ci)"] = t2
                }
            }
        }
        // 28-day hormonal cycle oscillation around a flat mean (net-flat truth)
        for amp in [0.4, 0.8] {
            for seed in 0..<60 {
                var t = results["cycle28", default: Tally()]
                Self.run(Self.trajectory(days: 40, seed: UInt64(seed) &+ 14000,
                                         base: { day in 62 + amp * sin(Double(day) / 28 * 2 * .pi) },
                                         noise: .iid(amp: 0.5), cadence: .daily), truthSign: 0, tally: &t)
                results["cycle28"] = t
            }
        }
        // Weekend pattern: +0.5 kg Sat/Sun bumps, flat mean
        for seed in 0..<60 {
            var t = results["weekend", default: Tally()]
            Self.run(Self.trajectory(days: 40, seed: UInt64(seed) &+ 21000,
                                     base: { day in 62 + (day % 7 >= 5 ? 0.5 : 0) },
                                     noise: .iid(amp: 0.5), cadence: .daily), truthSign: 0, tally: &t)
            results["weekend"] = t
        }

        var worstDramatic = 0.0
        for (k, t) in results.sorted(by: { $0.key < $1.key }) {
            print(String(format: "MC-FP %-16s runs=%3d reported=%5.1f%% dramatic=%5.1f%%",
                         (k as NSString).utf8String!, t.runs, t.pctReported, t.pctDramatic))
            worstDramatic = max(worstDramatic, t.pctDramatic)
        }
        // MEASURED 2026-07-08 (baseline, MK gate):
        //   flat-iid: 2.8–10.6% dramatic · flat-ar1 (persistent water
        //   episodes): 10.0–27.8% · weekend pattern: 16.7% · cycle28: 90.8%.
        // Two findings this harness surfaced on its first run:
        //   1. KNOWN GAP — 28-day cycle oscillation reads as a confident
        //      trend ~91% of the time (a 21d window sees a half-period as a
        //      clean monotonic run). Needs cycle-aware handling / the #1024
        //      Kalman treatment. Canary bound below: if you improve this,
        //      lower the bound and celebrate.
        //   2. WEAK SPOT — persistent multi-day water retention (AR1 φ=0.6)
        //      leaks ~25-28% dramatic phantoms. #1024 target.
        // Bounds = measured + headroom; regressions beyond them fail.
        let iidWorst = ["flat-iid daily", "flat-iid 60%", "flat-iid every3"].map { results[$0]?.pctDramatic ?? 0 }.max() ?? 0
        let ar1Worst = ["flat-ar1 daily", "flat-ar1 60%", "flat-ar1 every3"].map { results[$0]?.pctDramatic ?? 0 }.max() ?? 0
        #expect(iidWorst < 14, "iid-noise dramatic-phantom rate regressed: \(iidWorst)%")
        #expect(ar1Worst < 32, "AR1 water-episode dramatic-phantom rate regressed: \(ar1Worst)% (known weak spot, do not let it grow)")
        #expect((results["weekend"]?.pctDramatic ?? 0) < 22, "weekend-pattern phantom rate regressed")
        #expect((results["cycle28"]?.pctDramatic ?? 0) < 95, "cycle28 canary — currently ~91% (known gap, #1024); if you fixed it, LOWER this bound")
    }

    // MARK: - Detection + sign errors on real trends

    @Test func detection_trendFamilies() async throws {
        let weeklyRates = [0.15, 0.3, 0.5]  // kg/wk, both directions
        var bySpec: [String: Tally] = [:]

        for rate in weeklyRates {
            for dir in [1.0, -1.0] {
                let perDay = rate * dir / 7
                for (ni, noise) in [("iid0.8", Noise.iid(amp: 0.8)), ("ar1", .ar1(phi: 0.6, amp: 0.8))] {
                    for (ci, cad) in [("daily", Cadence.daily), ("60%", .adherence(0.6))] {
                        let key = "r\(rate) \(ni) \(ci)"
                        for seed in 0..<40 {
                            var t = bySpec[key, default: Tally()]
                            // 35 days of established trend — the "should definitely see it" case
                            Self.run(Self.trajectory(days: 35, seed: UInt64(seed) &+ 30000,
                                                     base: { day in 62 + perDay * Double(day) },
                                                     noise: noise, cadence: cad),
                                     truthSign: dir > 0 ? 1 : -1, tally: &t)
                            bySpec[key] = t
                        }
                    }
                }
            }
        }
        for (k, t) in bySpec.sorted(by: { $0.key < $1.key }) {
            print(String(format: "MC-DET %-20s runs=%3d detected=%5.1f%% signErr=%4.1f%%",
                         (k as NSString).utf8String!, t.runs, t.pctDetected, t.pctSignError))
        }
        // MEASURED 2026-07-08 (baseline): established 0.5 kg/wk trends detect
        // at 87–95% (daily) / 74–88% (60% adherence); 0.3 kg/wk at 50–68%;
        // 0.15 kg/wk is genuinely hard (22–36%, sign errors to 13.8% under
        // AR1 — a 0.15/wk signal under 0.8kg daily noise is near the physical
        // detectability floor). Bounds pin the medium/strong cases.
        func spec(_ k: String) -> Tally { bySpec[k] ?? Tally() }
        #expect(spec("r0.5 iid0.8 daily").pctDetected > 85, "strong-trend detection regressed")
        #expect(spec("r0.5 ar1 daily").pctDetected > 82, "strong-trend detection under water episodes regressed")
        #expect(spec("r0.3 iid0.8 daily").pctDetected > 58, "medium-trend detection regressed")
        for k in bySpec.keys where !k.hasPrefix("r0.15") {
            #expect(spec(k).pctSignError < 8, "sign-error rate regressed for \(k): \(spec(k).pctSignError)%")
        }
    }

    // MARK: - Contaminated: spikes + gaps on trend and flat

    @Test func robustness_contaminated() async throws {
        var flat = Tally(), trend = Tally()
        for seed in 0..<120 {
            // flat + spikes + a 9-day gap
            Self.run(Self.trajectory(days: 40, seed: UInt64(seed) &+ 50000, base: { _ in 62 },
                                     noise: .iid(amp: 0.6), cadence: .dailyWithGap(start: 22, len: 9),
                                     spikeProb: 0.06), truthSign: 0, tally: &flat)
            // real bulk + spikes + the same gap (the 2026-07-08 field shape)
            Self.run(Self.trajectory(days: 40, seed: UInt64(seed) &+ 60000,
                                     base: { day in 54 + 0.05 * Double(day) },
                                     noise: .iid(amp: 0.6), cadence: .dailyWithGap(start: 22, len: 9),
                                     spikeProb: 0.06), truthSign: 1, tally: &trend)
        }
        print(String(format: "MC-CONT flat+gap+spikes  runs=%3d reported=%5.1f%% dramatic=%5.1f%%", flat.runs, flat.pctReported, flat.pctDramatic))
        print(String(format: "MC-CONT bulk+gap+spikes  runs=%3d detected=%5.1f%% signErr=%4.1f%%", trend.runs, trend.pctDetected, trend.pctSignError))
        // MEASURED 2026-07-08: flat+gap+spikes 4.2% dramatic · bulk through
        // the same contamination 80.8% detected, 0.8% sign error (the
        // 2026-07-08 field shape, at population scale).
        #expect(flat.pctDramatic < 9, "contaminated-flat phantom rate regressed: \(flat.pctDramatic)%")
        #expect(trend.pctDetected > 72, "contaminated-bulk detection regressed: \(trend.pctDetected)%")
        #expect(trend.pctSignError < 4, "contaminated-bulk sign errors regressed")
    }
}
