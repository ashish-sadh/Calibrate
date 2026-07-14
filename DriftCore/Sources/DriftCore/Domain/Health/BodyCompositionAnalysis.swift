import Foundation

/// Scan-over-scan body-composition breakdown + energy-balance reconciliation.
/// Pure and cross-platform so it's testable without a device (2026-07-14).
///
/// The DEXA tab used to show only raw deltas and arrows — fat-mass change and
/// lean-mass change side by side, with no synthesis. This engine answers the
/// question the operator actually asked ("figure out what's going right or
/// wrong"): of the weight you changed, how much was fat vs lean, is it
/// recomposition, and does the tissue change agree with the calorie-balance
/// estimate the weight-trend engine produced?
public enum BodyCompositionAnalysis {

    /// Energy density of body fat — the standard 7700 kcal/kg (3500 kcal/lb).
    /// Lean tissue is far less energy-dense (~1800 kcal/kg, mostly water) so we
    /// attribute the deficit to fat change for the reconciliation.
    static let kcalPerKgFat = 7700.0

    public enum Verdict: String, Sendable, Equatable {
        case fatLoss          // fat down, lean held or up — the goal for most
        case recomposition    // fat down AND lean up — best case
        case leanLoss         // lean down materially — a warning
        case fatGain          // fat up
        case muscleGain       // lean up, fat held or up modestly
        case stable
    }

    public struct ScanDelta: Sendable, Equatable {
        public let days: Int
        public let totalChangeKg: Double
        public let fatChangeKg: Double
        public let leanChangeKg: Double
        public let boneChangeKg: Double?
        public let bodyFatPctChange: Double?
        /// Of the absolute mass change, the fraction attributable to fat (0–1).
        /// nil when total change is ~0 (recomp with no net weight move).
        public let fatFractionOfChange: Double?
        public let verdict: Verdict
        public let narrative: String
    }

    /// Compare two scans. `previous` is the earlier scan. Returns nil if the
    /// core mass fields are missing on either scan.
    public static func scanDelta(previous: DEXAScan, current: DEXAScan) -> ScanDelta? {
        guard let pFat = previous.fatMassKg, let cFat = current.fatMassKg,
              let pLean = previous.leanMassKg, let cLean = current.leanMassKg else { return nil }

        let days = dayGap(previous.scanDate, current.scanDate)
        let fatChange = cFat - pFat
        let leanChange = cLean - pLean
        let totalChange = (current.totalMassKg ?? (cFat + cLean)) - (previous.totalMassKg ?? (pFat + pLean))
        let boneChange: Double? = (previous.boneMassKg != nil && current.boneMassKg != nil)
            ? current.boneMassKg! - previous.boneMassKg! : nil
        let bfChange: Double? = (previous.bodyFatPct != nil && current.bodyFatPct != nil)
            ? current.bodyFatPct! - previous.bodyFatPct! : nil

        let absTotal = abs(fatChange) + abs(leanChange)
        let fatFraction: Double? = absTotal > 0.05 ? abs(fatChange) / absTotal : nil

        let verdict = classify(fatChange: fatChange, leanChange: leanChange)
        let narrative = narrate(verdict: verdict, fatChange: fatChange, leanChange: leanChange,
                                totalChange: totalChange, days: days, bfChange: bfChange)

        return ScanDelta(
            days: days, totalChangeKg: totalChange, fatChangeKg: fatChange, leanChangeKg: leanChange,
            boneChangeKg: boneChange, bodyFatPctChange: bfChange, fatFractionOfChange: fatFraction,
            verdict: verdict, narrative: narrative)
    }

    /// Threshold below which a tissue change is treated as noise (DEXA precision
    /// is ~0.5–1 kg for regional, better for whole-body; 0.3 kg is conservative).
    static let noiseKg = 0.3

    /// When both fat and lean fall (a normal cut), lean loss above this
    /// fraction of the total tissue lost is the "you're burning muscle" warning.
    /// ~25% lean is expected in an unassisted deficit; above 40% is a red flag.
    static let leanLossWarnFraction = 0.40

    static func classify(fatChange: Double, leanChange: Double) -> Verdict {
        let fatDown = fatChange < -noiseKg
        let fatUp = fatChange > noiseKg
        let leanDown = leanChange < -noiseKg
        let leanUp = leanChange > noiseKg

        if fatDown && leanUp { return .recomposition }
        if fatDown && leanDown {
            // Both down — judge by how much of the loss was muscle.
            let leanFraction = abs(leanChange) / (abs(fatChange) + abs(leanChange))
            return leanFraction > leanLossWarnFraction ? .leanLoss : .fatLoss
        }
        if fatDown { return .fatLoss }                 // fat down, lean held
        if leanUp { return .muscleGain }               // lean up, fat flat/up
        if leanDown && !fatUp { return .leanLoss }     // lean down, fat flat
        if fatUp { return .fatGain }
        return .stable
    }

    static func narrate(verdict: Verdict, fatChange: Double, leanChange: Double,
                        totalChange: Double, days: Int, bfChange: Double?) -> String {
        let fat = kgLbs(fatChange), lean = kgLbs(leanChange), total = kgLbs(totalChange)
        let window = days > 0 ? " over \(days) days" : ""
        let bf = bfChange.map { String(format: " Body fat %@ %.1f pts.", $0 >= 0 ? "+" : "−", abs($0)) } ?? ""

        switch verdict {
        case .recomposition:
            return "Recomposition\(window): you lost \(fat) of fat AND gained \(lean) of lean mass — the ideal outcome.\(bf)"
        case .fatLoss:
            // Of the weight moved, how much was fat.
            let frac = abs(totalChange) > 0.05 ? Int((abs(fatChange) / (abs(fatChange) + abs(leanChange))) * 100) : 100
            return "Fat loss\(window): \(total) total, and \(frac)% of it was fat (\(fat)). Lean mass held.\(bf)"
        case .muscleGain:
            return "Muscle gain\(window): +\(lean) of lean mass with fat held steady.\(bf)"
        case .leanLoss:
            return "Lean loss\(window): you lost \(lean) of lean mass. If you're cutting, add protein and resistance training to protect muscle.\(bf)"
        case .fatGain:
            let frac = abs(totalChange) > 0.05 ? Int((abs(fatChange) / (abs(fatChange) + abs(leanChange))) * 100) : 100
            return "Fat gain\(window): +\(fat) of fat (\(frac)% of the \(total) change).\(bf)"
        case .stable:
            return "Body composition held steady\(window) — no meaningful fat or lean change.\(bf)"
        }
    }

    // MARK: - Energy-balance reconciliation

    public struct Reconciliation: Sendable, Equatable {
        /// Daily kcal balance implied by the DEXA FAT change (negative = deficit).
        public let dexaImpliedDailyKcal: Double
        /// The weight-trend engine's estimate we're comparing against.
        public let estimatedDailyKcal: Double
        public let agrees: Bool
        public let narrative: String
    }

    /// Reconcile the fat-mass change between two scans against the weight-trend
    /// engine's daily energy-balance estimate. If the estimate says −400 kcal/day
    /// and the DEXA fat loss over the same window implies −380 kcal/day, they
    /// agree and the user can trust both. A large mismatch is itself the signal
    /// ("the scale trend says deficit but fat isn't moving — likely water or a
    /// logging gap"). `estimatedDailyKcal` is negative for a deficit.
    /// `trendWindowDays` is the span the scale estimate covers (the trend
    /// engine's `rateWindowDays`). When the inter-scan gap greatly exceeds it
    /// (a 3-month DEXA gap vs a 3-week scale slope), the two numbers describe
    /// different periods, so the language is softened — they can look like they
    /// "agree" by coincidence.
    public static func reconcile(delta: ScanDelta, estimatedDailyKcal: Double, trendWindowDays: Int = 0) -> Reconciliation? {
        guard delta.days > 0 else { return nil }
        let dexaDailyKcal = (delta.fatChangeKg * kcalPerKgFat) / Double(delta.days)
        let sameSign = (dexaDailyKcal <= 0) == (estimatedDailyKcal <= 0)
        let diff = abs(dexaDailyKcal - estimatedDailyKcal)
        let tol = max(250, 0.40 * max(abs(dexaDailyKcal), abs(estimatedDailyKcal)))
        let agrees = sameSign && diff <= tol
        // Windows are comparable only when the scan gap is within ~2× the scale
        // window; beyond that the "agree" claim is not trustworthy.
        let windowsComparable = trendWindowDays <= 0 || delta.days <= trendWindowDays * 2

        let dexaStr = String(format: "%+.0f", dexaDailyKcal)
        let estStr = String(format: "%+.0f", estimatedDailyKcal)
        let narrative: String
        if agrees && windowsComparable {
            narrative = "Your scan and your scale trend agree: DEXA fat change implies \(dexaStr) kcal/day, your weight trend estimates \(estStr) kcal/day. You can trust the number."
        } else if agrees {
            narrative = "Both point the same way — DEXA fat change implies \(dexaStr) kcal/day (over \(delta.days) days), your recent scale trend \(estStr) kcal/day. They cover different spans, so treat this as directional, not exact."
        } else if !sameSign {
            narrative = "Mismatch: your scale trend suggests \(estStr) kcal/day, but your DEXA fat change points the other way (\(dexaStr) kcal/day). Recent scale moves are likely water — trust the scan for body-fat direction."
        } else {
            narrative = "Partial agreement: DEXA implies \(dexaStr) kcal/day vs \(estStr) kcal/day from your scale trend. Same direction, different magnitude — the truth is likely between them."
        }
        return Reconciliation(dexaImpliedDailyKcal: dexaDailyKcal, estimatedDailyKcal: estimatedDailyKcal,
                              agrees: agrees && windowsComparable, narrative: narrative)
    }

    // MARK: - Helpers

    static func dayGap(_ a: String, _ b: String) -> Int {
        guard let da = DateFormatters.dateOnly.date(from: String(a.prefix(10))),
              let db = DateFormatters.dateOnly.date(from: String(b.prefix(10))) else { return 0 }
        return max(0, Int((db.timeIntervalSince(da) / 86_400).rounded()))
    }

    static func kgLbs(_ kg: Double) -> String {
        String(format: "%.1f lbs", abs(kg) * 2.20462)
    }
}
