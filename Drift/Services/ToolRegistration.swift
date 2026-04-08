import Foundation

/// Registers all service tools in the ToolRegistry.
/// Called once at app startup.
@MainActor
enum ToolRegistration {

    static func registerAll() {
        let r = ToolRegistry.shared

        // MARK: - Food Tools (3 — consolidated from 7)
        // Small models need FEWER, MORE DISTINCT tools

        r.register(ToolSchema(
            id: "food.log_food", name: "log_food", service: "food",
            description: "User wants to LOG/ADD food they ate. Use this when they say 'I had', 'ate', 'log', 'add'.",
            parameters: [ToolParam("name", "string", "Food name"), ToolParam("amount", "number", "How many servings or grams (e.g. '200g', '2')", required: false)],
            preHook: { params in
                // Parse gram amounts: "paneer biryani 200g" or amount="200g"
                guard let rawName = params.string("name") else { return params }
                var name = rawName
                var gramAmount: Double? = nil
                var servings = params.double("amount")

                // Check if amount contains "g" → treat as grams
                if let amtStr = params.string("amount") {
                    let gramPattern = #"^(\d+\.?\d*)\s*g(?:ram)?s?$"#
                    if let regex = try? NSRegularExpression(pattern: gramPattern, options: .caseInsensitive),
                       let match = regex.firstMatch(in: amtStr, range: NSRange(amtStr.startIndex..., in: amtStr)),
                       let numRange = Range(match.range(at: 1), in: amtStr),
                       let grams = Double(String(amtStr[numRange])) {
                        gramAmount = grams
                        servings = nil
                    }
                }

                // Also parse "200g" or "200 gram" embedded in the name
                let nameGramPattern = #"\s+(\d+\.?\d*)\s*g(?:ram)?s?\s*$"#
                if gramAmount == nil,
                   let regex = try? NSRegularExpression(pattern: nameGramPattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                   let numRange = Range(match.range(at: 1), in: name),
                   let grams = Double(String(name[numRange])) {
                    gramAmount = grams
                    name = String(name[..<name.index(name.startIndex, offsetBy: match.range.location)]).trimmingCharacters(in: .whitespaces)
                }

                // DB lookup + gram→serving conversion
                if let food = AIActionExecutor.findFood(query: name, servings: servings, gramAmount: gramAmount) {
                    var enriched: [String: String] = ["name": food.food.name]
                    enriched["amount"] = "\(food.servings)"
                    return ToolCallParams(values: enriched)
                }

                // No match — pass cleaned name through for search
                var enriched: [String: String] = ["name": name]
                if let s = servings { enriched["amount"] = "\(s)" }
                return ToolCallParams(values: enriched)
            },
            handler: { params in
                guard let name = params.string("name") else { return .error("Missing food name") }
                return .action(.openFoodSearch(query: name, servings: params.double("amount")))
            }
        ))

        r.register(ToolSchema(
            id: "food.food_info", name: "food_info", service: "food",
            description: "User asks ABOUT food: calories, protein, nutrition, 'what should I eat', diet questions. NOT for logging.",
            parameters: [ToolParam("query", "string", "What they asked about", required: false)],
            handler: { params in
                let query = (params.string("query") ?? "").lowercased()

                // Nutrition lookup for specific food: "calories in banana"
                if !query.isEmpty, let result = FoodService.getNutrition(name: query) {
                    return .text("\(result.perServing) Say 'log \(result.food.name.lowercased())' to add it.")
                }

                let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
                let goal = WeightGoal.load()
                let targets = goal?.macroTargets()

                // Macro-specific focus: "how is my protein", "carbs today", "fat intake"
                if query.contains("protein") {
                    guard n.proteinG > 0 else { return .text("No food logged yet. Log meals to track protein.") }
                    if let t = targets {
                        let left = max(0, Int(t.proteinG - n.proteinG))
                        var response = "\(Int(n.proteinG))g protein today (\(Int(t.proteinG))g target). \(left > 0 ? "Still need \(left)g." : "Target reached!")"
                        let topP = FoodService.topProteinFoods(limit: 3)
                        if left > 20 && !topP.isEmpty {
                            response += " Try: " + topP.map { "\($0.name) (\(Int($0.proteinG))P)" }.joined(separator: ", ")
                        }
                        return .text(response)
                    }
                    return .text("\(Int(n.proteinG))g protein today.")
                }
                if query.contains("carb") {
                    let left = targets.map { max(0, Int($0.carbsG - n.carbsG)) }
                    return .text("\(Int(n.carbsG))g carbs today.\(left.map { " Target: \(Int(targets!.carbsG))g. \($0 > 0 ? "Need \($0)g more." : "Reached!")" } ?? "")")
                }
                if query.contains("fat") && !query.contains("body fat") {
                    let left = targets.map { max(0, Int($0.fatG - n.fatG)) }
                    return .text("\(Int(n.fatG))g fat today.\(left.map { " Target: \(Int(targets!.fatG))g. \($0 > 0 ? "Need \($0)g more." : "Reached!")" } ?? "")")
                }

                // Yesterday summary
                if query.contains("yesterday") {
                    return .text(AIRuleEngine.yesterdaySummary())
                }
                // Weekly summary
                if query.contains("weekly") || query.contains("week") {
                    return .text(AIRuleEngine.weeklySummary())
                }
                // Meal suggestions
                if query.contains("suggest") || query.contains("what should") || query.contains("what to eat") {
                    let totals = FoodService.getDailyTotals()
                    let targets = goal?.macroTargets()
                    let protLeft = targets.map { max(0, Int($0.proteinG) - totals.proteinG) }
                    let suggestions = FoodService.suggestMeal(caloriesLeft: totals.remaining, proteinNeeded: protLeft)
                    var lines = ["\(totals.remaining) cal remaining. \(protLeft.map { "Need \($0)g more protein." } ?? "")"]
                    if !suggestions.isEmpty {
                        lines.append("Suggestions: " + suggestions.prefix(3).map { "\($0.name) (\(Int($0.calories)) cal, \(Int($0.proteinG))g protein)" }.joined(separator: ", "))
                    }
                    return .text(lines.joined(separator: "\n"))
                }

                // General food info: calories, macros, suggestions, context
                let totals = FoodService.getDailyTotals()
                var lines: [String] = []
                let pctEaten = totals.target > 0 ? Int(Double(totals.eaten) / Double(totals.target) * 100) : 0
                lines.append("Calories: \(totals.eaten) eaten of \(totals.target) target (\(totals.remaining > 0 ? "\(totals.remaining) remaining" : "\(abs(totals.remaining)) over")).")
                // Progress indicator for LLM context
                if pctEaten < 30 { lines.append("Status: early in the day, plenty of budget left.") }
                else if pctEaten >= 80 && pctEaten <= 105 { lines.append("Status: close to target, on track.") }
                else if pctEaten > 105 { lines.append("Status: over target by \(abs(totals.remaining)) cal.") }

                if let t = targets {
                    let pLeft = max(0, Int(t.proteinG) - totals.proteinG)
                    let cLeft = max(0, Int(t.carbsG) - totals.carbsG)
                    let fLeft = max(0, Int(t.fatG) - totals.fatG)
                    lines.append("Macros: \(totals.proteinG)P/\(totals.carbsG)C/\(totals.fatG)F. Need: \(pLeft)P \(cLeft)C \(fLeft)F more.")
                }

                let suggestions = FoodService.suggestMeal()
                if !suggestions.isEmpty {
                    lines.append("Try: " + suggestions.prefix(3).map { "\($0.name) (\(Int($0.calories))cal, \(Int($0.proteinG))P)" }.joined(separator: ", "))
                }

                if totals.proteinG < 50 {
                    let topP = FoodService.topProteinFoods(limit: 3)
                    if !topP.isEmpty {
                        lines.append("High protein: " + topP.map { "\($0.name) (\(Int($0.proteinG))P)" }.joined(separator: ", "))
                    }
                }

                // Include supplement + workout status for broad status queries
                if query.contains("how") || query.contains("doing") || query.contains("summary") || query.contains("status") {
                    let today = DateFormatters.todayString
                    if let supps = try? AppDatabase.shared.fetchActiveSupplements(), !supps.isEmpty,
                       let logs = try? AppDatabase.shared.fetchSupplementLogs(for: today) {
                        let taken = logs.filter(\.taken).count
                        lines.append("Supplements: \(taken)/\(supps.count) taken.")
                    }
                    if let workouts = try? WorkoutService.fetchWorkouts(limit: 10) {
                        let todayWorkouts = workouts.filter { $0.date == today }
                        if !todayWorkouts.isEmpty {
                            lines.append("Workout: \(todayWorkouts.map(\.name).joined(separator: ", "))")
                        }
                    }
                }

                return .text(lines.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "food.copy_yesterday", name: "copy_yesterday", service: "food",
            description: "User wants to COPY or REPEAT yesterday's food. Use when they say 'same as yesterday', 'copy yesterday'.",
            parameters: [],
            handler: { _ in .text(FoodService.copyYesterday()) }
        ))

        r.register(ToolSchema(
            id: "food.delete_food", name: "delete_food", service: "food",
            description: "User wants to REMOVE or DELETE a food entry. Use when they say 'remove', 'delete', 'undo food'.",
            parameters: [ToolParam("name", "string", "Food name to remove, or 'last' for most recent entry")],
            handler: { params in
                let name = params.string("name") ?? "last"
                return .text(FoodService.deleteEntry(matching: name))
            }
        ))

        r.register(ToolSchema(
            id: "food.explain_calories", name: "explain_calories", service: "food",
            description: "User asks HOW calories are calculated, what TDEE means, or why their target is a certain number.",
            parameters: [],
            handler: { _ in .text(FoodService.explainCalories()) }
        ))

        // MARK: - Weight Tools (2 — consolidated from 4)

        r.register(ToolSchema(
            id: "weight.log_weight", name: "log_weight", service: "weight",
            description: "User wants to LOG their body weight. Use when they say 'I weigh', 'my weight is', 'scale says'.",
            parameters: [ToolParam("value", "number", "Weight number"), ToolParam("unit", "string", "kg or lbs", required: false)],
            needsConfirmation: true,
            validate: { params in
                guard let value = params.double("value") else { return "Missing weight value" }
                let unit = params.string("unit") ?? "lbs"
                let kg = unit.lowercased().hasPrefix("kg") ? value : value / 2.20462
                if kg < 20 || kg > 300 { return "Weight \(value) \(unit) is outside valid range" }
                return nil
            },
            handler: { params in
                guard let value = params.double("value") else { return .error("Missing weight value") }
                let unit = params.string("unit") ?? "lbs"
                // Show confirmation first — Swift pre-parser handles actual logging
                return .text("Log \(String(format: "%.1f", value)) \(unit) for today? Say 'yes' to confirm.")
            }
        ))

        r.register(ToolSchema(
            id: "weight.weight_info", name: "weight_info", service: "weight",
            description: "User asks ABOUT their weight: trend, progress, goal, body fat, BMI. NOT for logging.",
            parameters: [],
            handler: { _ in
                var lines: [String] = []
                lines.append(WeightServiceAPI.describeTrend())
                if let goal = WeightServiceAPI.getGoalProgress() {
                    lines.append("Goal: \(String(format: "%.1f", goal.currentWeight)) → \(String(format: "%.1f", goal.targetWeight))\(goal.unit), \(goal.progressPct)% done.")
                }
                // Enrich with total change + weekly trend for LLM presentation
                let unit = Preferences.weightUnit
                if let entries = try? AppDatabase.shared.fetchWeightEntries(), entries.count >= 2 {
                    let latest = entries.first!
                    let oldest = entries.last!
                    let totalChange = unit.convert(fromKg: latest.weightKg - oldest.weightKg)
                    lines.append("Total change: \(totalChange >= 0 ? "+" : "")\(String(format: "%.1f", totalChange)) \(unit.displayName) over \(entries.count) entries")
                    // Weekly
                    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
                    let weekStr = DateFormatters.dateOnly.string(from: weekAgo)
                    let recent = entries.filter { $0.date >= weekStr }
                    if recent.count >= 2, let weekOldest = recent.last {
                        let weekChange = unit.convert(fromKg: latest.weightKg - weekOldest.weightKg)
                        lines.append("This week: \(weekChange >= 0 ? "+" : "")\(String(format: "%.1f", weekChange)) \(unit.displayName)")
                    }
                }
                return .text(lines.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "weight.set_goal", name: "set_goal", service: "weight",
            description: "User wants to SET or UPDATE their weight goal. Use when they say 'set goal to', 'target weight', 'I want to weigh'.",
            parameters: [ToolParam("target", "number", "Target weight"), ToolParam("unit", "string", "kg or lbs", required: false)],
            handler: { params in
                guard let target = params.double("target") else { return .error("Missing target weight") }
                let unit = params.string("unit") ?? Preferences.weightUnit.rawValue
                let targetKg = unit.lowercased().hasPrefix("kg") ? target : target / 2.20462
                if targetKg < 20 || targetKg > 200 { return .error("Target \(target) \(unit) is outside valid range.") }

                let currentKg = (try? AppDatabase.shared.fetchWeightEntries())?.first?.weightKg ?? targetKg
                var goal = WeightGoal.load() ?? WeightGoal(targetWeightKg: targetKg, monthsToAchieve: 6,
                    startDate: DateFormatters.todayString, startWeightKg: currentKg)
                goal.targetWeightKg = targetKg
                goal.save()
                let display = unit.lowercased().hasPrefix("kg") ? String(format: "%.1f kg", target) : String(format: "%.0f lbs", target)
                return .text("Goal set to \(display).")
            }
        ))

        // MARK: - Exercise Tools (2 — consolidated from 4)

        r.register(ToolSchema(
            id: "exercise.start_workout", name: "start_workout", service: "exercise",
            description: "User wants to START or BEGIN a workout. Use when they say 'start', 'begin', 'let's do', or name a body part.",
            parameters: [ToolParam("name", "string", "Template name or muscle group like 'chest', 'legs', 'push day'")],
            handler: { params in
                guard let name = params.string("name") else { return .text(ExerciseService.suggestWorkout()) }
                // Try template first
                if let _ = ExerciseService.startTemplate(name: name) {
                    return .action(.openWorkout(templateName: name))
                }
                // Build smart session for muscle group — open directly
                if let _ = ExerciseService.buildSmartSession(muscleGroup: name) {
                    return .action(.openWorkout(templateName: name))
                }
                return .text("No template for '\(name)'. Try 'chest', 'legs', 'back', or 'push day'.")
            }
        ))

        r.register(ToolSchema(
            id: "exercise.exercise_info", name: "exercise_info", service: "exercise",
            description: "User asks ABOUT workouts: what to train, progress, history, recovery. NOT for starting a workout.",
            parameters: [ToolParam("exercise", "string", "Specific exercise name if asking about progress", required: false)],
            handler: { params in
                if let exercise = params.string("exercise") {
                    var lines: [String] = []
                    // Progressive overload
                    if let info = ExerciseService.getProgressiveOverload(exercise: exercise) {
                        lines.append(info.trend)
                    }
                    // Last session data
                    if let w = (try? WorkoutService.lastWeight(for: exercise)) ?? nil {
                        lines.append("Last weight: \(Int(w)) lbs")
                    }
                    return .text(lines.isEmpty ? "No data for '\(exercise)' yet." : lines.joined(separator: "\n"))
                }
                // General workout info: suggestion + history + streak
                var lines: [String] = [ExerciseService.suggestWorkout()]
                // Recent workouts from HealthKit
                if let recent = try? await HealthKitService.shared.fetchRecentWorkouts(days: 7), !recent.isEmpty {
                    lines.append("Recent workouts:")
                    for w in recent.prefix(5) {
                        let dur = Int(w.duration / 60)
                        let cal = Int(w.calories)
                        let day = DateFormatters.shortDisplay.string(from: w.date)
                        lines.append("  \(day): \(w.type) — \(dur) min, \(cal) cal")
                    }
                }
                // Streak info
                if let streak = try? WorkoutService.workoutStreak() {
                    lines.append("Streak: \(streak.current) weeks (longest: \(streak.longest))")
                }
                return .text(lines.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "exercise.log_activity", name: "log_activity", service: "exercise",
            description: "User says they COMPLETED an activity: 'I did yoga', 'went running', 'just finished pilates'. NOT for starting a new workout.",
            parameters: [
                ToolParam("name", "string", "Activity name like 'yoga', 'running', 'swimming'"),
                ToolParam("duration", "number", "Duration in minutes if mentioned", required: false)
            ],
            needsConfirmation: true,
            preHook: { params in
                guard var name = params.string("name") else { return params }
                var duration = params.double("duration")

                // Parse duration embedded in name: "30 min yoga" → 30, "yoga"
                let durPattern = #"^(\d+)\s*(?:min(?:ute)?s?)\s+"#
                if duration == nil,
                   let regex = try? NSRegularExpression(pattern: durPattern),
                   let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                   let numRange = Range(match.range(at: 1), in: name) {
                    duration = Double(String(name[numRange]))
                    name = String(name[name.index(name.startIndex, offsetBy: match.range.length)...]).trimmingCharacters(in: .whitespaces)
                }

                // Also: "yoga for 30 min" → "yoga", 30
                let trailingDurPattern = #"\s+(?:for\s+)?(\d+)\s*(?:min(?:ute)?s?)\s*$"#
                if duration == nil,
                   let regex = try? NSRegularExpression(pattern: trailingDurPattern),
                   let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
                   let numRange = Range(match.range(at: 1), in: name) {
                    duration = Double(String(name[numRange]))
                    name = String(name[..<name.index(name.startIndex, offsetBy: match.range.location)]).trimmingCharacters(in: .whitespaces)
                }

                var enriched: [String: String] = ["name": name]
                if let d = duration { enriched["duration"] = "\(Int(d))" }
                return ToolCallParams(values: enriched)
            },
            handler: { params in
                guard let name = params.string("name"), !name.isEmpty else {
                    return .error("What activity did you do?")
                }
                let display = name.capitalized
                let durText = params.double("duration").map { " (\(Int($0)) min)" } ?? ""
                return .text("Log \(display)\(durText) for today? Say yes to confirm.")
            }
        ))

        // MARK: - Health Data Tools (2 — consolidated from 5)

        r.register(ToolSchema(
            id: "health.sleep_recovery", name: "sleep_recovery", service: "sleep",
            description: "User asks about SLEEP, RECOVERY, HRV, heart rate, tiredness, or whether to rest vs train.",
            parameters: [ToolParam("period", "string", "'today', 'week', or 'last week'", required: false)],
            handler: { params in
                var lines: [String] = []
                let sleep = SleepRecoveryService.getSleep()
                let recovery = SleepRecoveryService.getRecovery()
                let readiness = SleepRecoveryService.getReadiness()
                if !sleep.contains("No ") { lines.append(sleep) }
                if !recovery.contains("No ") { lines.append(recovery) }
                lines.append(readiness)
                // Weekly sleep trend from HealthKit
                let period = params.string("period")?.lowercased() ?? ""
                if period.contains("week") || period.contains("last") {
                    if let recent = try? await HealthKitService.shared.fetchRecentSleepData(days: 7), !recent.isEmpty {
                        let avgHours = recent.map(\.hours).reduce(0, +) / Double(recent.count)
                        lines.append("Last 7 days avg: \(String(format: "%.1f", avgHours))h sleep (\(recent.count) nights tracked)")
                    }
                }
                return .text(lines.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "health.supplements", name: "supplements", service: "supplement",
            description: "User asks about SUPPLEMENTS or VITAMINS: what they took, what's remaining.",
            parameters: [],
            handler: { _ in .text(SupplementService.getStatus()) }
        ))

        r.register(ToolSchema(
            id: "health.add_supplement", name: "add_supplement", service: "supplement",
            description: "User wants to ADD a new supplement to their daily stack. NOT for marking taken.",
            parameters: [ToolParam("name", "string", "Supplement name"),
                         ToolParam("dosage", "string", "Dosage like '5g' or '2000 IU'", required: false)],
            handler: { params in
                guard let name = params.string("name") else { return .error("Which supplement?") }
                return .text(SupplementService.addSupplement(name: name, dosage: params.string("dosage")))
            }
        ))

        r.register(ToolSchema(
            id: "health.mark_supplement", name: "mark_supplement", service: "supplement",
            description: "User TOOK a supplement. Use when they say 'took my creatine', 'had vitamin D', 'took fish oil'.",
            parameters: [ToolParam("name", "string", "Supplement name")],
            handler: { params in
                guard let name = params.string("name") else { return .error("Which supplement?") }
                return .text(SupplementService.markTaken(name: name))
            }
        ))

        // NOTE: Glucose, biomarker, and body composition tools are registered but NOT shown
        // in the default 6-tool prompt. They appear when user is on those specific screens.
        // This keeps the main prompt focused for the 1.5B model.

        r.register(ToolSchema(
            id: "health.glucose", name: "glucose", service: "glucose",
            description: "User asks about blood sugar, glucose readings, or spikes.",
            parameters: [],
            handler: { _ in .text(GlucoseService.getReadings() + "\n" + GlucoseService.detectSpikes()) }
        ))

        r.register(ToolSchema(
            id: "health.biomarkers", name: "biomarkers", service: "biomarker",
            description: "User asks about lab results, blood tests, or biomarkers.",
            parameters: [],
            handler: { _ in .text(BiomarkerService.getResults()) }
        ))

        r.register(ToolSchema(
            id: "health.body_comp", name: "body_comp", service: "bodycomp",
            description: "User asks about body composition, body fat %, BMI, lean mass, DEXA scans, or muscle mass.",
            parameters: [],
            handler: { _ in .text(AIContextBuilder.dexaContext()) }
        ))

        r.register(ToolSchema(
            id: "health.log_body_comp", name: "log_body_comp", service: "bodycomp",
            description: "User LOGS body composition data: body fat %, BMI, or weight from a smart scale.",
            parameters: [ToolParam("body_fat", "number", "Body fat percentage", required: false),
                         ToolParam("bmi", "number", "BMI value", required: false)],
            handler: { params in
                let bf = params.double("body_fat")
                let bmi = params.double("bmi")
                guard bf != nil || bmi != nil else { return .error("Provide body fat % or BMI.") }
                var entry = BodyComposition(date: DateFormatters.todayString, bodyFatPct: bf, bmi: bmi,
                                             source: "manual", createdAt: DateFormatters.iso8601.string(from: Date()))
                try? AppDatabase.shared.saveBodyComposition(&entry)
                var parts: [String] = []
                if let bf { parts.append("body fat \(String(format: "%.1f", bf))%") }
                if let bmi { parts.append("BMI \(String(format: "%.1f", bmi))") }
                return .text("Logged \(parts.joined(separator: ", ")).")
            }
        ))
    }
}
