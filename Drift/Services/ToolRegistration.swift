import Foundation

/// Registers all service tools in the ToolRegistry.
/// Called once at app startup (from LocalAIService or DriftApp).
@MainActor
enum ToolRegistration {

    static func registerAll() {
        let r = ToolRegistry.shared

        // MARK: - Food Tools

        r.register(ToolSchema(
            id: "food.search_food", name: "search_food", service: "food",
            description: "Search foods by name",
            parameters: [ToolParam("query", "string", "Food name to search")],
            handler: { params in
                guard let q = params.string("query") else { return .error("Missing query") }
                let results = FoodService.searchFood(query: q)
                if results.isEmpty { return .text("No foods found for '\(q)'.") }
                let list = results.prefix(3).map { "\($0.name) — \(Int($0.calories)) cal, \(Int($0.proteinG))g P" }
                return .text(list.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "food.log_food", name: "log_food", service: "food",
            description: "Log a food entry",
            parameters: [ToolParam("name", "string", "Food name"), ToolParam("amount", "number", "Servings", required: false), ToolParam("meal", "string", "Meal type", required: false)],
            handler: { params in
                guard let name = params.string("name") else { return .error("Missing food name") }
                return .action(.openFoodSearch(query: name, servings: params.double("amount")))
            }
        ))

        r.register(ToolSchema(
            id: "food.get_nutrition", name: "get_nutrition", service: "food",
            description: "Look up nutrition for a food",
            parameters: [ToolParam("name", "string", "Food name")],
            handler: { params in
                guard let name = params.string("name") else { return .error("Missing food name") }
                if let result = FoodService.getNutrition(name: name) {
                    return .text(result.perServing)
                }
                return .text("'\(name)' not found in database.")
            }
        ))

        r.register(ToolSchema(
            id: "food.get_calories_left", name: "get_calories_left", service: "food",
            description: "Show remaining calories and protein for today",
            parameters: [],
            handler: { _ in .text(FoodService.getCaloriesLeft()) },
            postHook: { _ in "Say 'suggest meal' for food ideas or 'explain calories' for the math." }
        ))

        r.register(ToolSchema(
            id: "food.explain_calories", name: "explain_calories", service: "food",
            description: "Explain calorie math: TDEE, deficit, target breakdown",
            parameters: [],
            handler: { _ in .text(FoodService.explainCalories()) }
        ))

        r.register(ToolSchema(
            id: "food.suggest_meal", name: "suggest_meal", service: "food",
            description: "Suggest foods that fit remaining calorie/protein budget",
            parameters: [],
            handler: { _ in
                let suggestions = FoodService.suggestMeal()
                if suggestions.isEmpty { return .text("No suggestions — log some food first so I can learn your preferences.") }
                let list = suggestions.map { "\($0.name) — \(Int($0.calories)) cal, \(Int($0.proteinG))g protein" }
                return .text("Try:\n" + list.joined(separator: "\n"))
            }
        ))

        r.register(ToolSchema(
            id: "food.top_protein", name: "top_protein", service: "food",
            description: "Show top high-protein foods from database",
            parameters: [],
            handler: { _ in
                let foods = FoodService.topProteinFoods(limit: 5)
                if foods.isEmpty { return .text("No food data available.") }
                let list = foods.map { "\($0.name) — \(Int($0.proteinG))g protein, \(Int($0.calories)) cal" }
                return .text("Top protein:\n" + list.joined(separator: "\n"))
            }
        ))

        // MARK: - Weight Tools

        r.register(ToolSchema(
            id: "weight.log_weight", name: "log_weight", service: "weight",
            description: "Log a body weight entry",
            parameters: [ToolParam("value", "number", "Weight value"), ToolParam("unit", "string", "kg or lbs", required: false)],
            validate: { params in
                guard let value = params.double("value") else { return "Missing weight value" }
                let unit = params.string("unit") ?? "lbs"
                let kg = unit.lowercased().hasPrefix("kg") ? value : value / 2.20462
                if kg < 20 || kg > 300 { return "Weight \(value) \(unit) is outside valid range (20-300 kg)" }
                return nil
            },
            handler: { params in
                guard let value = params.double("value") else { return .error("Missing weight value") }
                let unit = params.string("unit") ?? "lbs"
                if let _ = WeightServiceAPI.logWeight(value: value, unit: unit) {
                    return .text("Logged \(String(format: "%.1f", value)) \(unit).")
                }
                return .error("Invalid weight value.")
            }
        ))

        r.register(ToolSchema(
            id: "weight.get_trend", name: "get_trend", service: "weight",
            description: "Show weight trend: current, rate, direction",
            parameters: [],
            handler: { _ in .text(WeightServiceAPI.describeTrend()) }
        ))

        r.register(ToolSchema(
            id: "weight.get_goal", name: "get_goal", service: "weight",
            description: "Show goal progress: target, % done",
            parameters: [],
            handler: { _ in
                guard let goal = WeightServiceAPI.getGoalProgress() else { return .text("No weight goal set.") }
                return .text("\(String(format: "%.1f", goal.currentWeight))\(goal.unit) → \(String(format: "%.1f", goal.targetWeight))\(goal.unit). \(goal.progressPct)% done.")
            }
        ))

        // MARK: - Exercise Tools

        r.register(ToolSchema(
            id: "exercise.start_template", name: "start_template", service: "exercise",
            description: "Start a workout from a saved template",
            parameters: [ToolParam("name", "string", "Template name")],
            handler: { params in
                guard let name = params.string("name") else { return .error("Missing template name") }
                if let _ = ExerciseService.startTemplate(name: name) {
                    return .action(.openWorkout(templateName: name))
                }
                return .text("No template matching '\(name)' found.")
            }
        ))

        r.register(ToolSchema(
            id: "exercise.build_smart_session", name: "build_smart_session", service: "exercise",
            description: "Build a workout session (max 5 exercises, based on history)",
            parameters: [ToolParam("muscle_group", "string", "Target muscle group", required: false)],
            handler: { params in
                let group = params.string("muscle_group")
                if let template = ExerciseService.buildSmartSession(muscleGroup: group) {
                    let exercises = template.exercises.prefix(5).map { "\($0.name) — \($0.notes ?? "3x10")" }
                    return .text("Workout: \(template.name)\n" + exercises.joined(separator: "\n"))
                }
                return .text("Couldn't build a session. Try specifying a muscle group.")
            }
        ))

        r.register(ToolSchema(
            id: "exercise.suggest_workout", name: "suggest_workout", service: "exercise",
            description: "Suggest what to train based on recent history",
            parameters: [],
            handler: { _ in .text(ExerciseService.suggestWorkout()) }
        ))

        r.register(ToolSchema(
            id: "exercise.progressive_overload", name: "progressive_overload", service: "exercise",
            description: "Check if you're making progress on an exercise",
            parameters: [ToolParam("exercise", "string", "Exercise name")],
            handler: { params in
                guard let name = params.string("exercise") else { return .error("Missing exercise name") }
                if let info = ExerciseService.getProgressiveOverload(exercise: name) {
                    return .text(info.trend)
                }
                return .text("No data for '\(name)'. Log some workouts first.")
            }
        ))

        // MARK: - Sleep & Recovery Tools

        r.register(ToolSchema(
            id: "sleep.get_sleep", name: "get_sleep", service: "sleep",
            description: "Show last night's sleep data",
            parameters: [],
            handler: { _ in .text(SleepRecoveryService.getSleep()) }
        ))

        r.register(ToolSchema(
            id: "sleep.get_recovery", name: "get_recovery", service: "sleep",
            description: "Show recovery score, HRV, resting heart rate",
            parameters: [],
            handler: { _ in .text(SleepRecoveryService.getRecovery()) }
        ))

        r.register(ToolSchema(
            id: "sleep.get_readiness", name: "get_readiness", service: "sleep",
            description: "Assess training readiness based on recovery + sleep",
            parameters: [],
            handler: { _ in .text(SleepRecoveryService.getReadiness()) }
        ))

        // MARK: - Supplement Tools

        r.register(ToolSchema(
            id: "supplement.get_status", name: "get_supplement_status", service: "supplement",
            description: "Check which supplements taken today",
            parameters: [],
            handler: { _ in .text(SupplementService.getStatus()) }
        ))

        r.register(ToolSchema(
            id: "supplement.mark_taken", name: "mark_supplement_taken", service: "supplement",
            description: "Mark a supplement as taken",
            parameters: [ToolParam("name", "string", "Supplement name")],
            handler: { params in
                guard let name = params.string("name") else { return .error("Missing supplement name") }
                return .text(SupplementService.markTaken(name: name))
            }
        ))

        // MARK: - Glucose Tools

        r.register(ToolSchema(
            id: "glucose.get_readings", name: "get_glucose", service: "glucose",
            description: "Show today's glucose readings summary",
            parameters: [],
            handler: { _ in .text(GlucoseService.getReadings()) }
        ))

        r.register(ToolSchema(
            id: "glucose.detect_spikes", name: "detect_spikes", service: "glucose",
            description: "Check for glucose spikes today",
            parameters: [],
            handler: { _ in .text(GlucoseService.detectSpikes()) }
        ))

        // MARK: - Biomarker Tools

        r.register(ToolSchema(
            id: "biomarker.get_results", name: "get_biomarkers", service: "biomarker",
            description: "Show out-of-range biomarker results",
            parameters: [],
            handler: { _ in .text(BiomarkerService.getResults()) }
        ))

        r.register(ToolSchema(
            id: "biomarker.get_detail", name: "get_biomarker_detail", service: "biomarker",
            description: "Get details for a specific biomarker",
            parameters: [ToolParam("name", "string", "Biomarker name")],
            handler: { params in
                guard let name = params.string("name") else { return .error("Missing biomarker name") }
                return .text(BiomarkerService.getDetail(name: name))
            }
        ))
    }
}
