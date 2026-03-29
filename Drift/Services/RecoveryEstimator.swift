import Foundation

/// Estimates WHOOP-like recovery and strain scores from Apple Health data.
///
/// Recovery Score (0-100%):
///   Based on: HRV (40%), resting HR (30%), sleep (30%)
///   Higher HRV = better recovery
///   Lower RHR = better recovery
///   More sleep = better recovery
///
/// Sleep Score (0-100%):
///   Based on: total hours vs needed, REM %, deep sleep %
///
/// Strain Score (0-21 scale like WHOOP):
///   Based on: active calories burned, steps, exercise intensity
enum RecoveryEstimator {

    struct DailyRecovery: Sendable {
        let date: Date
        let recoveryScore: Int      // 0-100%
        let recoveryLevel: Level
        let sleepScore: Int          // 0-100%
        let strainScore: Double      // 0-21

        let sleepHours: Double
        let sleepNeeded: Double      // estimated
        let hrvMs: Double
        let restingHR: Double
        let respiratoryRate: Double

        let sleepDetail: HealthKitService.SleepDetail?

        enum Level: String, Sendable {
            case green = "Good"
            case yellow = "Moderate"
            case red = "Poor"

            var color: String {
                switch self {
                case .green: "deficit"   // reusing theme colors
                case .yellow: "fatYellow"
                case .red: "surplus"
                }
            }
        }
    }

    // MARK: - Recovery Score

    /// Estimate recovery from HRV, RHR, and sleep.
    /// Uses personal baselines (rolling 30-day averages) when available.
    static func calculateRecovery(
        hrvMs: Double,
        restingHR: Double,
        sleepHours: Double,
        avgHRV: Double? = nil,      // 30-day avg for personalization
        avgRHR: Double? = nil,
        avgSleep: Double? = nil
    ) -> (score: Int, level: DailyRecovery.Level) {
        // HRV component (40% weight)
        // Population average: 20-80ms. Higher = better.
        let hrvBaseline = avgHRV ?? 45.0
        let hrvRatio = hrvMs > 0 ? min(2.0, hrvMs / hrvBaseline) : 0.5
        let hrvScore = min(100, Int(hrvRatio * 50))

        // RHR component (30% weight)
        // Population average: 60-80 bpm. Lower = better.
        let rhrBaseline = avgRHR ?? 65.0
        let rhrRatio = restingHR > 0 ? rhrBaseline / restingHR : 0.8
        let rhrScore = min(100, Int(rhrRatio * 50))

        // Sleep component (30% weight)
        let sleepTarget = avgSleep ?? 7.5
        let sleepRatio = sleepHours > 0 ? min(1.2, sleepHours / sleepTarget) : 0
        let sleepScore = min(100, Int(sleepRatio * 83))

        let total = Int(Double(hrvScore) * 0.4 + Double(rhrScore) * 0.3 + Double(sleepScore) * 0.3)
        let clamped = max(0, min(100, total))

        let level: DailyRecovery.Level
        if clamped >= 67 { level = .green }
        else if clamped >= 34 { level = .yellow }
        else { level = .red }

        return (clamped, level)
    }

    // MARK: - Sleep Score

    static func calculateSleepScore(
        totalHours: Double,
        remHours: Double,
        deepHours: Double,
        targetHours: Double = 7.5
    ) -> Int {
        // Duration component (60%)
        let durationScore = min(100, Int(totalHours / targetHours * 100))

        // Quality component (40%) - based on REM + deep proportions
        let remPct = totalHours > 0 ? remHours / totalHours : 0
        let deepPct = totalHours > 0 ? deepHours / totalHours : 0
        // Ideal: ~20-25% REM, ~15-20% deep
        let remScore = min(100, Int(remPct / 0.22 * 100))
        let deepScore = min(100, Int(deepPct / 0.17 * 100))
        let qualityScore = (remScore + deepScore) / 2

        return max(0, min(100, Int(Double(durationScore) * 0.6 + Double(qualityScore) * 0.4)))
    }

    // MARK: - Strain Score (0-21)

    static func calculateStrain(activeCalories: Double, steps: Double) -> Double {
        // WHOOP strain is 0-21 based on cardiovascular load
        // We approximate from active calories + steps
        // Light day: ~200 active cal, ~5000 steps → strain ~5
        // Moderate: ~400 cal, ~8000 steps → strain ~10
        // Hard: ~700+ cal, ~12000+ steps → strain ~15
        // Extreme: ~1000+ cal → strain ~18-21

        let calStrain = min(15.0, activeCalories / 70.0) // ~70 cal per strain point
        let stepStrain = min(6.0, steps / 2500.0)        // ~2500 steps per strain point
        return min(21.0, max(0, calStrain * 0.7 + stepStrain * 0.3))
    }

    // MARK: - Sleep Need Estimate

    /// Estimate sleep needed based on strain and personal baseline.
    static func estimatedSleepNeed(strain: Double, baselineSleep: Double = 7.5) -> Double {
        // Higher strain = more sleep needed
        // Base: 7.5h + 0.1h per strain point above 10
        let extra = max(0, (strain - 10) * 0.1)
        return baselineSleep + extra
    }
}
