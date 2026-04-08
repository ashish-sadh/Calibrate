import Foundation

// MARK: - Static Override Result

/// Result of a static override match — tells AIChatView what to do without hitting the LLM.
enum StaticResult: Sendable {
    case response(String)                    // Show this text directly
    case toolCall(ToolCall)                  // Execute this tool directly
    case uiAction(ToolAction, String?)       // Open a sheet/navigate + optional message
    case handler(@MainActor @Sendable () -> String)  // Run custom handler, show result
}

// MARK: - Static Overrides

/// Matches queries to pre-defined responses/actions. No LLM needed.
/// All overrides fire for both models. Unmatched queries fall through to AIToolAgent.
@MainActor
enum StaticOverrides {

    /// Returns a static result if the query matches, nil to fall through to AIToolAgent.
    static func match(_ query: String) -> StaticResult? {
        let lower = query.lowercased()

        // --- Universal overrides (both models) ---

        // Emoji-only
        if lower.unicodeScalars.allSatisfy({ $0.properties.isEmoji || $0.properties.isEmojiPresentation || $0 == " " })
            && !lower.isEmpty && lower.count <= 4 {
            return .response("What can I help you with?")
        }

        // Greetings
        let greetings: Set<String> = ["hi", "hello", "hey", "yo", "sup"]
        if greetings.contains(lower) {
            return .response("Hey! Ask about your food, weight, workouts, or say \"log 2 eggs\" to quickly log meals.")
        }

        // Thanks
        let thanks: Set<String> = ["thanks", "thank you", "thx", "ty", "cool", "ok", "okay", "got it", "nice"]
        if thanks.contains(lower) {
            return .response("Anytime! Let me know if you need anything else.")
        }

        // Help
        if lower == "help" || lower == "what can you do" || lower == "what can you do?" {
            return .response("I can help you:\n\u{2022} Log food: \"log 2 eggs and toast\"\n\u{2022} Log workout: \"I did bench press 3x10 at 135\"\n\u{2022} Start template: \"start push day\"\n\u{2022} Check progress: \"how am I doing?\"\n\u{2022} Get insights: \"calories left\", \"daily summary\"\n\u{2022} Ask about: weight, sleep, biomarkers, glucose, supplements")
        }

        // Barcode scan
        if lower == "scan barcode" || lower == "scan food" || lower == "scan" || lower == "scan a product"
            || lower == "barcode" || lower.contains("scan barcode") {
            return .uiAction(.navigate(tab: 0), "Opening barcode scanner...")
        }

        // --- Gemma: only exact rule engine matches below this point ---

        // Exact rule engine (both models — pure data, no ambiguity)
        if lower == "daily summary" || lower == "summary" {
            return .handler { AIRuleEngine.dailySummary() }
        }
        if lower == "calories left" || lower == "calories left today" || lower == "how many calories left" {
            return .handler { AIRuleEngine.caloriesLeft() }
        }
        if lower == "yesterday" || lower == "what did i eat yesterday" {
            return .handler { AIRuleEngine.yesterdaySummary() }
        }
        if lower == "this week" || lower == "weekly summary" || lower == "how was my week" {
            return .handler { AIRuleEngine.weeklySummary() }
        }
        if lower == "supplements" || lower == "did i take my supplements" || lower == "supplement status" {
            return .handler { AIRuleEngine.supplementStatus() }
        }
        if lower == "what did i eat today" || lower == "what did i eat" || lower == "today's food" {
            return .handler {
                let context = AIContextBuilder.foodContext()
                return context.isEmpty ? "No food logged today yet." : context
            }
        }
        if lower == "how's my protein" || lower == "how's my protein?" || lower == "protein status"
            || lower == "how is my protein" || lower == "how is my protein?" || lower.contains("protein") && (lower.contains("how") || lower.contains("status")) {
            return .handler {
                let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
                guard n.proteinG > 0 else { return "No food logged yet. Log your meals to track protein." }
                if let goal = WeightGoal.load(), let targets = goal.macroTargets() {
                    let pLeft = max(0, Int(targets.proteinG - n.proteinG))
                    return "\(Int(n.proteinG))g protein today (\(Int(targets.proteinG))g target). \(pLeft > 0 ? "Still need \(pLeft)g." : "Target reached!")"
                }
                return "\(Int(n.proteinG))g protein today."
            }
        }

        // --- Deterministic overrides (both models) ---
        // These are exact-match or regex-parsed — no LLM quality benefit from Gemma handling them.

        // Copy yesterday
        if lower == "copy yesterday" || lower == "same as yesterday" || lower == "repeat yesterday"
            || lower == "log same as yesterday" || lower == "yesterday's food" {
            return .handler { FoodService.copyYesterday() }
        }

        // Workout count
        if lower.contains("how many workout") || lower.contains("workout count") || lower.contains("how often did i train")
            || lower.contains("workouts this week") || lower.contains("how many times did i work") {
            return .handler {
                let count = (try? WorkoutService.fetchWorkouts(limit: 7))?.filter {
                    guard let d = DateFormatters.dateOnly.date(from: $0.date) else { return false }
                    return Calendar.current.isDate(d, equalTo: Date(), toGranularity: .weekOfYear)
                }.count ?? 0
                var response = "\(count) workout\(count == 1 ? "" : "s") this week."
                if let streak = try? WorkoutService.workoutStreak() {
                    response += " Streak: \(streak.current) weeks (best: \(streak.longest))."
                }
                return response
            }
        }

        // Supplement taken
        let supplementVerbs = ["took my ", "took ", "had my ", "taken my ", "take my "]
        if let verb = supplementVerbs.first(where: { lower.hasPrefix($0) }) {
            let name = String(lower.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty && !["breakfast", "lunch", "dinner", "snack"].contains(name) {
                if let supplements = try? AppDatabase.shared.fetchActiveSupplements(),
                   supplements.contains(where: { $0.name.lowercased().contains(name.lowercased()) }) {
                    return .handler { SupplementService.markTaken(name: name) }
                }
            }
        }

        // Cheat meal
        let cheatPhrases = ["cheat meal", "cheat day", "ate out", "went off plan", "off track", "binge"]
        if cheatPhrases.contains(where: { lower.contains($0) }) {
            return .response("No judgment! What did you have? I'll log it for you.")
        }

        // Sugar query
        if lower.contains("sugar") && (lower.contains("how much") || lower.contains("today") || lower.contains("intake")) {
            return .handler {
                let n = (try? AppDatabase.shared.fetchDailyNutrition(for: DateFormatters.todayString)) ?? .zero
                var response = "\(Int(n.carbsG))g carbs today."
                if let goal = WeightGoal.load(), let targets = goal.macroTargets() {
                    response += " Target: \(Int(targets.carbsG))g."
                }
                response += " (Drift tracks total carbs — sugar isn't tracked separately.)"
                return response
            }
        }

        // Weekly comparison
        if lower.contains("this week") && (lower.contains("last") || lower.contains("compare") || lower.contains("vs")) {
            return .handler {
                let comparison = AIContextBuilder.comparisonContext()
                return comparison.isEmpty ? "Not enough data to compare weeks yet." : comparison
            }
        }

        // Workout suggestion
        let workoutQuestions = ["what should i train", "what should i do today", "suggest me workout",
                                 "suggest a workout", "suggest workout", "give me a workout",
                                 "recommend a workout", "recommend workout", "what workout",
                                 "what exercise", "recommend exercises", "give me exercises"]
        if workoutQuestions.contains(where: { lower.contains($0) }) {
            return .handler { ExerciseService.suggestWorkout() }
        }

        // Healthy meal suggestions
        let healthyFoodQuestions = ["what's healthy", "healthy meal", "healthy food", "healthy dinner",
                                     "healthy breakfast", "healthy lunch", "healthy snack",
                                     "what's good to eat", "what should i eat", "suggest food",
                                     "suggest meal", "suggest a meal", "what to eat", "need food ideas",
                                     "i'm hungry", "im hungry", "feeling hungry"]
        if healthyFoodQuestions.contains(where: { lower.contains($0) }) {
            return .handler {
                let totals = FoodService.getDailyTotals()
                var response = "\(totals.remaining > 0 ? "\(totals.remaining)" : "0") cal remaining."
                let suggestions = FoodService.suggestMeal()
                if !suggestions.isEmpty {
                    response += " Try: " + suggestions.prefix(3).map { "\($0.name) (\(Int($0.calories))cal, \(Int($0.proteinG))P)" }.joined(separator: ", ")
                }
                return response
            }
        }

        // Body comp entry
        let bfPattern = #"(?:body fat|bf|body fat %|bodyfat)\s*(?:is\s+)?(\d+\.?\d*)"#
        if let bfRegex = try? NSRegularExpression(pattern: bfPattern),
           let bfMatch = bfRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(bfMatch.range(at: 1), in: lower),
           let bf = Double(String(lower[numRange])), bf >= 3 && bf <= 60 {
            return .handler {
                var entry = BodyComposition(date: DateFormatters.todayString, bodyFatPct: bf,
                                             source: "manual", createdAt: DateFormatters.iso8601.string(from: Date()))
                try? AppDatabase.shared.saveBodyComposition(&entry)
                return "Logged body fat \(String(format: "%.1f", bf))%."
            }
        }
        let bmiPattern = #"bmi\s*(?:is\s+)?(\d+\.?\d*)"#
        if let bmiRegex = try? NSRegularExpression(pattern: bmiPattern),
           let bmiMatch = bmiRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(bmiMatch.range(at: 1), in: lower),
           let bmi = Double(String(lower[numRange])), bmi >= 12 && bmi <= 60 {
            return .handler {
                var entry = BodyComposition(date: DateFormatters.todayString, bmi: bmi,
                                             source: "manual", createdAt: DateFormatters.iso8601.string(from: Date()))
                try? AppDatabase.shared.saveBodyComposition(&entry)
                return "Logged BMI \(String(format: "%.1f", bmi))."
            }
        }

        // Set weight goal
        let goalPattern = #"(?:set goal to|target weight|i want to weigh|goal weight|my goal is)\s+(\d+\.?\d*)\s*(kg|lbs|lb|pounds?)?"#
        if let goalRegex = try? NSRegularExpression(pattern: goalPattern),
           let goalMatch = goalRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(goalMatch.range(at: 1), in: lower),
           let target = Double(String(lower[numRange])) {
            let unit: String
            if let unitRange = Range(goalMatch.range(at: 2), in: lower) {
                unit = String(lower[unitRange]).hasPrefix("kg") ? "kg" : "lbs"
            } else {
                unit = Preferences.weightUnit.rawValue
            }
            let targetKg = unit == "kg" ? target : target / 2.20462
            if targetKg >= 20 && targetKg <= 200 {
                return .handler {
                    let currentKg = (try? AppDatabase.shared.fetchWeightEntries())?.first?.weightKg ?? targetKg
                    var goal = WeightGoal.load() ?? WeightGoal(targetWeightKg: targetKg, monthsToAchieve: 6,
                        startDate: DateFormatters.todayString, startWeightKg: currentKg)
                    goal.targetWeightKg = targetKg
                    goal.save()
                    let display = unit == "kg" ? String(format: "%.1f kg", target) : String(format: "%.0f lbs", target)
                    return "Goal set to \(display)."
                }
            }
        }

        // Inline macros: "log 400 cal 30g protein lunch"
        let macroPattern = #"(\d+)\s*(?:cal|kcal).*?(\d+)\s*(?:g\s*)?(?:p(?:rotein)?)"#
        if let macroRegex = try? NSRegularExpression(pattern: macroPattern),
           let macroMatch = macroRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let calRange = Range(macroMatch.range(at: 1), in: lower),
           let protRange = Range(macroMatch.range(at: 2), in: lower),
           let cal = Int(String(lower[calRange])), let prot = Int(String(lower[protRange])),
           cal >= 50 && cal <= 5000 {
            // Extract optional carbs and fat
            var carbs = 0.0
            var fat = 0.0
            let carbPat = #"(\d+)\s*(?:g\s*)?(?:c(?:arbs?)?)"#
            if let cRegex = try? NSRegularExpression(pattern: carbPat),
               let cMatch = cRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let cRange = Range(cMatch.range(at: 1), in: lower) { carbs = Double(String(lower[cRange])) ?? 0 }
            let fatPat = #"(\d+)\s*(?:g\s*)?(?:f(?:at)?)"#
            if let fRegex = try? NSRegularExpression(pattern: fatPat),
               let fMatch = fRegex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
               let fRange = Range(fMatch.range(at: 1), in: lower) { fat = Double(String(lower[fRange])) ?? 0 }
            var meal: String? = nil
            for (kw, m) in [("breakfast", "breakfast"), ("lunch", "lunch"), ("dinner", "dinner"), ("snack", "snack")] {
                if lower.contains(kw) { meal = m; break }
            }
            return .handler {
                let today = DateFormatters.todayString
                let mealType = meal ?? { let h = Calendar.current.component(.hour, from: Date()); return h < 11 ? "breakfast" : h < 15 ? "lunch" : h < 21 ? "dinner" : "snack" }()
                do {
                    var mealLogs = try AppDatabase.shared.fetchMealLogs(for: today)
                    var mealLog = mealLogs.first { $0.mealType == mealType }
                    if mealLog == nil {
                        var newLog = MealLog(date: today, mealType: mealType)
                        try AppDatabase.shared.saveMealLog(&newLog)
                        mealLog = newLog
                    }
                    if let mlId = mealLog?.id {
                        var entry = FoodEntry(mealLogId: mlId, foodName: "Quick Add", servingSizeG: 0, servings: 1,
                                               calories: Double(cal), proteinG: Double(prot), carbsG: carbs, fatG: fat)
                        try AppDatabase.shared.saveFoodEntry(&entry)
                        return "Logged \(cal) cal, \(prot)P\(carbs > 0 ? " \(Int(carbs))C" : "")\(fat > 0 ? " \(Int(fat))F" : "") for \(mealType)."
                    }
                } catch {}
                return "Couldn't log macros. Try again."
            }
        }

        // Quick-add raw calories: "log 500 cal"
        let calPattern = #"(\d+)\s*(?:cal(?:ories?)?|kcal)"#
        if let regex = try? NSRegularExpression(pattern: calPattern),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let numRange = Range(match.range(at: 1), in: lower),
           let cal = Int(String(lower[numRange])), cal >= 50 && cal <= 5000 {
            var meal: String? = nil
            for (suffix, m) in [("breakfast", "breakfast"), ("lunch", "lunch"), ("dinner", "dinner"), ("snack", "snack")] {
                if lower.contains(suffix) { meal = m; break }
            }
            return .handler { FoodService.quickAddCalories(cal, meal: meal) }
        }

        // Add supplement: "add vitamin D", "add creatine 5g"
        if (lower.hasPrefix("add ") && (lower.contains("supplement") || lower.contains("vitamin") || lower.contains("to my stack")))
            || lower.hasPrefix("add creatine") || lower.hasPrefix("add fish oil") || lower.hasPrefix("add magnesium") {
            var name = lower.replacingOccurrences(of: "add ", with: "")
                .replacingOccurrences(of: " to my stack", with: "")
                .replacingOccurrences(of: " supplement", with: "")
                .trimmingCharacters(in: .whitespaces)
            var dosage: String? = nil
            let dosagePattern = #"\s+(\d+\s*(?:g|mg|iu|mcg|ml))\s*$"#
            if let dRegex = try? NSRegularExpression(pattern: dosagePattern, options: .caseInsensitive),
               let dMatch = dRegex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
               let dRange = Range(dMatch.range(at: 1), in: name) {
                dosage = String(name[dRange])
                name = String(name[..<dRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            if !name.isEmpty {
                return .handler { SupplementService.addSupplement(name: name, dosage: dosage) }
            }
        }

        // Completed activity (both models)
        let activityPrefixes = ["i did ", "i went ", "just did ", "just finished ", "did "]
        if let prefix = activityPrefixes.first(where: { lower.hasPrefix($0) }) {
            var activity = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            for suffix in [" today", " this morning", " this evening", " just now"] {
                if activity.hasSuffix(suffix) { activity = String(activity.dropLast(suffix.count)) }
            }
            var durationMin: Int? = nil
            let durPattern = #"^(\d+)\s*(?:min(?:ute)?s?)\s+"#
            if let durRegex = try? NSRegularExpression(pattern: durPattern),
               let durMatch = durRegex.firstMatch(in: activity, range: NSRange(activity.startIndex..., in: activity)),
               let numRange = Range(durMatch.range(at: 1), in: activity) {
                durationMin = Int(String(activity[numRange]))
                activity = String(activity[activity.index(activity.startIndex, offsetBy: durMatch.range.length)...]).trimmingCharacters(in: .whitespaces)
            }
            if !activity.isEmpty && activity.count > 2 {
                let name = activity.capitalized
                let durText = durationMin.map { " (\($0) min)" } ?? ""
                return .response("Log \(name)\(durText) for today? Say yes to confirm.")
            }
        }

        return nil
    }
}
