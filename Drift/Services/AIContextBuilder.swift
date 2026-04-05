import Foundation

/// Builds rich, context-specific prompts for AI interactions.
/// Each action/page gets tailored data injected into the prompt.
enum AIContextBuilder {

    // MARK: - Main Entry Point

    /// Build context for a specific tab + optional action.
    static func buildContext(tab: Int = 0, action: String? = nil) -> String {
        var parts: [String] = []

        // Always include base context + app features
        parts.append(baseContext())
        parts.append(featureContext())

        // Action-specific or page-specific context
        if let action {
            switch action {
            case "food": parts.append(foodContext())
            case "weight": parts.append(weightContext())
            case "summary": parts.append(fullDayContext())
            case "workout": parts.append(workoutContext())
            case "supplements": parts.append(supplementContext())
            case "yesterday": parts.append(yesterdayContext())
            default: parts.append(pageContext(tab: tab))
            }
        } else {
            parts.append(pageContext(tab: tab))
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Action-Specific Sub-Prompts

    static func actionPrompt(for action: String) -> String {
        switch action {
        case "food":
            return """
            The user wants to log food. \
            If they name a food, respond with [LOG_FOOD: food_name amount]. \
            If they describe a meal, break it into individual [LOG_FOOD:] items. \
            Ask what they ate if they haven't said.
            """
        case "weight":
            return """
            Tell them their current weight status using the data below. \
            Ask what they'd like to know: trend analysis, goal progress, or log a new weight?
            """
        case "summary":
            return """
            Summarize the user's day using the data below. \
            Highlight what's going well and what needs attention. Be encouraging.
            """
        case "workout":
            return """
            The user wants to work out. Based on their history below, \
            suggest what to train today. Offer to start a specific template with [START_WORKOUT: name].
            """
        case "supplements":
            return """
            Show the user their supplement status. \
            Remind them about any untaken supplements. Be encouraging if they've taken all.
            """
        case "yesterday":
            return """
            Show the user what they ate yesterday using the data below. \
            Compare to their goals and highlight any patterns.
            """
        default:
            return ""
        }
    }

    // MARK: - Base Context (always included)

    static func baseContext() -> String {
        var lines: [String] = []
        let today = DateFormatters.todayString

        // Today's nutrition
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: today)) ?? .zero
        if nutrition.calories > 0 {
            lines.append("Today's intake: \(Int(nutrition.calories))cal, \(Int(nutrition.proteinG))P \(Int(nutrition.carbsG))C \(Int(nutrition.fatG))F \(Int(nutrition.fiberG))fiber")
        } else {
            lines.append("No food logged today.")
        }

        // Weight + trend
        if let entries = try? AppDatabase.shared.fetchWeightEntries() {
            let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
            if let trend = WeightTrendCalculator.calculateTrend(entries: input) {
                let unit = Preferences.weightUnit
                lines.append("Weight: \(String(format: "%.1f", unit.convert(fromKg: trend.currentEMA))) \(unit.displayName)")
                lines.append("Weekly rate: \(String(format: "%+.2f", unit.convert(fromKg: trend.weeklyRateKg))) \(unit.displayName)/wk")
                if trend.estimatedDailyDeficit != 0 {
                    lines.append("Daily \(trend.estimatedDailyDeficit < 0 ? "deficit" : "surplus"): \(Int(abs(trend.estimatedDailyDeficit)))kcal")
                }
            }
        }

        // Goal
        if let goal = WeightGoal.load() {
            let unit = Preferences.weightUnit
            lines.append("Goal: \(String(format: "%.1f", unit.convert(fromKg: goal.targetWeightKg))) \(unit.displayName) in \(goal.monthsToAchieve)mo")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Food Context

    static func foodContext() -> String {
        var lines: [String] = []
        let today = DateFormatters.todayString

        // Recent foods for quick reference
        if let recents = try? AppDatabase.shared.fetchRecentEntryNames() {
            let names = recents.prefix(5).map(\.name)
            if !names.isEmpty {
                lines.append("Recent foods: \(names.joined(separator: ", "))")
            }
        }

        // Today's food entries
        if let logs = try? AppDatabase.shared.fetchMealLogs(for: today) {
            for log in logs {
                guard let logId = log.id, let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: logId) else { continue }
                for entry in entries {
                    lines.append("- \(entry.foodName): \(Int(entry.totalCalories))cal")
                }
            }
        }

        // 7-day average
        let cal = Calendar.current
        if let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) {
            let from = DateFormatters.dateOnly.string(from: weekAgo)
            let to = DateFormatters.todayString
            if let avg = try? AppDatabase.shared.averageDailyCalories(from: from, to: to), avg > 0 {
                lines.append("7-day avg: \(Int(avg))cal/day")
            }
        }

        return lines.isEmpty ? "" : "Food context:\n" + lines.joined(separator: "\n")
    }

    // MARK: - Weight Context

    static func weightContext() -> String {
        var lines: [String] = []

        if let entries = try? AppDatabase.shared.fetchWeightEntries() {
            let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
            if let trend = WeightTrendCalculator.calculateTrend(entries: input) {
                let unit = Preferences.weightUnit
                let changes = trend.weightChanges
                lines.append("Current: \(String(format: "%.1f", unit.convert(fromKg: trend.currentEMA))) \(unit.displayName)")
                lines.append("Weekly: \(String(format: "%+.2f", unit.convert(fromKg: trend.weeklyRateKg)))/wk")
                if let d7 = changes.sevenDay { lines.append("7-day change: \(String(format: "%+.1f", unit.convert(fromKg: d7)))") }
                if let d30 = changes.thirtyDay { lines.append("30-day change: \(String(format: "%+.1f", unit.convert(fromKg: d30)))") }
                if let proj = trend.projection30Day {
                    lines.append("30-day projection: \(String(format: "%.1f", unit.convert(fromKg: proj))) \(unit.displayName)")
                }
                lines.append("Direction: \(trend.trendDirection)")
            }

            // Goal progress
            if let goal = WeightGoal.load() {
                let unit = Preferences.weightUnit
                let progress = goal.progress(currentWeightKg: input.last?.weightKg ?? goal.targetWeightKg)
                lines.append("Goal: \(String(format: "%.1f", unit.convert(fromKg: goal.targetWeightKg))) \(unit.displayName)")
                lines.append("Progress: \(Int(progress * 100))%")
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
           let logs = try? AppDatabase.shared.fetchSupplementLogs(for: today) {
            let taken = logs.filter(\.taken).count
            lines.append("Supplements: \(taken)/\(supplements.count) taken")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Workout Context

    static func workoutContext() -> String {
        var lines: [String] = []

        if let workouts = try? WorkoutService.fetchWorkouts(limit: 10) {
            if let last = workouts.first {
                let daysAgo = Calendar.current.dateComponents([.day], from: DateFormatters.dateOnly.date(from: last.date) ?? Date(), to: Date()).day ?? 0
                lines.append("Last workout: \(last.name) (\(daysAgo) days ago)")
            }

            // This week count
            let thisWeek = workouts.filter {
                guard let d = DateFormatters.dateOnly.date(from: $0.date) else { return false }
                return Calendar.current.isDate(d, equalTo: Date(), toGranularity: .weekOfYear)
            }.count
            lines.append("This week: \(thisWeek) workouts")
        }

        // Templates
        if let templates = try? WorkoutService.fetchTemplates() {
            let names = templates.prefix(5).map(\.name)
            if !names.isEmpty {
                lines.append("Templates: \(names.joined(separator: ", "))")
            }
        }

        return lines.isEmpty ? "No workout history." : "Workout context:\n" + lines.joined(separator: "\n")
    }

    // MARK: - Supplement Context

    static func supplementContext() -> String {
        let today = DateFormatters.todayString
        guard let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
              let logs = try? AppDatabase.shared.fetchSupplementLogs(for: today) else {
            return "No supplements set up."
        }
        let takenIds = Set(logs.filter(\.taken).compactMap(\.supplementId))
        var lines = ["Supplements (\(takenIds.count)/\(supplements.count) taken):"]
        for s in supplements {
            let status = takenIds.contains(s.id ?? 0) ? "✓" : "✗"
            lines.append("  \(status) \(s.name)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Yesterday Context

    static func yesterdayContext() -> String {
        let cal = Calendar.current
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) else { return "" }
        let dateStr = DateFormatters.dateOnly.string(from: yesterday)
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: dateStr)) ?? .zero

        if nutrition.calories == 0 { return "No food logged yesterday." }

        var lines = ["Yesterday (\(DateFormatters.shortDisplay.string(from: yesterday))):"]
        lines.append("Total: \(Int(nutrition.calories))cal, \(Int(nutrition.proteinG))P \(Int(nutrition.carbsG))C \(Int(nutrition.fatG))F")

        if let logs = try? AppDatabase.shared.fetchMealLogs(for: dateStr) {
            for log in logs {
                guard let logId = log.id, let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: logId) else { continue }
                for entry in entries {
                    lines.append("- \(entry.foodName): \(Int(entry.totalCalories))cal")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Page Context (free text on specific tab)

    static func pageContext(tab: Int) -> String {
        switch tab {
        case 0: return fullDayContext() // Dashboard — everything
        case 1: return weightContext()
        case 2: return foodContext()
        case 3: return workoutContext()
        case 4: return supplementContext()
        default: return ""
        }
    }

    // MARK: - App Feature Context (always included so LLM can answer about Drift)

    static func featureContext() -> String {
        """
        About Drift (the app the user is using):
        - Local-first health tracking app. All data stays on device — no cloud, no accounts, no analytics.
        - Food logging: search 1000+ foods, scan barcodes (Open Food Facts), custom foods, copy from yesterday.
        - Weight tracking: daily weigh-ins, EMA trend line, goal progress projection, syncs with Apple Health.
        - Exercise: workout templates, import from Strong/Hevy, track sets/reps/weight, duration exercises.
        - Body Rhythm: sleep, HRV, resting heart rate from Apple Health.
        - Cycle tracking: reads period data from Apple Health, shows biometric correlations.
        - Supplements: daily checklist with consistency tracking.
        - Body Composition: DEXA scan data entry and tracking.
        - Glucose: CGM glucose tracking.
        - Biomarkers: blood test results and trends.
        - AI assistant (this chat): on-device, private, no data leaves the phone.
        - Barcode scanning: tap + on Food tab, then Scan. Looks up nutrition from Open Food Facts.
        - To log food: say "log 2 eggs" or use the Food tab search. Can also say "ate chicken breast".
        - To track weight: Weight tab → tap + to add entry. Apple Health weights sync automatically.
        - To start workout: Exercise tab → pick a template or create custom.
        """
    }

    // MARK: - Legacy (backward compat)

    static func buildContext() -> String {
        buildContext(tab: 0)
    }
}
