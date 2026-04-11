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

        // Info queries (daily summary, calories left, yesterday, weekly, supplements, weight progress,
        // meal suggestions, "how am I doing", cross-domain, sleep) are NOT handled here.
        // They route through AIToolAgent → tool execution → LLM streaming presentation
        // for natural conversational responses. Only COMMANDS stay in StaticOverrides.

        // Barcode scan: "scan barcode", "scan food"
        let scanPatterns = ["scan barcode", "scan food", "scan a barcode", "barcode",
                             "scan something", "scan a food", "scan it"]
        if scanPatterns.contains(where: { lower == $0 || lower.hasPrefix($0) }) {
            return .uiAction(.navigate(tab: 0), "Opening barcode scanner...")
        }

        // Meal suggestions, general status, weight progress → routed through AIToolAgent for LLM presentation

        // Undo: "undo", "undo that", "undo last" — same as "delete last entry"
        if lower == "undo" || lower == "undo that" || lower == "undo last" {
            return .handler {
                let today = DateFormatters.todayString
                guard let entries = try? AppDatabase.shared.fetchFoodEntries(for: today),
                      let last = entries.first, let id = last.id else {
                    return "Nothing to undo."
                }
                try? AppDatabase.shared.deleteFoodEntry(id: id)
                return "Undone: removed \(last.foodName) (\(Int(last.calories * last.servings)) cal)."
            }
        }

        // Info queries (TDEE, "what did I eat", protein status, macro queries) now route
        // through AIToolAgent → IntentClassifier / ToolRanker → food_info / weight_info tools.
        // Removed from here to avoid duplicating logic and enable LLM presentation.

        // --- Deterministic overrides (both models) ---
        // These are exact-match or regex-parsed — no LLM quality benefit from Gemma handling them.

        // Calorie estimation ("calories in samosa") → food_info tool handles via FoodService.getNutrition()

        // Copy yesterday
        if lower == "copy yesterday" || lower == "same as yesterday" || lower == "repeat yesterday"
            || lower == "log same as yesterday" || lower == "yesterday's food" {
            return .handler { FoodService.copyYesterday() }
        }

        // Delete/remove food entry
        let deletePrefixes = ["delete ", "remove ", "undo "]
        if let prefix = deletePrefixes.first(where: { lower.hasPrefix($0) }) {
            let target = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if target == "last entry" || target == "last food" || target == "last" {
                return .handler {
                    let today = DateFormatters.todayString
                    guard let entries = try? AppDatabase.shared.fetchFoodEntries(for: today),
                          let last = entries.first, let id = last.id else {
                        return "No food entries today to delete."
                    }
                    try? AppDatabase.shared.deleteFoodEntry(id: id)
                    return "Deleted \(last.foodName) (\(Int(last.calories * last.servings)) cal)."
                }
            }
            // Delete by name: "remove the rice", "delete chicken"
            let cleanTarget = target.replacingOccurrences(of: "the ", with: "")
                .replacingOccurrences(of: "my ", with: "")
            if !cleanTarget.isEmpty && cleanTarget.count > 2 {
                return .handler {
                    let today = DateFormatters.todayString
                    guard let entries = try? AppDatabase.shared.fetchFoodEntries(for: today) else {
                        return "No food entries today."
                    }
                    if let match = entries.first(where: { $0.foodName.lowercased().contains(cleanTarget) }),
                       let id = match.id {
                        try? AppDatabase.shared.deleteFoodEntry(id: id)
                        return "Deleted \(match.foodName) (\(Int(match.calories * match.servings)) cal)."
                    }
                    return "Couldn't find '\(cleanTarget)' in today's food log."
                }
            }
        }

        // Workout count ("how many workouts this week") → exercise_info tool

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

        // Sugar/carbs, weekly comparison, workout suggestions → food_info/exercise_info tools

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

        // Set weight goal — resolve word numbers first ("one sixty" → "160")
        let goalInput = Self.resolveWordNumbers(lower)
        let goalPattern = #"(?:set (?:my )?goal to|target weight|i want to weigh|goal weight|my goal is)\s+(\d+\.?\d*)\s*(kg|lbs|lb|pounds?)?"#
        if let goalRegex = try? NSRegularExpression(pattern: goalPattern),
           let goalMatch = goalRegex.firstMatch(in: goalInput, range: NSRange(goalInput.startIndex..., in: goalInput)),
           let numRange = Range(goalMatch.range(at: 1), in: goalInput),
           let target = Double(String(goalInput[numRange])) {
            let unit: String
            if let unitRange = Range(goalMatch.range(at: 2), in: goalInput) {
                unit = String(goalInput[unitRange]).hasPrefix("kg") ? "kg" : "lbs"
            } else {
                unit = Preferences.weightUnit.rawValue
            }
            let targetKg = unit == "kg" ? target : target / 2.20462
            if targetKg >= 20 && targetKg <= 200 {
                return .handler {
                    let currentKg = WeightTrendService.shared.latestWeightKg ?? targetKg
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

        // Weekly comparison + cross-domain → routed through AIToolAgent for LLM presentation

        // Diet/fitness advice → food_info tool (LLM presents personalized advice with macro data)

        // Completed activity (both models)
        let activityPrefixes = ["i did ", "i went ", "just did ", "just finished ", "did "]
        if let prefix = activityPrefixes.first(where: { lower.hasPrefix($0) }) {
            var activity = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            for suffix in [" today", " this morning", " this evening", " just now"] {
                if activity.hasSuffix(suffix) { activity = String(activity.dropLast(suffix.count)) }
            }
            var durationMin: Int? = nil
            // Leading duration: "30 min yoga", "20 minutes cardio"
            let durPattern = #"^(\d+)\s*(?:min(?:ute)?s?)\s+"#
            if let durRegex = try? NSRegularExpression(pattern: durPattern),
               let durMatch = durRegex.firstMatch(in: activity, range: NSRange(activity.startIndex..., in: activity)),
               let numRange = Range(durMatch.range(at: 1), in: activity) {
                durationMin = Int(String(activity[numRange]))
                activity = String(activity[activity.index(activity.startIndex, offsetBy: durMatch.range.length)...]).trimmingCharacters(in: .whitespaces)
            }
            // Trailing duration: "yoga for 30 min", "yoga for like half an hour", "yoga for about 45 minutes"
            let trailingDur = #"\s+for\s+(?:like |about |roughly )?(\d+)\s*(?:min(?:ute)?s?|hrs?|hours?)"#
            if let tRegex = try? NSRegularExpression(pattern: trailingDur),
               let tMatch = tRegex.firstMatch(in: activity, range: NSRange(activity.startIndex..., in: activity)),
               let nRange = Range(tMatch.range(at: 1), in: activity) {
                let val = Int(String(activity[nRange])) ?? 0
                let fullRange = Range(tMatch.range, in: activity)!
                let unit = activity[fullRange].lowercased()
                durationMin = unit.contains("hr") || unit.contains("hour") ? val * 60 : val
                activity = String(activity[..<fullRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            // Word durations: "for half an hour" = 30, "for an hour" = 60
            let wordDurs: [(String, Int)] = [
                ("for like half an hour", 30), ("for half an hour", 30), ("for about half an hour", 30),
                ("for an hour", 60), ("for like an hour", 60), ("for about an hour", 60),
            ]
            for (phrase, mins) in wordDurs {
                if activity.hasSuffix(phrase) {
                    durationMin = mins
                    activity = String(activity.dropLast(phrase.count)).trimmingCharacters(in: .whitespaces)
                    break
                }
            }
            if !activity.isEmpty && activity.count > 2 {
                let name = activity.capitalized
                let durText = durationMin.map { " (\($0) min)" } ?? ""
                return .response("Log \(name)\(durText) for today? Say yes to confirm.")
            }
        }

        return nil
    }

    /// Convert word numbers to digits: "one sixty" → "160", "seventy five" → "75"
    private static func resolveWordNumbers(_ text: String) -> String {
        let tens: [String: Int] = ["twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
                                    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90]
        let ones: [String: Int] = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                                    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                                    "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
                                    "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19]
        let hundreds: [String: Int] = ["hundred": 100]

        let words = text.split(separator: " ").map { String($0) }
        var result = text
        var i = 0
        while i < words.count {
            let w = words[i].lowercased()
            var num: Int? = nil
            var consumed = 1

            // "one sixty" = 100 + 60, "one forty five" = 100 + 45
            if let o = ones[w], o <= 9, i + 1 < words.count {
                let next = words[i + 1].lowercased()
                if let t = tens[next] {
                    num = o * 100 + t
                    consumed = 2
                    // "one sixty five" = 165
                    if i + 2 < words.count, let o2 = ones[words[i + 2].lowercased()], o2 <= 9 {
                        num = (num ?? 0) + o2
                        consumed = 3
                    }
                } else if next == "hundred" {
                    num = o * 100
                    consumed = 2
                }
            }
            // "seventy five" = 75
            else if let t = tens[w] {
                num = t
                consumed = 1
                if i + 1 < words.count, let o = ones[words[i + 1].lowercased()], o <= 9 {
                    num = t + o
                    consumed = 2
                }
            }

            if let num {
                let origWords = words[i..<(i + consumed)].joined(separator: " ")
                result = result.replacingOccurrences(of: origWords, with: "\(num)")
                i += consumed
            } else {
                i += 1
            }
        }
        return result
    }
}
