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
            parameters: [ToolParam("name", "string", "Food name"), ToolParam("amount", "number", "How many servings", required: false)],
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
                let query = params.string("query") ?? ""
                // Try nutrition lookup first
                if !query.isEmpty, let result = FoodService.getNutrition(name: query) {
                    return .text("\(result.perServing) Say 'log \(result.food.name.lowercased())' to add it.")
                }
                // Show comprehensive food info: calories, macros, balance, suggestions
                let totals = FoodService.getDailyTotals()
                var lines: [String] = []
                lines.append("\(totals.remaining > 0 ? "\(totals.remaining)" : "0") cal remaining (\(totals.eaten)/\(totals.target)).")

                // Macro balance
                if let goal = WeightGoal.load(), let targets = goal.macroTargets() {
                    let pLeft = max(0, Int(targets.proteinG) - totals.proteinG)
                    let cLeft = max(0, Int(targets.carbsG) - totals.carbsG)
                    let fLeft = max(0, Int(targets.fatG) - totals.fatG)
                    lines.append("Macros: \(totals.proteinG)P/\(totals.carbsG)C/\(totals.fatG)F. Need: \(pLeft)P \(cLeft)C \(fLeft)F more.")
                }

                // Suggestions
                let suggestions = FoodService.suggestMeal()
                if !suggestions.isEmpty {
                    lines.append("Try: " + suggestions.prefix(3).map { "\($0.name) (\(Int($0.calories))cal, \(Int($0.proteinG))P)" }.joined(separator: ", "))
                }

                // Top protein if protein is low
                if totals.proteinG < 50 {
                    let topP = FoodService.topProteinFoods(limit: 3)
                    if !topP.isEmpty {
                        lines.append("High protein: " + topP.map { "\($0.name) (\(Int($0.proteinG))P)" }.joined(separator: ", "))
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
                // General workout suggestion with body part coverage
                var lines: [String] = [ExerciseService.suggestWorkout()]
                // Streak info
                if let streak = try? WorkoutService.workoutStreak() {
                    lines.append("Streak: \(streak.current) weeks (longest: \(streak.longest))")
                }
                return .text(lines.joined(separator: "\n"))
            }
        ))

        // MARK: - Health Data Tools (2 — consolidated from 5)

        r.register(ToolSchema(
            id: "health.sleep_recovery", name: "sleep_recovery", service: "sleep",
            description: "User asks about SLEEP, RECOVERY, HRV, heart rate, tiredness, or whether to rest vs train.",
            parameters: [],
            handler: { _ in
                var lines: [String] = []
                let sleep = SleepRecoveryService.getSleep()
                let recovery = SleepRecoveryService.getRecovery()
                let readiness = SleepRecoveryService.getReadiness()
                if !sleep.contains("No ") { lines.append(sleep) }
                if !recovery.contains("No ") { lines.append(recovery) }
                lines.append(readiness)
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
