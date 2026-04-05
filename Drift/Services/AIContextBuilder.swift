import Foundation

/// Builds a concise health context string for AI prompts from local data.
enum AIContextBuilder {
    /// Build context from today's data + recent trends.
    static func buildContext() -> String {
        var lines: [String] = []

        // Today's nutrition
        let today = DateFormatters.todayString
        if let nutrition = try? AppDatabase.shared.fetchDailyNutrition(for: today), nutrition.calories > 0 {
            lines.append("Today's food: \(Int(nutrition.calories))cal, \(Int(nutrition.proteinG))g protein, \(Int(nutrition.carbsG))g carbs, \(Int(nutrition.fatG))g fat, \(Int(nutrition.fiberG))g fiber")
        } else {
            lines.append("No food logged today yet.")
        }

        // Weight trend
        if let entries = try? AppDatabase.shared.fetchWeightEntries() {
            let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
            if let trend = WeightTrendCalculator.calculateTrend(entries: input) {
                let unit = Preferences.weightUnit
                lines.append("Current weight: \(String(format: "%.1f", unit.convert(fromKg: trend.currentEMA))) \(unit.displayName)")
                lines.append("Weekly change: \(String(format: "%+.2f", unit.convert(fromKg: trend.weeklyRateKg))) \(unit.displayName)/wk")
                if trend.estimatedDailyDeficit != 0 {
                    lines.append("Estimated daily \(trend.estimatedDailyDeficit < 0 ? "deficit" : "surplus"): \(Int(abs(trend.estimatedDailyDeficit))) kcal")
                }
            }
        }

        // Goal
        if let goal = WeightGoal.load() {
            let unit = Preferences.weightUnit
            lines.append("Goal: \(String(format: "%.1f", unit.convert(fromKg: goal.targetWeightKg))) \(unit.displayName) in \(goal.monthsToAchieve) months")
        }

        // Recent workouts (last 3)
        if let workouts = try? WorkoutService.fetchWorkouts(limit: 3), !workouts.isEmpty {
            let names = workouts.map { "\($0.name) (\($0.date))" }
            lines.append("Recent workouts: \(names.joined(separator: ", "))")
        }

        // Supplements
        if let supplements = try? AppDatabase.shared.fetchActiveSupplements(), !supplements.isEmpty {
            let names = supplements.map(\.name)
            lines.append("Supplements: \(names.joined(separator: ", "))")
        }

        // 7-day calorie average
        let cal = Calendar.current
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) {
            let fromStr = DateFormatters.dateOnly.string(from: weekAgo)
            let toStr = DateFormatters.todayString
            if let avg = try? AppDatabase.shared.averageDailyCalories(from: fromStr, to: toStr), avg > 0 {
                lines.append("7-day avg intake: \(Int(avg)) kcal/day")
            }
        }

        return lines.joined(separator: "\n")
    }
}
