import Foundation

/// Computes behavior-outcome correlations from existing cross-domain data.
/// Each insight compares a behavior (workout frequency, protein intake, sleep)
/// against an outcome (weight trend, recovery score) using simple descriptive stats.
struct BehaviorInsight: Sendable {
    let icon: String
    let title: String
    let detail: String
    let isPositive: Bool
}

@MainActor
enum BehaviorInsightService {

    /// Compute all available insights from existing data. Returns 0-3 insights.
    static func computeInsights() -> [BehaviorInsight] {
        var insights: [BehaviorInsight] = []
        if let workout = workoutFrequencyInsight() { insights.append(workout) }
        if let protein = proteinAdherenceInsight() { insights.append(protein) }
        if let logging = loggingConsistencyInsight() { insights.append(logging) }
        return insights
    }

    // MARK: - Insight 1: Workout Frequency vs Weight Trend

    /// Compares weeks with 3+ workouts to weeks with fewer.
    /// Requires: 4+ weeks of data with workouts + weight entries.
    private static func workoutFrequencyInsight() -> BehaviorInsight? {
        let db = AppDatabase.shared

        // Use existing weeklyWorkoutCounts (8 weeks)
        guard let weeklyCounts = try? WorkoutService.weeklyWorkoutCounts(weeks: 8) else { return nil }

        var activeWeeksWeightChange: [Double] = []
        var inactiveWeeksWeightChange: [Double] = []

        let calendar = Calendar.current
        for week in weeklyCounts {
            guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: week.weekStart) else { continue }
            let startStr = DateFormatters.dateOnly.string(from: week.weekStart)
            let endStr = DateFormatters.dateOnly.string(from: weekEnd)

            // Get weight change this week
            guard let weightEntries = try? db.fetchWeightEntries(from: startStr, to: endStr),
                  weightEntries.count >= 2 else { continue }
            let firstW = weightEntries.last!.weightKg  // entries are DESC sorted
            let lastW = weightEntries.first!.weightKg
            let change = lastW - firstW  // negative = lost weight

            if week.count >= 3 {
                activeWeeksWeightChange.append(change)
            } else {
                inactiveWeeksWeightChange.append(change)
            }
        }

        // Need at least 2 weeks in each bucket
        guard activeWeeksWeightChange.count >= 2, inactiveWeeksWeightChange.count >= 2 else { return nil }

        let activeAvg = activeWeeksWeightChange.reduce(0, +) / Double(activeWeeksWeightChange.count)
        let inactiveAvg = inactiveWeeksWeightChange.reduce(0, +) / Double(inactiveWeeksWeightChange.count)
        let diff = inactiveAvg - activeAvg  // positive = active weeks are better

        guard abs(diff) > 0.05 else { return nil }  // negligible difference

        let unit = Preferences.weightUnit
        let diffDisplay = abs(unit.convert(fromKg: diff))

        if diff > 0 {
            return BehaviorInsight(
                icon: "figure.run",
                title: "Workouts help",
                detail: "Weeks with 3+ workouts: \(String(format: "%.1f", diffDisplay)) \(unit.displayName) better trend than lighter weeks.",
                isPositive: true)
        } else {
            return BehaviorInsight(
                icon: "figure.run",
                title: "Activity gap",
                detail: "Your weight trend is similar regardless of workout frequency. Focus on nutrition consistency.",
                isPositive: false)
        }
    }

    // MARK: - Insight 2: Protein Adherence vs Weight Trend

    /// Checks if hitting protein target correlates with better weight outcomes.
    /// Requires: active goal with protein target + 2 weeks of food logs.
    private static func proteinAdherenceInsight() -> BehaviorInsight? {
        guard let goal = WeightGoal.load(),
              let targets = goal.macroTargets() else { return nil }

        let db = AppDatabase.shared
        let calendar = Calendar.current
        let today = Date()

        var hitDays = 0
        var missedDays = 0
        var totalDays = 0

        for dayOffset in 1...14 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            guard let nutrition = try? db.fetchDailyNutrition(for: dateStr),
                  nutrition.calories > 200 else { continue }  // skip days with minimal logging

            totalDays += 1
            if nutrition.proteinG >= targets.proteinG * 0.9 {  // within 10% of target
                hitDays += 1
            } else {
                missedDays += 1
            }
        }

        guard totalDays >= 7 else { return nil }  // need at least a week of data

        let hitRate = Double(hitDays) / Double(totalDays)

        if hitRate >= 0.7 {
            return BehaviorInsight(
                icon: "fork.knife",
                title: "Protein on track",
                detail: "You hit your protein target \(Int(hitRate * 100))% of the last \(totalDays) days. Great for muscle preservation.",
                isPositive: true)
        } else if hitRate < 0.4 {
            return BehaviorInsight(
                icon: "fork.knife",
                title: "Protein gap",
                detail: "Only \(Int(hitRate * 100))% protein adherence over \(totalDays) days. Aim for \(Int(targets.proteinG))g daily.",
                isPositive: false)
        }
        return nil  // middle ground — no strong signal
    }

    // MARK: - Insight 3: Logging Consistency

    /// Shows how consistent food logging has been and its correlation with weight data quality.
    private static func loggingConsistencyInsight() -> BehaviorInsight? {
        let consistency = TDEEEstimator.shared.foodLoggingConsistency()
        guard consistency > 0 else { return nil }

        let streak = consecutiveLoggingDays()

        if consistency >= 0.8 {
            let detail = streak >= 7
                ? "\(streak)-day logging streak. Your adaptive TDEE is getting more accurate."
                : "\(Int(consistency * 100))% logging rate over 14 days. Great data quality."
            return BehaviorInsight(
                icon: "chart.bar.fill",
                title: "Consistent logging",
                detail: detail,
                isPositive: true)
        } else if consistency < 0.4 {
            return BehaviorInsight(
                icon: "chart.bar.fill",
                title: "Log more to unlock insights",
                detail: "Only \(Int(consistency * 100))% of days logged. TDEE adapts faster with consistent data.",
                isPositive: false)
        }
        return nil
    }

    /// Count consecutive days with food logged ending at yesterday.
    private static func consecutiveLoggingDays() -> Int {
        let db = AppDatabase.shared
        let calendar = Calendar.current
        var streak = 0
        for dayOffset in 1...30 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            guard let nutrition = try? db.fetchDailyNutrition(for: dateStr),
                  nutrition.calories > 100 else { break }
            streak += 1
        }
        return streak
    }
}
