import Foundation

/// Estimates recovery, sleep quality, and activity load from Apple Health data.
///
/// Recovery Score (0-100): HRV (40%) + RHR (30%) + Sleep (30%), relative to personal baselines.
/// Sleep Score (0-100): Duration vs dynamic need (60%) + stage quality (40%).
/// Activity Load: Light / Moderate / Heavy classification from calories + steps.
enum RecoveryEstimator {

    // MARK: - Data Models

    struct DailyRecovery: Sendable {
        let date: Date
        let recoveryScore: Int          // 0-100
        let sleepScore: Int             // 0-100
        let activityLoad: ActivityLoad
        let activityRaw: Double         // 0-21 internal scale
        let activeCalories: Double
        let steps: Double

        let sleepHours: Double
        let sleepNeeded: Double
        let sleepDebt: Double           // exponentially-decayed, capped -3 to +3
        let hrvMs: Double
        let restingHR: Double
        let respiratoryRate: Double

        let sleepDetail: HealthKitService.SleepDetail?
        let baselines: Baselines?
    }

    struct Baselines: Sendable {
        let hrvMs: Double
        let restingHR: Double
        let respiratoryRate: Double
        let sleepHours: Double
        let daysOfData: Int
        var isEstablished: Bool { daysOfData >= 5 }
    }

    enum ActivityLoad: String, Sendable {
        case rest = "Rest"
        case light = "Light"
        case moderate = "Moderate"
        case heavy = "Heavy"
        case extreme = "Extreme"
    }

    // MARK: - Baselines

    static func calculateBaselines(
        hrvHistory: [(date: Date, ms: Double)],
        rhrHistory: [(date: Date, bpm: Double)],
        respHistory: [(date: Date, rpm: Double)],
        sleepHistory: [(date: Date, hours: Double)]
    ) -> Baselines {
        let hrvAvg = hrvHistory.isEmpty ? 45 : hrvHistory.map(\.ms).reduce(0, +) / Double(hrvHistory.count)
        let rhrAvg = rhrHistory.isEmpty ? 65 : rhrHistory.map(\.bpm).reduce(0, +) / Double(rhrHistory.count)
        let respAvg = respHistory.isEmpty ? 15 : respHistory.map(\.rpm).reduce(0, +) / Double(respHistory.count)
        let sleepAvg = sleepHistory.isEmpty ? 7.5 : sleepHistory.map(\.hours).reduce(0, +) / Double(sleepHistory.count)
        let dataPoints = max(hrvHistory.count, max(rhrHistory.count, sleepHistory.count))
        return Baselines(hrvMs: hrvAvg, restingHR: rhrAvg, respiratoryRate: respAvg, sleepHours: sleepAvg, daysOfData: dataPoints)
    }

    // MARK: - Recovery Score (0-100)

    static func calculateRecovery(
        hrvMs: Double,
        restingHR: Double,
        sleepHours: Double,
        baselines: Baselines? = nil
    ) -> Int {
        let hrvBaseline = baselines?.hrvMs ?? 45.0
        let rhrBaseline = baselines?.restingHR ?? 65.0
        let sleepBaseline = baselines?.sleepHours ?? 7.5

        // HRV component (40%): higher = better
        let hrvRatio = hrvMs > 0 ? min(2.0, hrvMs / hrvBaseline) : 0.5
        let hrvScore = min(100, Int(hrvRatio * 50))

        // RHR component (30%): lower = better
        let rhrRatio = restingHR > 0 ? rhrBaseline / restingHR : 0.8
        let rhrScore = min(100, Int(rhrRatio * 50))

        // Sleep component (30%): closer to baseline = better
        let sleepRatio = sleepHours > 0 ? min(1.2, sleepHours / sleepBaseline) : 0
        let sleepScore = min(100, Int(sleepRatio * 83))

        let total = Int(Double(hrvScore) * 0.4 + Double(rhrScore) * 0.3 + Double(sleepScore) * 0.3)
        return max(0, min(100, total))
    }

    // MARK: - Sleep Score (0-100)

    static func calculateSleepScore(
        totalHours: Double,
        remHours: Double,
        deepHours: Double,
        targetHours: Double
    ) -> Int {
        // Duration vs dynamic need (60%)
        let durationScore = min(100, Int(totalHours / max(1, targetHours) * 100))

        // Quality: REM + deep proportions (40%)
        let remPct = totalHours > 0 ? remHours / totalHours : 0
        let deepPct = totalHours > 0 ? deepHours / totalHours : 0
        let remScore = min(100, Int(remPct / 0.22 * 100))   // ideal ~22% REM
        let deepScore = min(100, Int(deepPct / 0.17 * 100)) // ideal ~17% deep
        let qualityScore = (remScore + deepScore) / 2

        return max(0, min(100, Int(Double(durationScore) * 0.6 + Double(qualityScore) * 0.4)))
    }

    // MARK: - Activity Load

    static func calculateActivityLoad(activeCalories: Double, steps: Double) -> (load: ActivityLoad, raw: Double) {
        let calStrain = min(15.0, activeCalories / 70.0)
        let stepStrain = min(6.0, steps / 2500.0)
        let raw = min(21.0, max(0, calStrain * 0.7 + stepStrain * 0.3))

        let load: ActivityLoad
        switch raw {
        case ..<3: load = .rest
        case ..<7: load = .light
        case ..<14: load = .moderate
        case ..<18: load = .heavy
        default: load = .extreme
        }
        return (load, raw)
    }

    // MARK: - Dynamic Sleep Need

    /// Sleep need = 7.5h base + strain adjustment + debt adjustment.
    /// Capped at 9h — nobody realistically needs more than that.
    static func dynamicSleepNeed(
        previousDayLoad: Double,
        rollingDebtHours: Double
    ) -> Double {
        let base = 7.5
        let strainExtra = min(0.5, max(0, (previousDayLoad - 10) * 0.05))
        // Debt adjustment: gentle — max 0.5h extra even with significant debt
        let debtExtra = rollingDebtHours < -1 ? min(0.5, abs(rollingDebtHours) * 0.15) : 0
        return min(9.0, base + strainExtra + debtExtra)
    }

    /// Exponentially-decayed sleep debt over 7 days. Recent nights matter more.
    /// Capped at -3h to +3h — you can't accumulate infinite debt.
    /// Sleeping more gradually pays it off (decay factor 0.7 per day).
    static func sleepDebt(recentSleep: [(date: Date, hours: Double)], need: Double) -> Double {
        let last7 = Array(recentSleep.suffix(7))
        guard !last7.isEmpty else { return 0 }

        // Most recent day has weight 1.0, each older day decays by 0.7
        var debt = 0.0
        let count = last7.count
        for i in 0..<count {
            let daysAgo = count - 1 - i // 0 = oldest, count-1 = most recent
            let weight = pow(0.7, Double(daysAgo))
            let dailyDiff = last7[i].hours - need
            debt += dailyDiff * weight
        }

        // Normalize by sum of weights so the scale stays in hours
        let totalWeight = (0..<count).map { pow(0.7, Double(count - 1 - $0)) }.reduce(0, +)
        let normalized = totalWeight > 0 ? debt / totalWeight * Double(count) : 0

        // Cap: you can't accumulate more than 3h of debt or surplus
        return max(-3, min(3, normalized))
    }

    // MARK: - Deviation Helpers

    static func deviation(current: Double, baseline: Double, higherIsBetter: Bool) -> (arrow: String, pct: Int, favorable: Bool) {
        guard baseline > 0 else { return ("—", 0, true) }
        let pct = Int(((current - baseline) / baseline) * 100)
        let arrow = pct > 3 ? "↑" : pct < -3 ? "↓" : "—"
        let favorable: Bool
        if higherIsBetter {
            favorable = pct >= -3
        } else {
            favorable = pct <= 3
        }
        return (arrow, abs(pct), favorable)
    }

    // MARK: - Insights

    static func generateInsights(
        recovery: DailyRecovery,
        hrvHistory: [(date: Date, ms: Double)],
        sleepHistory: [(date: Date, hours: Double)]
    ) -> [String] {
        var insights: [String] = []

        // HRV trend: check all sequential pairs are rising
        if hrvHistory.count >= 3 {
            let last3 = hrvHistory.suffix(3).map(\.ms)
            let trendingUp = last3[0] < last3[1] && last3[1] < last3[2]
            if trendingUp {
                insights.append("HRV has been trending up — consistent with good recovery.")
            }
        }

        // Sleep debt
        if let baselines = recovery.baselines {
            let debt = sleepDebt(recentSleep: sleepHistory, need: baselines.sleepHours)
            if debt < -3 {
                insights.append("You're \(String(format: "%.1f", abs(debt)))h short on sleep this week. Consider an early night.")
            }
        }

        // Recovery context
        if recovery.recoveryScore >= 80 {
            insights.append("Strong recovery — good day for high-intensity training.")
        } else if recovery.recoveryScore < 40 {
            insights.append("Low recovery — consider lighter activity or rest today.")
        }

        return Array(insights.prefix(2))
    }

}
