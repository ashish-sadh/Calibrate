import Foundation

/// Builds rich, context-specific prompts for AI interactions.
/// Each action/page gets tailored data injected into the prompt.
@MainActor
enum AIContextBuilder {

    // MARK: - Base Context (always included)

    static func baseContext() -> String {
        var lines: [String] = []
        let today = DateFormatters.todayString

        // Nutrition — pre-computed with target
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: today)) ?? .zero
        let target = FoodService.resolvedCalorieTarget()

        if nutrition.calories > 0 {
            let left = target - Int(nutrition.calories)
            lines.append("Calories: \(Int(nutrition.calories)) eaten, \(target) target, \(left > 0 ? "\(left) remaining" : "\(abs(left)) over target")")
            lines.append("Macros: \(Int(nutrition.proteinG))P \(Int(nutrition.carbsG))C \(Int(nutrition.fatG))F")
        } else {
            lines.append("No food logged | Target: \(target)cal")
        }

        // Weight — from centralized trend service
        let ws = WeightTrendService.shared
        if let trend = ws.trend, !ws.isStale {
            let u = Preferences.weightUnit
            let w = String(format: "%.1f", u.convert(fromKg: trend.currentEMA))
            let rate = String(format: "%+.1f", u.convert(fromKg: trend.weeklyRateKg))
            lines.append("Weight: \(w)\(u.displayName) | \(rate)/wk")
        }

        // Goal — pre-computed with progress
        if let goal = WeightGoal.load() {
            let u = Preferences.weightUnit
            let currentKg = ws.trendWeight
            let direction = currentKg.map { goal.isLosing(currentWeightKg: $0) ? "losing" : "gaining" } ?? "targeting"
            if let currentKg {
                let progress = goal.progress(currentWeightKg: currentKg)
                let goalW = String(format: "%.1f", u.convert(fromKg: goal.targetWeightKg))
                lines.append("Goal: \(direction) to \(goalW)\(u.displayName) | \(Int(progress * 100))% done | \(goal.monthsToAchieve)mo")
            }
        }

        // Pre-computed insights — tell the model what's notable
        let hour = Calendar.current.component(.hour, from: Date())
        if nutrition.calories > 0 {
            let pctTarget = Double(nutrition.calories) / Double(target)
            if hour < 12 && pctTarget > 0.5 {
                lines.append("Note: eaten >50% of target before noon")
            } else if hour > 18 && pctTarget < 0.3 {
                lines.append("Note: only \(Int(pctTarget * 100))% of target by evening — undereating today")
            }
            if nutrition.proteinG < 30 && hour > 14 {
                lines.append("Note: low protein so far (\(Int(nutrition.proteinG))g)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Food Context

    static func foodContext() -> String {
        var lines: [String] = []
        let today = DateFormatters.todayString

        // Today's food entries grouped by meal
        var todayHasFood = false
        if let logs = try? AppDatabase.shared.fetchMealLogs(for: today) {
            for log in logs {
                guard let logId = log.id, let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: logId),
                      !entries.isEmpty else { continue }
                let mealName = log.mealType.capitalized
                let foods = entries.map { "\($0.foodName) \(Int($0.totalCalories))cal" }.joined(separator: ", ")
                lines.append("\(mealName): \(foods)")
                todayHasFood = true
            }
        }
        if !todayHasFood {
            lines.append("Today: Nothing logged yet.")
        }

        // Past foods for meal suggestions — logged on previous days, NOT today
        if let recents = try? AppDatabase.shared.fetchRecentEntryNames() {
            let items = recents.prefix(5).map { "\($0.name)(\(Int($0.proteinG))P)" }
            if !items.isEmpty {
                lines.append("Suggestions from past days (not today\'s log): \(items.joined(separator: ", "))")
            }
        }

        // Macro targets — pre-computed remaining macros for meal suggestions
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: today)) ?? .zero
        if let goal = WeightGoal.load(),
           let targets = goal.macroTargets(currentWeightKg: WeightTrendService.shared.latestWeightKg) {
            let pLeft = max(0, Int(targets.proteinG - nutrition.proteinG))
            let cLeft = max(0, Int(targets.carbsG - nutrition.carbsG))
            let fLeft = max(0, Int(targets.fatG - nutrition.fatG))
            lines.append("Remaining macros: \(pLeft)P \(cLeft)C \(fLeft)F")
        }

        // 7-day average
        let cal = Calendar.current
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) {
            let from = DateFormatters.dateOnly.string(from: weekAgo)
            let to = DateFormatters.todayString
            if let avg = try? AppDatabase.shared.averageDailyCalories(from: from, to: to), avg > 0 {
                lines.append("7d avg: \(Int(avg))cal/day")
            }
        }

        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }

    // MARK: - Weight Context

    static func weightContext() -> String {
        var lines: [String] = []

        if let trend = WeightTrendService.shared.trend, !WeightTrendService.shared.isStale {
                let u = Preferences.weightUnit
                let changes = trend.weightChanges
                let cur = String(format: "%.1f", u.convert(fromKg: trend.currentEMA))
                let rate = String(format: "%+.1f", u.convert(fromKg: trend.weeklyRateKg))
                lines.append("Weight: \(cur)\(u.displayName) | \(rate)/wk | \(trend.trendDirection)")

                if let d7 = changes.sevenDay {
                    lines.append("7d: \(String(format: "%+.1f", u.convert(fromKg: d7)))\(u.displayName)")
                }
                if let d30 = changes.thirtyDay {
                    lines.append("30d: \(String(format: "%+.1f", u.convert(fromKg: d30)))\(u.displayName)")
                }

                // Pre-computed assessment
                let isLosingGoal = (WeightGoal.load()?.targetWeightKg ?? 0) < trend.currentEMA
                if isLosingGoal && trend.weeklyRateKg < -0.15 {
                    lines.append("Assessment: losing at healthy pace")
                } else if isLosingGoal && trend.weeklyRateKg > 0 {
                    lines.append("Assessment: gaining despite losing goal — review intake")
                } else if !isLosingGoal && trend.weeklyRateKg > 0.1 {
                    lines.append("Assessment: gaining as planned")
                }

            // Goal progress
            if let goal = WeightGoal.load() {
                let u = Preferences.weightUnit
                let progress = goal.progress(currentWeightKg: trend.currentEMA)
                lines.append("Goal: \(String(format: "%.1f", u.convert(fromKg: goal.targetWeightKg)))\(u.displayName) | \(Int(progress * 100))% done")
            }
        }

        return lines.isEmpty ? "No weight data." : "Weight analytics:\n" + lines.joined(separator: "\n")
    }

    // MARK: - Full Day Context (for Summary)

    static func fullDayContext() -> String {
        var lines: [String] = []

        // Include food context
        lines.append(foodContext())

        // Workouts today
        let today = DateFormatters.todayString
        if let workouts = try? WorkoutService.fetchWorkouts(limit: 10) {
            let todayWorkouts = workouts.filter { $0.date == today }
            if !todayWorkouts.isEmpty {
                lines.append("Today's workouts: \(todayWorkouts.map(\.name).joined(separator: ", "))")
            } else {
                lines.append("No workout today.")
            }
        }

        // Supplements
        if let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
           !supplements.isEmpty,
           let logs = try? AppDatabase.shared.fetchSupplementLogs(for: today) {
            let taken = logs.filter(\.taken).count
            lines.append("Supplements: \(taken)/\(supplements.count)")
        }

        // Sleep/recovery (from cache)
        let sleep = sleepRecoveryContext()
        if !sleep.isEmpty && !sleep.contains("No sleep") {
            lines.append(sleep)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Workout Context

    static func workoutContext() -> String {
        var lines: [String] = []

        if let workouts = try? WorkoutService.fetchWorkouts(limit: 10) {
            if let last = workouts.first {
                let daysAgo = Calendar.current.dateComponents([.day], from: DateFormatters.dateOnly.date(from: last.date) ?? Date(), to: Date()).day ?? 0
                lines.append("Last: \(last.name) (\(daysAgo)d ago)")

                // Show last workout's exercises so LLM knows what was done
                if let lastId = last.id, let sets = try? WorkoutService.fetchSets(forWorkout: lastId) {
                    let grouped = Dictionary(grouping: sets.filter { !$0.isWarmup }, by: \.exerciseName)
                    let summary = grouped.prefix(5).map { (name, sets) in
                        let bestSet = sets.max(by: { ($0.weightLbs ?? 0) < ($1.weightLbs ?? 0) })
                        let w = bestSet?.weightLbs.map { "\(Int($0))lb" } ?? ""
                        return "\(name) \(sets.count)x\(w)"
                    }.joined(separator: ", ")
                    if !summary.isEmpty { lines.append("Last exercises: \(summary)") }
                }

                if daysAgo == 0 {
                    lines.append("Note: already trained today")
                } else if daysAgo >= 3 {
                    lines.append("Note: \(daysAgo) days since last workout — may be time to train")
                }
            }

            // This week count
            let thisWeek = workouts.filter {
                guard let d = DateFormatters.dateOnly.date(from: $0.date) else { return false }
                return Calendar.current.isDate(d, equalTo: Date(), toGranularity: .weekOfYear)
            }.count
            lines.append("This week: \(thisWeek) workouts")

            // Body part coverage — which parts haven't been trained recently
            var bodyPartDays: [String: Int] = [:]
            for w in workouts.prefix(7) {
                guard let wId = w.id, let sets = try? WorkoutService.fetchSets(forWorkout: wId) else { continue }
                let daysAgo = Calendar.current.dateComponents([.day], from: DateFormatters.dateOnly.date(from: w.date) ?? Date(), to: Date()).day ?? 0
                for name in Set(sets.map(\.exerciseName)) {
                    let part = ExerciseDatabase.bodyPart(for: name)
                    if bodyPartDays[part] == nil || daysAgo < bodyPartDays[part]! {
                        bodyPartDays[part] = daysAgo
                    }
                }
            }
            if !bodyPartDays.isEmpty {
                let neglected = bodyPartDays.filter { $0.value >= 4 }.sorted { $0.value > $1.value }
                if !neglected.isEmpty {
                    let parts = neglected.map { "\($0.key) (\($0.value)d)" }.joined(separator: ", ")
                    lines.append("Needs training: \(parts)")
                }
            }
        }

        // Templates — suggest but don't auto-start (ask user to confirm first)
        if let templates = try? WorkoutService.fetchTemplates(), !templates.isEmpty {
            for t in templates.prefix(3) {
                let exerciseNames = t.exercises.prefix(4).map(\.name).joined(separator: ", ")
                lines.append("Template '\(t.name)': \(exerciseNames)")
            }
            lines.append("Suggest a template, ask user to say 'start [name]' to begin.")

            // Suggest one not done recently
            if let workouts = try? WorkoutService.fetchWorkouts(limit: 5) {
                let recentSet = Set(workouts.map(\.name))
                if let suggestion = templates.first(where: { !recentSet.contains($0.name) }) {
                    lines.append("Recommendation: \(suggestion.name) (not done recently)")
                }
            }
        }

        return lines.isEmpty ? "No workout data." : lines.joined(separator: "\n")
    }

    // MARK: - Supplement Context

    static func supplementContext() -> String {
        let today = DateFormatters.todayString
        guard let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
              !supplements.isEmpty,
              let logs = try? AppDatabase.shared.fetchSupplementLogs(for: today) else {
            return "No supplements set up."
        }
        let takenIds = Set(logs.filter(\.taken).compactMap(\.supplementId))
        let taken = takenIds.count
        let total = supplements.count
        var lines = ["Supplements: \(taken)/\(total) taken"]
        if taken == total {
            lines.append("Note: all supplements taken today")
        } else {
            let untaken = supplements.filter { !takenIds.contains($0.id ?? 0) }.map(\.name)
            lines.append("Still need: \(untaken.joined(separator: ", "))")
        }
        // Skip per-item list to save tokens — "Still need:" already shows what's missing
        return lines.joined(separator: "\n")
    }

    // MARK: - Yesterday Context

    static func yesterdayContext() -> String {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) else { return "" }
        let dateStr = DateFormatters.dateOnly.string(from: yesterday)
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: dateStr)) ?? .zero

        if nutrition.calories == 0 { return "No food logged yesterday." }

        let target = FoodService.resolvedCalorieTarget()
        let vsTarget = Int(nutrition.calories) - target

        var lines = ["Yesterday: \(Int(nutrition.calories))cal (\(vsTarget > 0 ? "+\(vsTarget) over" : "\(abs(vsTarget)) under") target), \(Int(nutrition.proteinG))P \(Int(nutrition.carbsG))C \(Int(nutrition.fatG))F"]

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
        if !foods.isEmpty {
            lines.append("Foods: \(foods.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Screen-Aware Context

    static func buildContext(screen: AIScreen) -> String {
        var parts: [String] = [baseContext()]
        parts.append(screenContext(screen: screen))
        return truncateToFit(parts.joined(separator: "\n"), maxTokens: 800)
    }

    static func screenContext(screen: AIScreen) -> String {
        var context: String
        switch screen {
        case .dashboard: context = fullDayContext()
        case .weight, .goal: context = weightContext()
        case .food: context = foodContext()
        case .exercise: context = workoutContext()
        case .supplements: context = supplementContext()
        case .bodyRhythm: context = sleepRecoveryContext()
        case .cycle: context = cycleContext()
        case .bodyComposition: context = dexaContext()
        case .glucose: context = glucoseContext()
        case .biomarkers: context = biomarkerContext()
        case .settings, .algorithm: context = ""
        }

        // Action hints — always available so LLM can classify any intent
        var actions: [String] = ["[LOG_FOOD: name amount]", "[LOG_WEIGHT: value unit]",
                                  "[START_WORKOUT: name]", "[CREATE_WORKOUT: Exercise 3x10@135]"]
        // Emphasize the most relevant action for the current screen
        switch screen {
        case .food: actions = ["[LOG_FOOD: name amount]"] + actions.filter { !$0.contains("LOG_FOOD") }
        case .exercise: actions = ["[START_WORKOUT: name]", "[CREATE_WORKOUT: Exercise 3x10@135]"] + actions.filter { !$0.contains("WORKOUT") }
        case .weight, .goal: actions = ["[LOG_WEIGHT: value unit]"] + actions.filter { !$0.contains("LOG_WEIGHT") }
        default: break
        }
        context += "\nActions: \(actions.joined(separator: ", "))"

        return context
    }

    // Sleep, Glucose, Biomarker, DEXA, and Cycle contexts in AIContextBuilder+Health.swift

    // MARK: - App Feature Context (conditionally included for app-about queries)

    static func featureContext() -> String {
        """
        Drift: local-first health tracker, all data on-device. \
        Food: 2400+ foods, barcode scan, "log 2 eggs" or Food tab. \
        Weight: daily weigh-ins, EMA trend, goal projection, Apple Health sync. \
        Exercise: templates, Strong/Hevy import, sets/reps/weight. \
        Also: sleep/HRV, cycle tracking, supplements, DEXA, glucose, biomarkers — all from Apple Health. \
        AI chat (this): on-device, private. Say "log", "start workout", or ask questions.
        """
    }

    // MARK: - Comparison Context

    /// Pre-computed this-week vs last-week comparison for food and weight.
    static func comparisonContext() -> String {
        var lines: [String] = []
        let cal = Calendar.current
        let today = Date()

        // This week vs last week calories
        guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today)),
              let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart),
              let lastWeekEnd = cal.date(byAdding: .day, value: -1, to: weekStart) else {
            return ""
        }

        let thisWeekFrom = DateFormatters.dateOnly.string(from: weekStart)
        let thisWeekTo = DateFormatters.dateOnly.string(from: today)
        let lastWeekFrom = DateFormatters.dateOnly.string(from: lastWeekStart)
        let lastWeekTo = DateFormatters.dateOnly.string(from: lastWeekEnd)

        let thisAvg = (try? AppDatabase.shared.averageDailyCalories(from: thisWeekFrom, to: thisWeekTo)) ?? 0
        let lastAvg = (try? AppDatabase.shared.averageDailyCalories(from: lastWeekFrom, to: lastWeekTo)) ?? 0

        if thisAvg > 0 || lastAvg > 0 {
            lines.append("This week avg: \(Int(thisAvg))cal/day | Last week: \(Int(lastAvg))cal/day")
            if lastAvg > 0 {
                let diff = thisAvg - lastAvg
                lines.append("Change: \(diff > 0 ? "+" : "")\(Int(diff))cal/day (\(diff > 0 ? "eating more" : "eating less"))")
            }
        }

        return lines.isEmpty ? "" : lines.joined(separator: "\n")
    }

    // MARK: - Token Budget Management

    /// Rough token estimate (1 token per 4 chars for English text).
    static func estimateTokens(_ text: String) -> Int {
        text.utf8.count / 4
    }

    /// Truncate context to fit within budget, preserving complete lines.
    static func truncateToFit(_ context: String, maxTokens: Int = 800) -> String {
        guard estimateTokens(context) > maxTokens else { return context }
        let targetChars = maxTokens * 4
        let truncated = String(context.prefix(targetChars))
        if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[...lastNewline])
        }
        return truncated
    }

    // MARK: - Legacy (backward compat)

    static func buildContext() -> String {
        buildContext(screen: .dashboard)
    }
}
