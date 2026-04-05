import Foundation

/// Rule-based health insights — works without the AI model.
/// Used as fallback when model isn't downloaded, and to enrich AI responses.
@MainActor
enum AIRuleEngine {

    /// Generate a quick insight based on today's data.
    static func quickInsight() -> String? {
        let today = DateFormatters.todayString

        // Check food logged
        guard let nutrition = try? AppDatabase.shared.fetchDailyNutrition(for: today) else { return nil }

        if nutrition.calories == 0 {
            return "You haven't logged any food today. Tap \"Log breakfast\" to get started."
        }

        // Weight trend
        if let entries = try? AppDatabase.shared.fetchWeightEntries() {
            let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
            if let trend = WeightTrendCalculator.calculateTrend(entries: input) {
                let rate = trend.weeklyRateKg
                let deficit = trend.estimatedDailyDeficit

                if rate < -0.1 {
                    let lbsPerWeek = abs(rate) * 2.20462
                    return String(format: "You're losing about %.1f lbs/week. Today you've eaten %d calories so far.", lbsPerWeek, Int(nutrition.calories))
                } else if rate > 0.1 {
                    return "Your weight is trending up. You've eaten \(Int(nutrition.calories)) calories today."
                } else {
                    return "Weight is stable. You've eaten \(Int(nutrition.calories)) calories today with \(Int(nutrition.proteinG))g protein."
                }
            }
        }

        return "You've logged \(Int(nutrition.calories)) calories today with \(Int(nutrition.proteinG))g protein."
    }

    /// Suggest what to do next based on gaps in today's data.
    static func nextAction() -> String? {
        let today = DateFormatters.todayString
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: today)) ?? .zero

        let hour = Calendar.current.component(.hour, from: Date())

        if nutrition.calories == 0 {
            if hour < 11 { return "Log your breakfast to start tracking today." }
            if hour < 15 { return "Don't forget to log your meals — what did you have for lunch?" }
            return "It's getting late — try to log what you ate today."
        }

        if nutrition.proteinG < 50 && hour > 15 {
            return "Your protein is at \(Int(nutrition.proteinG))g — consider a high-protein dinner or snack."
        }

        // Check if workout logged today
        if let workouts = try? WorkoutService.fetchWorkouts(limit: 5) {
            let todayWorkouts = workouts.filter { $0.date == today }
            if todayWorkouts.isEmpty && hour > 10 {
                return "No workout logged today. Want to start one?"
            }
        }

        return nil
    }

    /// Yesterday's food log with target comparison.
    static func yesterdaySummary() -> String {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) else { return "Can't load yesterday." }
        let dateStr = DateFormatters.dateOnly.string(from: yesterday)
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: dateStr)) ?? .zero

        if nutrition.calories == 0 { return "No food was logged yesterday." }

        let tdee = TDEEEstimator.shared.current?.tdee ?? 2000
        let deficit = WeightGoal.load()?.requiredDailyDeficit ?? 0
        let target = max(500, Int(tdee - deficit))
        let vsTarget = Int(nutrition.calories) - target

        var lines = ["Yesterday: \(Int(nutrition.calories)) cal (\(vsTarget > 0 ? "+\(vsTarget) over" : "\(abs(vsTarget)) under") target) — \(Int(nutrition.proteinG))P \(Int(nutrition.carbsG))C \(Int(nutrition.fatG))F"]

        // Compact food list
        var foods: [String] = []
        if let logs = try? AppDatabase.shared.fetchMealLogs(for: dateStr) {
            for log in logs {
                guard let logId = log.id, let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: logId) else { continue }
                for entry in entries {
                    foods.append("\(entry.foodName) \(Int(entry.totalCalories))cal")
                }
            }
        }
        if !foods.isEmpty { lines.append(foods.joined(separator: ", ")) }
        return lines.joined(separator: "\n")
    }

    /// Generate a structured daily summary.
    static func dailySummary() -> String {
        var lines: [String] = ["Here's your day:"]
        let today = DateFormatters.todayString

        // Nutrition with target
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: today)) ?? .zero
        let tdee = TDEEEstimator.shared.current?.tdee ?? 2000
        let deficit = WeightGoal.load()?.requiredDailyDeficit ?? 0
        let target = max(500, Int(tdee - deficit))

        if nutrition.calories > 0 {
            let left = target - Int(nutrition.calories)
            lines.append("Food: \(Int(nutrition.calories))/\(target) cal (\(left > 0 ? "\(left) left" : "\(abs(left)) over")) — \(Int(nutrition.proteinG))P \(Int(nutrition.carbsG))C \(Int(nutrition.fatG))F")
        } else {
            lines.append("Food: nothing logged yet (target: \(target) cal)")
        }

        // Weight
        if let entries = try? AppDatabase.shared.fetchWeightEntries(),
           let latest = entries.last {
            let unit = Preferences.weightUnit
            lines.append("Weight: \(String(format: "%.1f", unit.convert(fromKg: latest.weightKg)))\(unit.displayName)")
        }

        // Workouts today
        if let workouts = try? WorkoutService.fetchWorkouts(limit: 10) {
            let todayWorkouts = workouts.filter { $0.date == today }
            if !todayWorkouts.isEmpty {
                lines.append("Workout: \(todayWorkouts.map(\.name).joined(separator: ", "))")
            }
        }

        // Supplements
        if let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
           !supplements.isEmpty,
           let logs = try? AppDatabase.shared.fetchSupplementLogs(for: today) {
            let taken = logs.filter(\.taken).count
            lines.append("Supplements: \(taken)/\(supplements.count)")
        }

        return lines.joined(separator: "\n")
    }

    /// Calories remaining vs target.
    static func caloriesLeft() -> String {
        let today = DateFormatters.todayString
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: today)) ?? .zero
        let tdee = TDEEEstimator.shared.current?.tdee ?? 2000
        let deficit = WeightGoal.load()?.requiredDailyDeficit ?? 0
        let target = tdee - deficit

        if nutrition.calories == 0 {
            return "No food logged yet. Your target is \(Int(target)) cal."
        }

        let remaining = target - nutrition.calories
        if remaining > 0 {
            // Add protein context if relevant
            if let goal = WeightGoal.load(), let targets = goal.macroTargets() {
                let pLeft = max(0, Int(targets.proteinG - nutrition.proteinG))
                if pLeft > 20 {
                    return "\(Int(remaining)) cal left (\(Int(nutrition.calories))/\(Int(target))). Still need \(pLeft)g protein."
                }
            }
            return "\(Int(remaining)) cal left (\(Int(nutrition.calories))/\(Int(target)))."
        } else {
            return "You've eaten \(Int(nutrition.calories)) of \(Int(target)) cal — \(Int(abs(remaining))) over target."
        }
    }

    /// Supplement check.
    static func supplementStatus() -> String {
        let today = DateFormatters.todayString
        guard let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
              !supplements.isEmpty else { return "No supplements set up." }
        let logs = (try? AppDatabase.shared.fetchSupplementLogs(for: today)) ?? []
        let takenIds = Set(logs.filter(\.taken).compactMap(\.supplementId))
        let taken = takenIds.count
        let total = supplements.count

        if taken == total { return "All \(total) supplements taken today." }
        let untaken = supplements.filter { !takenIds.contains($0.id ?? 0) }.map(\.name)
        return "Supplements: \(taken)/\(total) taken. Still need: \(untaken.joined(separator: ", "))."
    }
}
