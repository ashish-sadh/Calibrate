import Foundation

/// Parses user messages for food/weight/workout intent and extracts parameters.
/// Used to pre-fill and launch native app views from the AI assistant.
enum AIActionExecutor {

    struct FoodIntent {
        let query: String
        let servings: Double?
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

        // Direct verb prefix: "log eggs", "ate chicken"
        let verbs = ["log ", "ate ", "had ", "add ", "track ", "logged ", "eating "]
        var remainder: String

        if let verb = verbs.first(where: { lower.hasPrefix($0) }) {
            remainder = String(lower.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        } else {
            // Natural phrasing: "I just had", "I ate", "just ate", "just had"
            let naturalPrefixes = ["i just had ", "i just ate ", "i had ", "i ate ", "just had ", "just ate ", "just logged "]
            guard let prefix = naturalPrefixes.first(where: { lower.hasPrefix($0) }) else { return nil }
            remainder = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        // Remove trailing qualifiers
        for suffix in [" for me", " please", " today", " for breakfast", " for lunch", " for dinner", " for snack"] {
            if remainder.hasSuffix(suffix) {
                remainder = String(remainder.dropLast(suffix.count))
            }
        }

        guard !remainder.isEmpty else { return nil }

        // Try to extract amount from the beginning
        let (amount, food) = extractAmount(from: remainder)

        guard !food.isEmpty else { return nil }
        return FoodIntent(query: food, servings: amount)
    }

    /// Try to parse a weight logging intent.
    /// "I weigh 165" → WeightIntent(165, lbs)
    /// "weight is 75.2 kg" → WeightIntent(75.2, kg)
    static func parseWeightIntent(_ text: String) -> WeightIntent? {
        let lower = text.lowercased()
        guard lower.contains("weigh") || lower.contains("weight is") || lower.contains("weight:")
              || lower.contains("weighed in") || lower.contains("scale says") || lower.contains("i'm at ")
              || lower.contains("log weight") || lower.contains("my weight") else { return nil }

        // Extract number
        let pattern = #"(\d+\.?\d*)\s*(kg|lbs|lb|pounds?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let numRange = Range(match.range(at: 1), in: lower),
              let value = Double(String(lower[numRange])) else { return nil }

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

        let verbs = ["log ", "ate ", "had ", "add ", "track ", "logged ", "eating "]
        let naturalPrefixes = ["i just had ", "i just ate ", "i had ", "i ate ", "just had ", "just ate "]
        var remainder: String

        if let verb = verbs.first(where: { lower.hasPrefix($0) }) {
            remainder = String(lower.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        } else if let prefix = naturalPrefixes.first(where: { lower.hasPrefix($0) }) {
            remainder = String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        } else {
            return nil
        }
        for suffix in [" for me", " please", " today", " for breakfast", " for lunch", " for dinner", " for snack"] {
            if remainder.hasSuffix(suffix) { remainder = String(remainder.dropLast(suffix.count)) }
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

        guard parts.count > 1 else { return nil } // Single item — use parseFoodIntent instead

        return parts.map { part in
            let (amount, food) = extractAmount(from: part)
            return FoodIntent(query: food, servings: amount)
        }
    }

    // MARK: - Food Search + AI Fallback

    struct FoodMatch {
        let food: Food
        let servings: Double
    }

    /// Search local DB for food with fuzzy matching. Returns best match or nil.
    static func findFood(query: String, servings: Double?) -> FoodMatch? {
        // Try exact search first
        if let results = try? AppDatabase.shared.searchFoodsRanked(query: query),
           let best = results.first {
            let queryWords = query.lowercased().split(separator: " ")
            let nameWords = best.name.lowercased()
            let matchCount = queryWords.filter { nameWords.contains($0) }.count
            if matchCount > 0 {
                return FoodMatch(food: best, servings: servings ?? 1)
            }
        }
        // Try without trailing 's' (eggs → egg, bananas → banana)
        let singular = query.hasSuffix("s") ? String(query.dropLast()) : query
        if singular != query,
           let results = try? AppDatabase.shared.searchFoodsRanked(query: singular),
           let best = results.first {
            return FoodMatch(food: best, servings: servings ?? 1)
        }
        // Try first word only (chicken breast → chicken)
        let firstWord = String(query.split(separator: " ").first ?? Substring(query))
        if firstWord != query && firstWord.count >= 3,
           let results = try? AppDatabase.shared.searchFoodsRanked(query: firstWord),
           let best = results.first {
            return FoodMatch(food: best, servings: servings ?? 1)
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
    private static func extractAmount(from text: String) -> (Double?, String) {
        let parts = text.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else { return (nil, text) }
        let firstStr = String(first)

        // Fraction: "1/3", "1/2"
        if firstStr.contains("/") {
            let fracParts = firstStr.split(separator: "/")
            if fracParts.count == 2, let num = Double(fracParts[0]), let den = Double(fracParts[1]), den > 0 {
                let food = parts.count > 1 ? String(parts[1]) : ""
                return (num / den, food.trimmingCharacters(in: .whitespaces))
            }
        }

        // Word amounts
        let wordAmounts: [String: Double] = ["half": 0.5, "quarter": 0.25, "one": 1, "two": 2, "three": 3, "a": 1, "an": 1]
        if let amount = wordAmounts[firstStr] {
            let food = parts.count > 1 ? String(parts[1]) : ""
            return (amount, food.trimmingCharacters(in: .whitespaces))
        }

        // Number: "2", "0.5", "200"
        if let num = Double(firstStr) {
            let food = parts.count > 1 ? String(parts[1]) : ""
            // If number is large (>10), it might be grams not servings — include with food name
            if num > 10 {
                return (nil, text) // "200g chicken" — let food search handle it
            }
            return (num, food.trimmingCharacters(in: .whitespaces))
        }

        // No amount found — entire text is food name
        return (nil, text)
    }
}
