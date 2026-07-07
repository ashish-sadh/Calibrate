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

        // #942 B2/B3: a query that is really MULTIPLE foods ("eggs avocado")
        // must not fuzzy-resolve to one prepared dish that shares a word
        // ("Eggs Benedict") or silently drop items via the first-word
        // fallback below. Callers split via parseMultiItemMeal / confirm.
        if query.contains(" "), segmentFoodItems(query) != nil {
            return nil
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

// MARK: - Multi-item segmentation (#942)

extension AIActionExecutor {

    /// Tight standalone match — does `query` name a real food BY ITSELF?
    /// Requires exact-name or name-prefix match among the top-ranked results
    /// (a mere substring hit like "supreme" inside "Supreme Pizza" does NOT
    /// count). This is the discriminator between "another food the user
    /// listed" and "a qualifier word" (#942 B2).
    static func tightFoodMatch(_ query: String) -> Food? {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard q.count >= 3 else { return nil }
        let singular = q.hasSuffix("s") && q.count > 3 ? String(q.dropLast()) : q
        for candidate in singular == q ? [q] : [singular, q] {
            guard let results = try? AppDatabase.shared.searchFoodsRanked(query: candidate),
                  !results.isEmpty else { continue }
            if let exact = results.prefix(15).first(where: { $0.name.lowercased() == candidate }) {
                return exact
            }
            if let prefix = results.prefix(15).first(where: { r in
                let name = r.name.lowercased()
                return name.hasPrefix(candidate + " ") || name.hasPrefix(candidate + ",")
            }) {
                return prefix
            }
            // Tier 3: whole-word at a name boundary ("toast" ← "avocado
            // toast") for foods the DB only carries in compounds — but never
            // for preparation/qualifier words, or "grilled chicken" would
            // split into two items.
            if !Self.foodQualifierWords.contains(candidate),
               let boundary = results.prefix(15).first(where: { r in
                   let name = r.name.lowercased()
                   return name.hasSuffix(" " + candidate) || name.hasPrefix(candidate + " ")
               }) {
                return boundary
            }
        }
        return nil
    }

    /// Cooking/preparation adjectives — a closed class that must never count
    /// as standalone foods during segmentation (#942).
    static let foodQualifierWords: Set<String> = [
        "grilled", "boiled", "fried", "roasted", "baked", "steamed", "raw",
        "cooked", "toasted", "fresh", "plain", "large", "small", "medium",
        "supreme", "deluxe", "homemade", "style", "spicy", "sweet", "hot",
        "cold", "dry", "wet", "mini", "jumbo", "extra", "double", "half",
        "whole", "sliced", "diced", "chopped", "mashed", "scrambled",
    ]

    /// Segment a space-separated multi-item description into per-food strings
    /// using greedy longest-run matching against the real food DB (#942 B1):
    /// "eggs avocado" → ["eggs", "avocado"]; "banana peanut butter" →
    /// ["banana", "peanut butter"] (longest run keeps compounds together);
    /// "chicken curry" → nil (the full string tight-matches one dish);
    /// "chicken supreme deluxe" → nil (unknown tokens = qualifiers, keep the
    /// single-item path). Leading numbers attach to the following food
    /// ("2 eggs 1 avocado" → ["2 eggs", "1 avocado"]). Returns nil unless
    /// EVERY token is consumed by a tight match — conservative by design so
    /// this never breaks up genuine single dishes.
    public static func segmentFoodItems(_ text: String) -> [String]? {
        // Intent verbs / filler / meal words — never foods; stripping them
        // lets the RAW chat message ("log eggs avocado for breakfast")
        // segment without a pre-cleaned query. Both AIToolAgent interception
        // sites pass the raw message (#942).
        let stop: Set<String> = ["a", "an", "the", "some", "of", "and",
                                 "log", "logged", "logging", "ate", "eat", "had",
                                 "have", "having", "i", "me", "my", "please",
                                 "add", "track", "just", "for", "breakfast",
                                 "lunch", "dinner", "snack", "today", "yesterday",
                                 "this", "morning", "evening", "night", "with"]
        let numberWords: Set<String> = ["one", "two", "three", "four", "five", "six",
                                        "seven", "eight", "nine", "ten", "half"]
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: " ,"))
            .filter { !$0.isEmpty && !stop.contains($0) }
        guard tokens.count >= 2, tokens.count <= 8 else { return nil }

        var segments: [String] = []
        var i = 0
        while i < tokens.count {
            // A count ("2", "two") or measured amount ("100g") rides with the
            // food that follows it; extractAmount parses it per segment later.
            var prefix: [String] = []
            while i < tokens.count,
                  Double(tokens[i]) != nil || numberWords.contains(tokens[i])
                    || tokens[i].range(of: "^[0-9]+(g|gm|gms|grams?|ml|kg|oz)$",
                                       options: .regularExpression) != nil {
                prefix.append(tokens[i])
                i += 1
            }
            guard i < tokens.count else { return nil }
            // Greedy longest run first, so "peanut butter" and "chicken curry"
            // stay whole before "peanut"/"chicken" are tried alone.
            var matched: (run: [String], next: Int)? = nil
            var j = min(tokens.count, i + 4)
            while j > i {
                let run = Array(tokens[i..<j])
                if tightFoodMatch(run.joined(separator: " ")) != nil {
                    matched = (run, j)
                    break
                }
                j -= 1
            }
            guard let m = matched else { return nil }
            segments.append((prefix + m.run).joined(separator: " "))
            i = m.next
        }
        return segments.count >= 2 ? segments : nil
    }
}
