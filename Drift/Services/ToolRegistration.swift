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
                // Otherwise show calories left + suggestions
                let totals = FoodService.getDailyTotals()
                var lines = ["\(totals.remaining > 0 ? "\(totals.remaining)" : "0") cal remaining (\(totals.eaten)/\(totals.target)). \(totals.proteinG)g protein so far."]
                let suggestions = FoodService.suggestMeal()
                if !suggestions.isEmpty {
                    lines.append("Suggestions: " + suggestions.prefix(3).map { "\($0.name) (\(Int($0.calories))cal, \(Int($0.proteinG))P)" }.joined(separator: ", "))
                }
                return .text(lines.joined(separator: "\n"))
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
                // Build smart session for muscle group
                if let template = ExerciseService.buildSmartSession(muscleGroup: name) {
                    let exercises = template.exercises.prefix(5).map { "\($0.name) — \($0.notes ?? "3x10")" }
                    return .text("Workout: \(template.name)\n" + exercises.joined(separator: "\n") + "\nSay 'start' to begin.")
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
                    if let info = ExerciseService.getProgressiveOverload(exercise: exercise) {
                        return .text(info.trend)
                    }
                    return .text("No data for '\(exercise)' yet.")
                }
                return .text(ExerciseService.suggestWorkout())
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
    }
}
