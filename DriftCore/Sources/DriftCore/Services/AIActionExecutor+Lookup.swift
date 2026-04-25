import Foundation

/// iOS-only side of AIActionExecutor — DB lookup + LLM-assisted normalization.
/// Pure parsing methods live in DriftCore (`AIActionExecutor` enum).
extension AIActionExecutor {

    public struct FoodMatch {
        public let food: Food
        public let servings: Double
    }

    /// Search local DB for food. If gram amount is provided, converts to servings using food's serving size.
    public static func findFood(query: String, servings: Double?, gramAmount: Double? = nil) -> FoodMatch? {
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
               !results.isEmpty {
                let q = searchQuery.lowercased()
                // Priority: exact name > starts-with-query > first-word-equals-query
                let exactMatch = results.prefix(15).first(where: { $0.name.lowercased() == q })
                let tightMatch = exactMatch ?? results.prefix(15).first(where: { r in
                    let name = r.name.lowercased()
                    let firstWord = name.split(separator: " ").first.map(String.init) ?? name
                    return name.hasPrefix(q + " ") || name.hasPrefix(q + ",") || firstWord == q
                })
                let candidate = tightMatch ?? results[0]
                let queryWords = q.split(separator: " ")
                let matchCount = queryWords.filter { candidate.name.lowercased().contains($0) }.count
                if matchCount > 0 {
                    return FoodMatch(food: candidate, servings: resolveServings(for: candidate))
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

        // Try stripping qualifiers
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
    public static func findFoodWithAI(query: String, servings: Double?) async -> FoodMatch? {
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
}
