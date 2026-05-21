import Foundation

/// Parses user messages for food/weight/workout intent and extracts parameters.
/// Pure parsing logic — no database, no LLM, no UI.
/// `FoodIntent` lives in `Models/FoodIntent.swift` so Domain parsers
/// (`ComposedFoodParser`) can produce it without depending on AI.
public enum AIActionExecutor {

    public struct WeightIntent: Sendable {
        public let weightValue: Double
        public let unit: WeightUnit

        public init(weightValue: Double, unit: WeightUnit) {
            self.weightValue = weightValue
            self.unit = unit
        }
    }

    // MARK: - Verb / Prefix Stripping (shared by parseFoodIntent + parseMultiFoodIntent)

    /// Conversational openers that wrap a logging intent — stripped first.
    /// "i want to log eggs" → "log eggs"
    private static let conversationalPrefixes = [
        "i want to ", "i'd like to ", "i'd to ",
        "can you ", "could you ", "can i ", "please ", "let me ", "help me "
    ]

    /// Imperative logging verbs at the start of the (possibly already-stripped) text.
    private static let foodVerbs = [
        "log ", "ate ", "had ", "add ", "track ", "logged ",
        "eating ", "drank ", "drinking ", "made "
    ]

    /// First-person past/present-tense leads that don't take a verb prefix.
    /// Checked against the ORIGINAL (pre-conversational-strip) text — "can you I had X"
    /// is intentionally rejected (asking, not logging).
    private static let foodNaturalPrefixes = [
        "i just had ", "i just ate ", "i had ", "i ate ",
        "just had ", "just ate ", "just logged ",
        "i'm having ", "i'm eating ", "snacked on ",
        "i drank ", "just drank ", "i made "
    ]

    /// Strip a food-logging verb or natural prefix; return the food remainder.
    /// Returns nil if no recognized lead.
    private static func stripFoodLead(_ text: String) -> String? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        var workingText = lower

        for cp in conversationalPrefixes where workingText.hasPrefix(cp) {
            workingText = String(workingText.dropFirst(cp.count)).trimmingCharacters(in: .whitespaces)
            break
        }

        if let verb = foodVerbs.first(where: { workingText.hasPrefix($0) }) {
            return String(workingText.dropFirst(verb.count)).trimmingCharacters(in: .whitespaces)
        }

        if let prefix = foodNaturalPrefixes.first(where: { lower.hasPrefix($0) }) {
            return String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }

        return nil
    }

    /// Try to parse a food logging intent from natural language.
    /// "log 1/3 avocado" → FoodIntent(query: "avocado", servings: 0.33)
    /// "ate 2 eggs" → FoodIntent(query: "egg", servings: 2)
    public static func parseFoodIntent(_ text: String) -> FoodIntent? {
        guard var remainder = stripFoodLead(text) else { return nil }

        if remainder.hasPrefix("my ") { remainder = String(remainder.dropFirst(3)) }

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

        let nonFoodWords: Set<String> = [
            "exercise", "workout", "a workout", "weight", "sleep", "supplement",
            "supplements", "recovery", "template", "a template", "my weight",
            "breakfast", "lunch", "dinner", "snack",
            "summary", "daily summary", "weekly summary", "today", "yesterday",
        ]
        if nonFoodWords.contains(food.lowercased()) { return nil }

        // Singularize food name for better DB matching: "eggs"→"egg", "bananas"→"banana"
        let foodQuery = food.hasSuffix("s") && food.count > 3 ? String(food.dropLast()) : food
        return FoodIntent(query: foodQuery, servings: amount, mealHint: mealHint, gramAmount: grams)
    }

    /// Try to parse a weight logging intent.
    /// `defaultUnit` is used when the input has no explicit unit. Default is `.lbs`;
    /// callers in iOS pass `Preferences.weightUnit` to honor user preference.
    public static func parseWeightIntent(_ text: String, defaultUnit: WeightUnit = .lbs) -> WeightIntent? {
        let lower = text.lowercased()
        guard lower.contains("i weigh") || lower.contains("weight is") || lower.contains("weight:")
              || lower.contains("weighed in") || lower.contains("scale says") || lower.contains("i'm at ")
              || lower.contains("log weight") || lower.contains("my weight") else { return nil }

        let pattern = #"(\d+\.?\d*)\s*(kg|lbs|lb|pounds?)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let numRange = Range(match.range(at: 1), in: lower),
              let value = Double(String(lower[numRange])) else { return nil }

        // Sanity check: prevents "chicken weighs 200g" from logging 200 as body weight
        if value < 20 || value > 500 { return nil }

        let unit: WeightUnit
        if let unitRange = Range(match.range(at: 2), in: lower) {
            let unitStr = String(lower[unitRange])
            unit = unitStr.hasPrefix("kg") ? .kg : .lbs
        } else {
            unit = defaultUnit
        }

        return WeightIntent(weightValue: value, unit: unit)
    }

    /// Parse multiple food items: "log chicken and rice" → [FoodIntent("chicken"), FoodIntent("rice")]
    public static func parseMultiFoodIntent(_ text: String) -> [FoodIntent]? {
        guard var remainder = stripFoodLead(text) else { return nil }

        if remainder.hasPrefix("my ") { remainder = String(remainder.dropFirst(3)) }
        for suffix in [" for me", " please", " today", " for breakfast", " for lunch", " for dinner", " for snack"] {
            if remainder.hasSuffix(suffix) { remainder = String(remainder.dropLast(suffix.count)) }
        }

        for brk in [" can you ", " please help ", " help me ", " could you "] {
            if let range = remainder.range(of: brk) {
                remainder = String(remainder[..<range.lowerBound])
                break
            }
        }
        guard !remainder.isEmpty else { return nil }

        let compoundFoods = ["mac and cheese", "bread and butter", "salt and pepper", "rice and beans",
                             "peanut butter and jelly", "fish and chips", "ham and cheese"]
        if compoundFoods.contains(where: { remainder.contains($0) }) {
            return nil
        }

        var parts = [remainder]
        for sep in [", and ", " and ", ", "] {
            parts = parts.flatMap { $0.components(separatedBy: sep) }
        }
        parts = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

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

        guard parts.count > 1 else { return nil }

        let intents = parts.compactMap { part -> FoodIntent? in
            let (amount, food, grams) = extractAmount(from: part)
            guard !food.isEmpty else { return nil }
            return FoodIntent(query: food, servings: amount, gramAmount: grams)
        }
        return intents.count > 1 ? intents : nil
    }

    /// Ask the LLM to estimate nutrition for an unknown food.
    /// Returns a prompt that will get structured nutrition data back.
    public static func nutritionEstimationPrompt(food: String, servings: Double?) -> String {
        let servingsText = servings.map { String(format: "%.1f servings of", $0) } ?? "1 serving of"
        return """
        Estimate nutrition for \(servingsText) \(food). \
        Reply ONLY in this exact format, nothing else: \
        NUTRITION|\(food)|calories|protein_g|carbs_g|fat_g|fiber_g|serving_size_g
        Example: NUTRITION|avocado|80|1|4|7|3|50
        """
    }

    /// Parse "NUTRITION|name|cal|p|c|f|fiber|serving_g" from LLM response.
    public static func parseNutritionEstimate(_ response: String) -> (name: String, cal: Double, p: Double, c: Double, f: Double, fiber: Double, servingG: Double)? {
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

    /// Converts a numeric amount + unit string to grams (flat constants, no food context).
    /// Returns nil for pure count units (scoop, piece, serving) that stay as servings.
    static func normalizeToGrams(_ amount: Double, unit: String) -> Double? {
        switch unit {
        case "g", "gram", "grams", "gm": return amount
        case "oz", "ounce", "ounces": return amount * 28.3495
        case "fl oz", "floz", "fluid oz", "fluid ounce", "fluid ounces": return amount * 29.5735
        case "kg": return amount * 1000
        case "ml": return amount
        case "cup", "cups": return amount * 240
        case "tbsp", "tablespoon", "tablespoons": return amount * 15
        case "tsp", "teaspoon", "teaspoons": return amount * 5
        default: return nil
        }
    }

    /// Food-aware conversion: uses RawIngredient density for cups/tbsp/tsp/pieces.
    /// Falls back to flat constants for unrecognised foods.
    static func normalizeToGrams(_ amount: Double, unit: String, foodHint: String) -> Double? {
        switch unit {
        case "cup", "cups", "tbsp", "tablespoon", "tablespoons", "tsp", "teaspoon", "teaspoons":
            if let ingredient = matchIngredient(for: foodHint.lowercased()) {
                switch unit {
                case "cup", "cups":
                    return amount * ingredient.gramsPerCup
                case "tbsp", "tablespoon", "tablespoons":
                    return amount * ingredient.gramsPerCup / 16
                default:
                    return amount * ingredient.gramsPerCup / 48
                }
            }
            return normalizeToGrams(amount, unit: unit)
        case "piece", "pieces":
            let knownPieceFoods: Set<RawIngredient> = [.egg, .banana, .apple, .potato, .onion, .tomato]
            if let ingredient = matchIngredient(for: foodHint.lowercased()),
               knownPieceFoods.contains(ingredient) {
                return amount * ingredient.gramsPerPiece
            }
            return nil
        default:
            return normalizeToGrams(amount, unit: unit)
        }
    }

    private static func matchIngredient(for food: String) -> RawIngredient? {
        let words = Set(food.split(whereSeparator: { !$0.isLetter }).map { String($0) })
        if food.contains("oat") { return .oats }
        if food.contains("rice") && !food.contains("cake") && !food.contains("cracker") { return .rice }
        if food.contains("wheat flour") || food.contains("atta") || food.contains("maida") { return .wheat_flour }
        if food.contains("sugar") { return .sugar }
        if words.contains("oil") { return .oil }
        if food.contains("ghee") { return .ghee }
        if food.contains("butter") && !food.contains("peanut") && !food.contains("almond") && !food.contains("chicken") { return .butter }
        if food.contains("milk") { return .milk }
        if food.contains("chicken") { return .chicken_raw }
        if food.contains("egg") { return .egg }
        if food.contains("paneer") { return .paneer }
        if food.contains("tofu") { return .tofu }
        if food.contains("lentil") || food.contains("dal") || food.contains("daal") { return .lentils }
        if food.contains("chickpea") || food.contains("chole") || food.contains("chana") { return .chickpeas }
        if food.contains("potato") { return .potato }
        if food.contains("onion") { return .onion }
        if food.contains("tomato") { return .tomato }
        if food.contains("spinach") { return .spinach }
        if food.contains("banana") { return .banana }
        if food.contains("apple") && !food.contains("juice") && !food.contains("sauce") { return .apple }
        if food.contains("peanut") && !food.contains("butter") { return .peanuts }
        if food.contains("almond") && !food.contains("butter") && !food.contains("milk") { return .almonds }
        if food.contains("cashew") && !food.contains("butter") { return .cashews }
        if food.contains("honey") { return .honey }
        return nil
    }

    /// Extract amount from beginning of string: "1/3 avocado" → (0.33, "avocado")
    /// Also converts weight/volume units: "2 oz chicken" → (nil, "chicken", 56.7),
    /// "1 cup oats" → (nil, "oats", 240), "1 tbsp peanut butter" → (nil, "peanut butter", 15).
    /// Multiplier keywords: "double the chicken" → (2.0, "chicken", nil).
    public static func extractAmount(from text: String) -> (Double?, String, Double?) {
        let weightAndVolumeUnits: Set<String> = ["g", "gram", "grams", "gm",
                                                   "oz", "ounce", "ounces",
                                                   "ml", "kg",
                                                   "cup", "cups",
                                                   "tbsp", "tablespoon", "tablespoons",
                                                   "tsp", "teaspoon", "teaspoons"]
        let countUnitsLeading: Set<String> = ["scoop", "scoops", "piece", "pieces", "slice", "slices",
                                               "serving", "servings", "portion", "portions"]
        let leadingWords = text.split(separator: " ").map(String.init)

        let multiplierWords: [String: Double] = ["double": 2.0, "twice": 2.0, "triple": 3.0, "2x": 2.0, "3x": 3.0]
        if let first = leadingWords.first, let multiplier = multiplierWords[first.lowercased()] {
            var rest = Array(leadingWords.dropFirst())
            if let next = rest.first, ["the", "a", "an", "my"].contains(next.lowercased()) {
                rest = Array(rest.dropFirst())
            }
            let food = rest.joined(separator: " ")
            if !food.isEmpty { return (multiplier, food.trimmingCharacters(in: .whitespaces), nil) }
        }
        // Decimal Nx multiplier: "1.5x chicken", "0.5x rice", "2.5x oats"
        if let first = leadingWords.first {
            let lower = first.lowercased()
            if lower.hasSuffix("x"), let multiplier = Double(String(lower.dropLast())) {
                var rest = Array(leadingWords.dropFirst())
                if let next = rest.first, ["the", "a", "an", "my"].contains(next.lowercased()) {
                    rest = Array(rest.dropFirst())
                }
                let food = rest.joined(separator: " ")
                if !food.isEmpty { return (multiplier, food.trimmingCharacters(in: .whitespaces), nil) }
            }
        }
        if leadingWords.count >= 3, let num = Double(leadingWords[0]) {
            let unit = leadingWords[1].lowercased()
            // "N fl oz food" — two-word compound unit
            if unit == "fl" && leadingWords.count >= 4 && leadingWords[2].lowercased() == "oz" {
                let foodStart = leadingWords.count > 4 && leadingWords[3].lowercased() == "of" ? 4 : 3
                if leadingWords.count > foodStart {
                    let food = leadingWords[foodStart...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    if !food.isEmpty { return (nil, food, num * 29.5735) }
                }
            }
            let convertedGrams = normalizeToGrams(num, unit: unit)
            let isCountUnit = countUnitsLeading.contains(unit)
            if convertedGrams != nil || isCountUnit {
                var foodStart = 2
                if leadingWords.count > 3 && leadingWords[2].lowercased() == "of" { foodStart = 3 }
                let food = leadingWords[foodStart...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !food.isEmpty {
                    if let cg = convertedGrams {
                        return (nil, food, normalizeToGrams(num, unit: unit, foodHint: food) ?? cg)
                    } else if unit == "piece" || unit == "pieces",
                              let pieceGrams = normalizeToGrams(num, unit: "piece", foodHint: food) {
                        return (nil, food, pieceGrams)
                    } else {
                        return (num, food, nil)
                    }
                }
            }
        }

        if leadingWords.count >= 2 {
            let first = leadingWords[0].lowercased()
            for unit in weightAndVolumeUnits {
                if first.hasSuffix(unit), let num = Double(first.dropLast(unit.count)),
                   let grams = normalizeToGrams(num, unit: unit) {
                    var remaining = leadingWords[1...]
                    if remaining.first?.lowercased() == "of" { remaining = remaining.dropFirst() }
                    let food = remaining.joined(separator: " ")
                    return (nil, food.trimmingCharacters(in: .whitespaces), grams)
                }
            }
        }

        let twoWordAmounts: [(String, String, Double)] = [
            ("a", "quarter", 0.25), ("a", "half", 0.5),
            ("one", "quarter", 0.25), ("one", "half", 0.5),
            ("half", "a", 0.5),
        ]
        if leadingWords.count >= 4 {
            for (w1, w2, amt) in twoWordAmounts {
                if leadingWords[0].lowercased() == w1 && leadingWords[1].lowercased() == w2 {
                    let unit = leadingWords[2].lowercased()
                    let convertedGrams = normalizeToGrams(amt, unit: unit)
                    let isCountUnit = countUnitsLeading.contains(unit)
                    if convertedGrams != nil || isCountUnit {
                        var foodStart = 3
                        if leadingWords.count > 4 && leadingWords[3].lowercased() == "of" { foodStart = 4 }
                        let food = leadingWords[foodStart...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                        if !food.isEmpty {
                            if convertedGrams != nil {
                                return (nil, food, normalizeToGrams(amt, unit: unit, foodHint: food) ?? convertedGrams!)
                            } else {
                                return (amt, food, nil)
                            }
                        }
                    }
                }
            }
        }

        let wordAmountsLeading: [String: Double] = ["half": 0.5, "quarter": 0.25, "one": 1, "two": 2, "three": 3, "a": 1, "an": 1]
        if leadingWords.count >= 3, let amt = wordAmountsLeading[leadingWords[0].lowercased()] {
            let unit = leadingWords[1].lowercased()
            let convertedGrams = normalizeToGrams(amt, unit: unit)
            let isCountUnit = countUnitsLeading.contains(unit)
            if convertedGrams != nil || isCountUnit {
                var foodStart = 2
                if leadingWords.count > 3 && leadingWords[2].lowercased() == "of" { foodStart = 3 }
                let food = leadingWords[foodStart...].joined(separator: " ").trimmingCharacters(in: .whitespaces)
                if !food.isEmpty {
                    if convertedGrams != nil {
                        return (nil, food, normalizeToGrams(amt, unit: unit, foodHint: food) ?? convertedGrams!)
                    } else {
                        return (amt, food, nil)
                    }
                }
            }
        }

        let multiWord: [(String, Double)] = [("a couple of ", 2), ("couple of ", 2), ("a few ", 3), ("a lot of ", 2), ("lots of ", 2)]
        for (prefix, amount) in multiWord {
            if text.lowercased().hasPrefix(prefix) {
                return (amount, String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces), nil)
            }
        }

        let allWeightUnits: Set<String> = weightAndVolumeUnits.union(countUnitsLeading)
        let allWords = text.split(separator: " ").map(String.init)
        if allWords.count >= 3 {
            let lastWord = allWords.last!.lowercased()
            let secondLast = allWords[allWords.count - 2]
            if allWeightUnits.contains(lastWord), let rawAmt = Double(secondLast) {
                let food = allWords[0..<(allWords.count - 2)].joined(separator: " ")
                if !food.isEmpty {
                    if let grams = normalizeToGrams(rawAmt, unit: lastWord) {
                        return (nil, food.trimmingCharacters(in: .whitespaces), grams)
                    } else {
                        return (rawAmt, food.trimmingCharacters(in: .whitespaces), nil)
                    }
                }
            }
        }
        if allWords.count >= 2 {
            let lastWord = allWords.last!.lowercased()
            for unit in allWeightUnits {
                if lastWord.hasSuffix(unit), let rawAmt = Double(lastWord.dropLast(unit.count)) {
                    let food = allWords[0..<(allWords.count - 1)].joined(separator: " ")
                    if !food.isEmpty {
                        if let grams = normalizeToGrams(rawAmt, unit: unit) {
                            return (nil, food.trimmingCharacters(in: .whitespaces), grams)
                        } else {
                            return (rawAmt, food.trimmingCharacters(in: .whitespaces), nil)
                        }
                    }
                }
            }
        }

        let parts = text.split(separator: " ", maxSplits: 1)
        guard let first = parts.first else { return (nil, text, nil) }
        let firstStr = String(first)

        if firstStr.contains("/") {
            let fracParts = firstStr.split(separator: "/")
            if fracParts.count == 2, let num = Double(fracParts[0]), let den = Double(fracParts[1]), den > 0 {
                let food = parts.count > 1 ? String(parts[1]) : ""
                return (num / den, food.trimmingCharacters(in: .whitespaces), nil)
            }
        }

        let wordAmounts: [String: Double] = [
            "half": 0.5, "quarter": 0.25, "third": 1.0/3, "sixth": 1.0/6, "eighth": 0.125,
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "a": 1, "an": 1, "the": 1, "couple": 2, "few": 3, "several": 4, "some": 1
        ]
        if let amount = wordAmounts[firstStr] {
            let food = parts.count > 1 ? String(parts[1]) : ""
            return (amount, food.trimmingCharacters(in: .whitespaces), nil)
        }

        let leadingLower = firstStr.lowercased()
        for unit in allWeightUnits {
            if leadingLower.hasSuffix(unit), let rawAmt = Double(leadingLower.dropLast(unit.count)) {
                let food = parts.count > 1 ? String(parts[1]) : ""
                if let grams = normalizeToGrams(rawAmt, unit: unit) {
                    return (nil, food.trimmingCharacters(in: .whitespaces), grams)
                } else {
                    return (rawAmt, food.trimmingCharacters(in: .whitespaces), nil)
                }
            }
        }

        if let num1 = Double(firstStr), leadingWords.count >= 4 {
            let connector = leadingWords[1].lowercased()
            if (connector == "to" || connector == "or" || connector == "-"),
               let num2 = Double(leadingWords[2]) {
                let food = leadingWords[3...].joined(separator: " ")
                let higher = max(num1, num2)
                return (higher, food.trimmingCharacters(in: .whitespaces), nil)
            }
        }

        if let num = Double(firstStr) {
            let food = parts.count > 1 ? String(parts[1]) : ""
            if num > 10 {
                return (nil, text, nil)
            }
            return (num, food.trimmingCharacters(in: .whitespaces), nil)
        }

        let connectors: Set<String> = ["with", "of", "and", "plus", "w/", "x"]
        for i in 1..<allWords.count {
            if let num = Double(allWords[i]), num > 0, num <= 10 {
                var foodWords = Array(allWords[0..<i])
                while let last = foodWords.last, connectors.contains(last.lowercased()) {
                    foodWords.removeLast()
                }
                let food = foodWords.joined(separator: " ")
                if !food.isEmpty {
                    return (num, food.trimmingCharacters(in: .whitespaces), nil)
                }
            }
        }

        return (nil, text, nil)
    }
}
