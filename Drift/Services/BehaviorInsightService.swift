import Foundation

/// Computes behavior-outcome correlations from existing cross-domain data.
/// Each insight compares a behavior (workout frequency, protein intake, sleep)
/// against an outcome (weight trend, recovery score) using simple descriptive stats.
struct BehaviorInsight: Sendable, Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
    let isPositive: Bool
}

@MainActor
enum BehaviorInsightService {

    /// Compute all available insights from existing data. Returns 0-4 insights.
    static func computeInsights(sleepHistory: [(date: Date, hours: Double)] = [], recentAppleWorkouts: [Date] = []) -> [BehaviorInsight] {
        var insights: [BehaviorInsight] = []
        if let workout = workoutFrequencyInsight() { insights.append(workout) }
        if let protein = proteinAdherenceInsight() { insights.append(protein) }
        if let logging = loggingConsistencyInsight() { insights.append(logging) }
        if let sleep = sleepVsCaloriesInsight(sleepHistory: sleepHistory) { insights.append(sleep) }
        return insights
    }

    // MARK: - Proactive Alerts (actionable, shown prominently)

    /// Urgent, actionable alerts — things that need attention right now.
    /// Different from insights (which are correlations over time).
    static func computeProactiveAlerts(recentAppleWorkouts: [Date] = []) -> [BehaviorInsight] {
        var alerts: [BehaviorInsight] = []
        if let protein = proteinStreakAlert() { alerts.append(protein) }
        if let supplement = supplementGapAlert() { alerts.append(supplement) }
        if let workout = workoutConsistencyAlert(recentAppleWorkouts: recentAppleWorkouts) { alerts.append(workout) }
        if let logging = loggingGapAlert() { alerts.append(logging) }
        return alerts
    }

    /// Alert when protein target has been missed 3+ consecutive days.
    private static func proteinStreakAlert() -> BehaviorInsight? {
        guard let goal = WeightGoal.load(),
              let targets = goal.macroTargets(),
              targets.proteinG > 0 else { return nil }

        let db = AppDatabase.shared
        let calendar = Calendar.current
        var missedStreak = 0

        for dayOffset in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            guard let nutrition = try? db.fetchDailyNutrition(for: dateStr),
                  nutrition.calories > 200,
                  nutrition.proteinG > 0 else { break }  // no logging or no protein data = can't judge
            if nutrition.proteinG < targets.proteinG * 0.8 {
                missedStreak += 1
            } else {
                break
            }
        }

        guard missedStreak >= 3 else { return nil }

        return BehaviorInsight(
            icon: "exclamationmark.triangle.fill",
            title: "Protein below target",
            detail: "\(missedStreak) days in a row under \(Int(targets.proteinG))g protein. Try adding a protein shake or eggs.",
            isPositive: false)
    }

    /// Alert when a supplement hasn't been marked as taken recently.
    private static func supplementGapAlert() -> BehaviorInsight? {
        guard let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
              !supplements.isEmpty else { return nil }

        let calendar = Calendar.current
        var missedNames: [String] = []

        for supp in supplements {
            // Check previous 3 days (skip today — new supplements shouldn't false-alert)
            var takenRecently = false
            for dayOffset in 1...3 {
                guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
                let dateStr = DateFormatters.dateOnly.string(from: date)
                if let logs = try? AppDatabase.shared.fetchSupplementLogs(for: dateStr),
                   logs.contains(where: { $0.supplementId == supp.id }) {
                    takenRecently = true
                    break
                }
            }
            if !takenRecently { missedNames.append(supp.name) }
        }

        guard !missedNames.isEmpty else { return nil }

        let names = missedNames.prefix(3).joined(separator: ", ")
        let extra = missedNames.count > 3 ? " + \(missedNames.count - 3) more" : ""
        return BehaviorInsight(
            icon: "pill.fill",
            title: "Supplements missed",
            detail: "\(names)\(extra) — not taken in 3+ days.",
            isPositive: false)
    }

    /// Alert when no workouts logged in 5+ days and no Apple Health workouts in that window.
    private static func workoutConsistencyAlert(recentAppleWorkouts: [Date] = []) -> BehaviorInsight? {
        let calendar = Calendar.current
        guard let fiveDaysAgo = calendar.date(byAdding: .day, value: -5, to: Date()) else { return nil }

        // Apple Health workout in the window → no alert
        if recentAppleWorkouts.contains(where: { $0 >= fiveDaysAgo }) { return nil }

        // Drift-logged workouts
        guard let recentWorkouts = try? WorkoutService.fetchWorkouts(limit: 1),
              let latest = recentWorkouts.first else {
            return nil // no workout history at all — don't nag new users
        }

        let dateStr = DateFormatters.dateOnly.string(from: fiveDaysAgo)
        guard latest.date < dateStr else { return nil }

        let latestDate = DateFormatters.dateOnly.date(from: latest.date) ?? fiveDaysAgo
        let daysSince = calendar.dateComponents([.day], from: latestDate, to: Date()).day ?? 5

        return BehaviorInsight(
            icon: "figure.walk",
            title: "No workouts recently",
            detail: "\(daysSince) days since your last logged workout. Even a short session helps.",
            isPositive: false)
    }

    /// Alert when no food has been logged in 2+ days.
    private static func loggingGapAlert() -> BehaviorInsight? {
        let calendar = Calendar.current
        let today = Date()

        // Check yesterday and the day before — if both are empty, alert
        for dayOffset in 1...2 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { return nil }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            if let nutrition = try? AppDatabase.shared.fetchDailyNutrition(for: dateStr),
               nutrition.calories > 100 {
                return nil // found food logged recently
            }
        }

        // Also check today — if they logged today, no alert needed
        let todayStr = DateFormatters.todayString
        if let todayNutrition = try? AppDatabase.shared.fetchDailyNutrition(for: todayStr),
           todayNutrition.calories > 100 {
            return nil
        }

        return BehaviorInsight(
            icon: "pencil.slash",
            title: "Food logging paused",
            detail: "No food logged in 2+ days. Consistent logging helps your calorie targets adapt.",
            isPositive: false)
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

        for dayOffset in 1...30 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            guard let nutrition = try? db.fetchDailyNutrition(for: dateStr),
                  nutrition.calories > 200 else { continue }  // skip days with minimal logging

            totalDays += 1
            if nutrition.proteinG >= targets.proteinG * 0.8 {  // matches alert threshold (80%)
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

    // MARK: - Insight 4: Sleep Duration vs Next-Day Calories

    /// Compares calorie intake on days after good sleep (7+ hours) vs poor sleep (<6 hours).
    /// Requires: 7+ days of sleep data paired with food data.
    private static func sleepVsCaloriesInsight(sleepHistory: [(date: Date, hours: Double)]) -> BehaviorInsight? {
        guard sleepHistory.count >= 7 else { return nil }

        let db = AppDatabase.shared
        let calendar = Calendar.current
        var goodSleepCals: [Double] = []
        var poorSleepCals: [Double] = []

        for entry in sleepHistory {
            // Sleep data is for the night ending on this date; look at food logged THIS day
            let dateStr = DateFormatters.dateOnly.string(from: entry.date)
            guard let nutrition = try? db.fetchDailyNutrition(for: dateStr),
                  nutrition.calories > 200 else { continue }  // skip days with minimal logging

            if entry.hours >= 7 {
                goodSleepCals.append(nutrition.calories)
            } else if entry.hours > 0 && entry.hours < 6 {
                poorSleepCals.append(nutrition.calories)
            }
        }

        guard goodSleepCals.count >= 3, poorSleepCals.count >= 2 else { return nil }

        let goodAvg = goodSleepCals.reduce(0, +) / Double(goodSleepCals.count)
        let poorAvg = poorSleepCals.reduce(0, +) / Double(poorSleepCals.count)
        let diff = poorAvg - goodAvg  // positive = eat more on poor sleep days

        guard abs(diff) > 50 else { return nil }  // negligible difference

        if diff > 100 {
            return BehaviorInsight(
                icon: "moon.zzz.fill",
                title: "Sleep affects eating",
                detail: "After poor sleep (<6h), you eat ~\(Int(diff)) more cal than after good sleep (7h+).",
                isPositive: false)
        } else if diff < -50 {
            return BehaviorInsight(
                icon: "moon.zzz.fill",
                title: "Sleep and food balanced",
                detail: "Your calorie intake stays consistent regardless of sleep quality. Nice discipline.",
                isPositive: true)
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
