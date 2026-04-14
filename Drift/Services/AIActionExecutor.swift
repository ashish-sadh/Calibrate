import Foundation

/// Parses user messages for food/weight/workout intent and extracts parameters.
/// Used to pre-fill and launch native app views from the AI assistant.
enum AIActionExecutor {

    struct FoodIntent {
        let query: String
        let servings: Double?
        var mealHint: String? = nil // "breakfast", "lunch", "dinner", "snack" if user specified
        var gramAmount: Double? = nil // "300 gram" → 300, used to calculate servings from food's serving size
    }

    struct WeightIntent {
        let weightValue: Double
        let unit: WeightUnit
    }

    /// Try to parse a food logging intent from natural language.
    /// "log 1/3 avocado" → FoodIntent(query: "avocado", servings: 0.33)
    /// "ate 2 eggs" → FoodIntent(query: "eggs", servings: 2)
    /// "had chicken breast" → FoodIntent(query: "chicken breast", servings: nil)
    static func parseFoodIntent(_ text: String) -> FoodIntent? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

        // Strip conversational openers: "i want to log X" → "log X"
        var workingText = lower
        let conversationalPrefixes = ["i want to ", "i'd like to ", "can you ", "could you ", "can i ", "please ", "let me ", "help me "]
        for cp in conversationalPrefixes {
            if workingText.hasPrefix(cp) {
                workingText = String(workingText.dropFirst(cp.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        // Direct verb prefix: "log eggs", "ate chicken"
        let verbs = ["log ", "ate ", "had ", "add ", "track ", "logged ", "eating ", "drank ", "drinking ", "made "]
        var remainder: String

        if let verb = verbs.first(where: { workingText.hasPrefix($0) }) {
            remainder = String(workingText.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        } else {
            // Natural phrasing: "I just had", "I ate", "just ate", "just had"
            let naturalPrefixes = ["i just had ", "i just ate ", "i had ", "i ate ", "just had ", "just ate ", "just logged ",
                                     "i'm having ", "i'm eating ", "snacked on ", "i drank ", "just drank ", "i made "]
            guard let prefix = naturalPrefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
            remainder = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        // Strip possessive: "my avocado" → "avocado"
        if remainder.hasPrefix("my ") { remainder = String(remainder.dropFirst(3)) }

        // Remove trailing qualifiers and detect meal hint
        var mealHint: String? = nil
        let mealSuffixes: [(String, String)] = [
            (" for breakfast", "breakfast"), (" for lunch", "lunch"),
            (" for dinner", "dinner"), (" for snack", "snack")
        ]
        for (suffix, meal) in mealSuffixes {
            if remainder.hasSuffix(suffix) {
                remainder = String(remainder.dropLast(suffix.count))
                mealHint = meal
                break
            }
        }
        for suffix in [" for me", " please", " today"] {
            if remainder.hasSuffix(suffix) { remainder = String(remainder.dropLast(suffix.count)) }
        }

        guard !remainder.isEmpty else { return nil }

        let (amount, food, grams) = extractAmount(from: remainder)
        guard !food.isEmpty else { return nil }

        // Reject non-food words that get caught by "log" prefix
        let nonFoodWords: Set<String> = [
            "exercise", "workout", "a workout", "weight", "sleep", "supplement",
            "supplements", "recovery", "template", "a template", "my weight",
            "breakfast", "lunch", "dinner", "snack", // meal names → ask follow-up
        ]
        if nonFoodWords.contains(food.lowercased()) { return nil }

        return FoodIntent(query: food, servings: amount, mealHint: mealHint, gramAmount: grams)
    }

    /// Try to parse a weight logging intent.
    /// "I weigh 165" → WeightIntent(165, lbs)
    /// "weight is 75.2 kg" → WeightIntent(75.2, kg)
    static func parseWeightIntent(_ text: String) -> WeightIntent? {
        let lower = text.lowercased()
        guard lower.contains("i weigh") || lower.contains("weight is") || lower.contains("weight:")
              || lower.contains("weighed in") || lower.contains("scale says") || lower.contains("i'm at ")
              || lower.contains("log weight") || lower.contains("my weight") else { return nil }

        // Extract number
        let pattern = #"(\d+\.?\d*)\s*(kg|lbs|lb|pounds?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let numRange = Range(match.range(at: 1), in: lower),
              let value = Double(String(lower[numRange])) else { return nil }

        // Sanity check: body weight should be in reasonable range
        // Prevents "chicken weighs 200g" from logging 200 as body weight
        if value < 20 || value > 500 { return nil }

        // Detect unit
        let unit: WeightUnit
        if let unitRange = Range(match.range(at: 2), in: lower) {
            let unitStr = String(lower[unitRange])
            unit = unitStr.hasPrefix("kg") ? .kg : .lbs
        } else {
            unit = Preferences.weightUnit // default to user's preference
        }

        return WeightIntent(weightValue: value, unit: unit)
    }

    // MARK: - Multi-Food Parsing

    /// Parse multiple food items: "log chicken and rice" → [FoodIntent("chicken"), FoodIntent("rice")]
    static func parseMultiFoodIntent(_ text: String) -> [FoodIntent]? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)

        // Strip conversational openers: "i want to log X and Y" → "log X and Y"
        var workingText = lower
        let conversationalPrefixes = ["i want to ", "i'd like to ", "can you ", "could you ", "can i ", "please ", "let me ", "help me "]
        for cp in conversationalPrefixes {
            if workingText.hasPrefix(cp) {
                workingText = String(workingText.dropFirst(cp.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        let verbs = ["log ", "ate ", "had ", "add ", "track ", "logged ", "eating ", "drank ", "drinking ", "made "]
        let naturalPrefixes = ["i just had ", "i just ate ", "i had ", "i ate ", "just had ", "just ate ",
                               "i'm having ", "i'm eating ", "snacked on ", "i drank ", "just drank ", "i made "]
        var remainder: String

        if let verb = verbs.first(where: { workingText.hasPrefix($0) }) {
            remainder = String(workingText.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        } else if let prefix = naturalPrefixes.first(where: { lower.hasPrefix($0) }) {
            remainder = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }

        // Strip possessive: "my eggs and toast" → "eggs and toast"
        if remainder.hasPrefix("my ") { remainder = String(remainder.dropFirst(3)) }
        for suffix in [" for me", " please", " today", " for breakfast", " for lunch", " for dinner", " for snack"] {
            if remainder.hasSuffix(suffix) { remainder = String(remainder.dropLast(suffix.count)) }
        }

        // Strip trailing conversational noise: "eggs and coffee can you help me log" → "eggs and coffee"
        for brk in [" can you ", " please help ", " help me ", " could you "] {
            if let range = remainder.range(of: brk) {
                remainder = String(remainder[..<range.lowerBound])
                break
            }
        }
        guard !remainder.isEmpty else { return nil }

        // Check for compound foods that contain "and" (don't split these)
        let compoundFoods = ["mac and cheese", "bread and butter", "salt and pepper", "rice and beans",
                             "peanut butter and jelly", "fish and chips", "ham and cheese"]
        if compoundFoods.contains(where: { remainder.contains($0) }) {
            return nil // Treat as single food
        }

        // Split on separators
        var parts = [remainder]
        for sep in [", and ", " and ", ", "] {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // Secondary split: "one avocado two eggs" → ["one avocado", "two eggs"]
        // Handles implicit lists without "and" where a word-number appears mid-string
        let implicitCountWords = ["two ", "three ", "four ", "five ", "six ", "seven ", "eight ", "nine ", "ten "]
        parts = parts.flatMap { part -> [String] in
            for num in implicitCountWords {
                if let range = part.range(of: " \(num)") {
                    let before = String(part[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let after = (num + String(part[range.upperBound...])).trimmingCharacters(in: .whitespaces)
                    if !before.isEmpty && !after.isEmpty { return [before, after] }
                }
            }
            return [part]
        }

        guard parts.count > 1 else { return nil } // Single item — use parseFoodIntent instead

        let intents = parts.compactMap { part -> FoodIntent? in
            let (amount, food, grams) = extractAmount(from: part)
            guard !food.isEmpty else { return nil }
            return FoodIntent(query: food, servings: amount, gramAmount: grams)
        }
        return intents.count > 1 ? intents : nil
    }

    // MARK: - Food Search + AI Fallback

    struct FoodMatch {
        let food: Food
        let servings: Double
    }

    /// Search local DB for food. If gram amount is provided, converts to servings using food's serving size.
    static func findFood(query: String, servings: Double?, gramAmount: Double? = nil) -> FoodMatch? {
        // Helper: calculate servings from gram amount if applicable
        func resolveServings(for food: Food) -> Double {
            if let grams = gramAmount, food.servingSize > 0 {
                return grams / food.servingSize
            }
            return servings ?? 1
        }

        // Try singular first for better matches: "bananas" → "banana" (avoids "TJ's Gone Bananas")
        let singular = query.hasSuffix("s") && query.count > 3 ? String(query.dropLast()) : query
        let searchQueries = singular != query ? [singular, query] : [query]

        for searchQuery in searchQueries {
            if let results = try? AppDatabase.shared.searchFoodsRanked(query: searchQuery),
               let best = results.first {
                // Prefer foods whose name closely matches the query (not just contains)
                let queryWords = searchQuery.lowercased().split(separator: " ")
                let nameWords = best.name.lowercased()
                let matchCount = queryWords.filter { nameWords.contains($0) }.count
                if matchCount > 0 {
                    return FoodMatch(food: best, servings: resolveServings(for: best))
                }
            }
        }
        // Try spell correction: "bannana" → "banana", "chiken" → "chicken"
        let corrected = SpellCorrectService.correct(query)
        if corrected != query,
           let results = try? AppDatabase.shared.searchFoodsRanked(query: corrected),
           let best = results.first {
            return FoodMatch(food: best, servings: resolveServings(for: best))
        }

        // Try stripping qualifiers: "slices of pizza" → "pizza", "cups of rice" → "rice"
        let qualifiers = ["slices of ", "slice of ", "pieces of ", "piece of ", "cups of ", "cup of ",
                          "bowls of ", "bowl of ", "glasses of ", "glass of ", "servings of ", "serving of ",
                          "portions of ", "portion of ", "plate of ", "plates of ", "some ", "handful of ", "scoop of "]
        for qual in qualifiers {
            if query.lowercased().hasPrefix(qual) {
                let stripped = String(query.dropFirst(qual.count))
                if let results = try? AppDatabase.shared.searchFoodsRanked(query: stripped),
                   let best = results.first {
                    return FoodMatch(food: best, servings: resolveServings(for: best))
                }
            }
        }
        // Try first word only (chicken breast → chicken)
        let firstWord = String(query.split(separator: " ").first ?? Substring(query))
        if firstWord != query && firstWord.count >= 3,
           let results = try? AppDatabase.shared.searchFoodsRanked(query: firstWord),
           let best = results.first {
            return FoodMatch(food: best, servings: resolveServings(for: best))
        }
        return nil
    }

    /// Try to find food with AI normalization: "PBJ" → "peanut butter sandwich" → local search.
    static func findFoodWithAI(query: String, servings: Double?) async -> FoodMatch? {
        // Try local first
        if let match = findFood(query: query, servings: servings) { return match }

        guard Preferences.aiEnabled, await LocalAIService.shared.isModelLoaded else { return nil }

        let prompt = "What food is '\(query)'? Reply with ONLY the common food name, nothing else."
        let normalized = await LocalAIService.shared.respond(to: prompt)
        let cleaned = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\"", with: "")

        if !cleaned.isEmpty && cleaned != query.lowercased() {
            return findFood(query: cleaned, servings: servings)
        }
        return nil
    }

    /// Ask the LLM to estimate nutrition for an unknown food.
    /// Returns a prompt that will get structured nutrition data back.
    static func nutritionEstimationPrompt(food: String, servings: Double?) -> String {
        let servingsText = servings.map { String(format: "%.1f servings of", $0) } ?? "1 serving of"
        return """
        Estimate nutrition for \(servingsText) \(food). \
        Reply ONLY in this exact format, nothing else: \
        NUTRITION|\(food)|calories|protein_g|carbs_g|fat_g|fiber_g|serving_size_g
        Example: NUTRITION|avocado|80|1|4|7|3|50
        """
    }

    /// Parse "NUTRITION|name|cal|p|c|f|fiber|serving_g" from LLM response.
    static func parseNutritionEstimate(_ response: String) -> (name: String, cal: Double, p: Double, c: Double, f: Double, fiber: Double, servingG: Double)? {
        let lines = response.components(separatedBy: .newlines)
        guard let line = lines.first(where: { $0.hasPrefix("NUTRITION|") }) else { return nil }
        let parts = line.split(separator: "|")
        guard parts.count >= 8 else { return nil }
        guard let cal = Double(parts[2]),
              let p = Double(parts[3]),
              let c = Double(parts[4]),
              let f = Double(parts[5]),
              let fiber = Double(parts[6]),
              let servingG = Double(parts[7]) else { return nil }
        return (name: String(parts[1]), cal: cal, p: p, c: c, f: f, fiber: fiber, servingG: servingG)
    }

    // MARK: - Amount Parsing

    /// Extract amount from beginning of string: "1/3 avocado" → (0.33, "avocado")
    /// Also returns gram amount separately: "paneer biryani 300 gram" → (nil, "paneer biryani", 300)
    static func extractAmount(from text: String) -> (Double?, String, Double?) {
        // "NUMBER UNIT of FOOD": "100 gram of rice", "2 cups of dal", "200 oz of daal"
        let gramUnitsLeading: Set<String> = ["g", "gram", "grams", "gm", "oz", "ml", "kg"]
        let countUnitsLeading: Set<String> = ["scoop", "scoops", "tbsp", "tsp", "cup", "cups",
                                               "piece", "pieces", "slice", "slices", "serving", "servings",
                                               "portion", "portions"]
        let leadingWords = text.split(separator: " ").map(String.init)
        if leadingWords.count >= 3, let num = Double(leadingWords[0]) {
            let unit = leadingWords[1].lowercased()
            let isGramUnit = gramUnitsLeading.contains(unit)
            let isCountUnit = countUnitsLeading.contains(unit)
            if isGramUnit || isCountUnit {
                var foodStart = 2
                if leadingWords.count > 3 && leadingWords[2].lowercased() == "of" { foodStart = 3 }
                let food = leadingWords[foodStart...].joined(separator: " ")
                if !food.isEmpty {
                    if isGramUnit {
                        return (nil, food.trimmingCharacters(in: .whitespaces), num)
                    } else {
                        return (num, food.trimmingCharacters(in: .whitespaces), nil)
                    }
                }
            }
        }

        // Compact leading: "200ml milk", "100g chicken", "300g rice"
        if leadingWords.count >= 2 {
            let first = leadingWords[0].lowercased()
            for unit in gramUnitsLeading {
                if first.hasSuffix(unit), let num = Double(first.dropLast(unit.count)) {
                    let food = leadingWords[1...].joined(separator: " ")
                    return (nil, food.trimmingCharacters(in: .whitespaces), num)
                }
            }
        }

        // Word amount + unit: "half cup oats", "quarter cup rice"
        let wordAmountsLeading: [String: Double] = ["half": 0.5, "quarter": 0.25, "one": 1, "two": 2, "three": 3]
        if leadingWords.count >= 3, let amt = wordAmountsLeading[leadingWords[0].lowercased()] {
            let unit = leadingWords[1].lowercased()
            let isGramUnit = gramUnitsLeading.contains(unit)
            let isCountUnit = countUnitsLeading.contains(unit)
            if isGramUnit || isCountUnit {
                var foodStart = 2
                if leadingWords.count > 3 && leadingWords[2].lowercased() == "of" { foodStart = 3 }
                let food = leadingWords[foodStart...].joined(separator: " ")
                if !food.isEmpty {
                    if isGramUnit { return (nil, food.trimmingCharacters(in: .whitespaces), amt) }
                    else { return (amt, food.trimmingCharacters(in: .whitespaces), nil) }
                }
            }
        }

        // Multi-word amounts first
        let multiWord: [(String, Double)] = [("a couple of ", 2), ("couple of ", 2), ("a few ", 3), ("a lot of ", 2), ("lots of ", 2)]
        for (prefix, amount) in multiWord {
            if text.lowercased().hasPrefix(prefix) {
                return (amount, String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces), nil)
            }
        }

        // Trailing quantity: "paneer biryani 300 gram", "chicken 200g", "fairlife protein 2 scoop"
        let weightUnits: Set<String> = ["g", "gram", "grams", "gm", "oz", "ml", "kg",
                                         "scoop", "scoops", "tbsp", "tsp", "cup", "cups",
                                         "piece", "pieces", "slice", "slices", "serving", "servings"]
        let allWords = text.split(separator: " ").map(String.init)
        if allWords.count >= 3 {
            let lastWord = allWords.last!.lowercased()
            let secondLast = allWords[allWords.count - 2]
            if weightUnits.contains(lastWord), let grams = Double(secondLast) {
                let food = allWords[0..<(allWords.count - 2)].joined(separator: " ")
                if !food.isEmpty {
                    return (nil, food.trimmingCharacters(in: .whitespaces), grams)
                }
            }
        }
        // Trailing compact: "chicken 200g", "rice 300ml"
        if allWords.count >= 2 {
            let lastWord = allWords.last!.lowercased()
            for unit in weightUnits {
                if lastWord.hasSuffix(unit), let grams = Double(lastWord.dropLast(unit.count)) {
                    let food = allWords[0..<(allWords.count - 1)].joined(separator: " ")
                    if !food.isEmpty {
                        return (nil, food.trimmingCharacters(in: .whitespaces), grams)
                    }
                }
            }
        }

        let parts = text.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else { return (nil, text, nil) }
        let firstStr = String(first)

        // Fraction: "1/3", "1/2"
        if firstStr.contains("/") {
            let fracParts = firstStr.split(separator: "/")
            if fracParts.count == 2, let num = Double(fracParts[0]), let den = Double(fracParts[1]), den > 0 {
                let food = parts.count > 1 ? String(parts[1]) : ""
                return (num / den, food.trimmingCharacters(in: .whitespaces), nil)
            }
        }

        // Word amounts
        let wordAmounts: [String: Double] = [
            "half": 0.5, "quarter": 0.25, "third": 1.0/3, "sixth": 1.0/6, "eighth": 0.125,
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "a": 1, "an": 1, "the": 1, "couple": 2, "few": 3, "several": 4, "some": 1
        ]
        if let amount = wordAmounts[firstStr] {
            let food = parts.count > 1 ? String(parts[1]) : ""
            return (amount, food.trimmingCharacters(in: .whitespaces), nil)
        }

        // Leading number with unit: "200g chicken" → strip unit, treat as gram amount
        let leadingLower = firstStr.lowercased()
        for unit in weightUnits {
            if leadingLower.hasSuffix(unit), let grams = Double(leadingLower.dropLast(unit.count)) {
                let food = parts.count > 1 ? String(parts[1]) : ""
                return (nil, food.trimmingCharacters(in: .whitespaces), grams)
            }
        }

        // Range: "2 to 3 bananas", "1 or 2 eggs" → take the higher number
        if let num1 = Double(firstStr), leadingWords.count >= 4 {
            let connector = leadingWords[1].lowercased()
            if (connector == "to" || connector == "or" || connector == "-"),
               let num2 = Double(leadingWords[2]) {
                let food = leadingWords[3...].joined(separator: " ")
                let higher = max(num1, num2)
                return (higher, food.trimmingCharacters(in: .whitespaces), nil)
            }
        }

        // Number: "2", "0.5", "200"
        if let num = Double(firstStr) {
            let food = parts.count > 1 ? String(parts[1]) : ""
            // If number is large (>10), it might be grams not servings — include with food name
            if num > 10 {
                return (nil, text, nil) // "200g chicken" — let food search handle it
            }
            return (num, food.trimmingCharacters(in: .whitespaces), nil)
        }

        // Mid-string number: "protein 2 scoop" → food="protein", amount=2
        // "fairlife protein with 2 scoop" → strip "with" → food="fairlife protein", amount=2
        let connectors: Set<String> = ["with", "of", "and", "plus", "w/", "x"]
        for i in 1..<allWords.count {
            if let num = Double(allWords[i]), num > 0, num <= 10 {
                var foodWords = Array(allWords[0..<i])
                // Strip trailing connectors: "fairlife protein with" → "fairlife protein"
                while let last = foodWords.last, connectors.contains(last.lowercased()) {
                    foodWords.removeLast()
                }
                let food = foodWords.joined(separator: " ")
                if !food.isEmpty {
                    return (num, food.trimmingCharacters(in: .whitespaces), nil)
                }
            }
        }

        // No amount found — entire text is food name
        return (nil, text, nil)
    }
}
