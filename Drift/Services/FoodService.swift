import Foundation
import GRDB

/// Unified food service — used by both UI views and AI tool calls.
/// Wraps AppDatabase food methods + adds computed insights.
@MainActor
enum FoodService {

    // MARK: - Search

    /// Search foods by name. Returns ranked results (usage, relevance, time-of-day boost).
    static func searchFood(query: String) -> [Food] {
        let corrected = SpellCorrectService.correct(query)
        var results = (try? AppDatabase.shared.searchFoodsRanked(query: corrected)) ?? []

        // Synonym expansion: if "curd" → "yogurt", merge those results too
        let expanded = SpellCorrectService.expandSynonyms(corrected)
        if expanded != corrected {
            let extraResults = (try? AppDatabase.shared.searchFoodsRanked(query: expanded)) ?? []
            let existingIds = Set(results.compactMap(\.id))
            results.append(contentsOf: extraResults.filter { food in
                guard let id = food.id else { return true }
                return !existingIds.contains(id)
            })
        }

        // Time-of-day boost: re-rank top results based on meal type
        let hour = Calendar.current.component(.hour, from: Date())
        let boostKeywords: [String]
        switch hour {
        case ..<11: boostKeywords = ["oat", "egg", "toast", "coffee", "tea", "cereal", "milk", "banana", "yogurt"]
        case 11..<15: boostKeywords = ["chicken", "rice", "sandwich", "salad", "dal", "roti", "wrap"]
        case 15..<18: boostKeywords = ["protein", "shake", "bar", "almonds", "fruit", "snack"]
        default: boostKeywords = ["chicken", "fish", "paneer", "rice", "pasta", "vegetables", "curry"]
        }

        results.sort { a, b in
            let aBoost = boostKeywords.contains(where: { a.name.lowercased().contains($0) })
            let bBoost = boostKeywords.contains(where: { b.name.lowercased().contains($0) })
            if aBoost && !bBoost { return true }
            if !aBoost && bBoost { return false }
            return false // preserve existing order
        }

        // Track queries that return no local results — used for food DB prioritization
        if results.isEmpty {
            try? AppDatabase.shared.trackSearchMiss(query: query)
        }

        return results
    }

    /// Search saved recipes by name.
    static func searchRecipes(query: String) -> [SavedFood] {
        (try? AppDatabase.shared.searchRecipes(query: query)) ?? []
    }

    /// Check if a food is favorited.
    static func isFavorite(name: String) -> Bool {
        (try? AppDatabase.shared.isFoodFavorite(name: name)) ?? false
    }

    /// Toggle favorite status for a food.
    static func toggleFavorite(name: String, foodId: Int64?) {
        try? AppDatabase.shared.toggleFoodFavorite(name: name, foodId: foodId)
    }

    /// Delete a favorite by ID.
    static func deleteFavorite(id: Int64) {
        try? AppDatabase.shared.deleteFavorite(id: id)
    }

    /// Save a scanned food (from barcode or online search).
    static func saveScannedFood(_ food: inout Food) -> Food? {
        try? AppDatabase.shared.saveScannedFood(&food)
        return (try? AppDatabase.shared.searchFoods(query: food.name))?.first
    }

    /// Fetch a single food by name (best match).
    static func findByName(_ name: String) -> Food? {
        (try? AppDatabase.shared.searchFoods(query: name, limit: 1))?.first
    }

    /// Delete a user-added (scanned) food and its usage tracking.
    static func deleteScannedFood(id: Int64, name: String) {
        try? AppDatabase.shared.writer.write { db in
            _ = try Food.deleteOne(db, id: id)
            try db.execute(sql: "DELETE FROM food_usage WHERE food_name = ?", arguments: [name])
        }
    }

    /// Fetch recently used foods.
    static func fetchRecentFoods(limit: Int = 10) -> [Food] {
        (try? AppDatabase.shared.fetchRecentFoods(limit: limit)) ?? []
    }

    /// Fetch foods by category.
    static func fetchFoodsByCategory(_ category: String) -> [Food] {
        (try? AppDatabase.shared.fetchFoodsByCategory(category)) ?? []
    }

    /// Save a recipe/favorite.
    static func saveRecipe(_ fav: inout SavedFood) {
        try? AppDatabase.shared.saveFavorite(&fav)
    }

    /// Fetch a cached barcode product.
    static func fetchCachedBarcode(_ barcode: String) -> BarcodeCache? {
        try? AppDatabase.shared.fetchCachedBarcode(barcode)
    }

    /// Cache a barcode product for future lookups.
    static func cacheBarcodeProduct(_ cache: BarcodeCache) {
        try? AppDatabase.shared.cacheBarcodeProduct(cache)
    }

    /// Fetch meal logs for a date.
    static func fetchMealLogs(for date: String) -> [MealLog] {
        (try? AppDatabase.shared.fetchMealLogs(for: date)) ?? []
    }

    /// Fetch food entries for a meal log.
    static func fetchFoodEntries(forMealLog id: Int64) -> [FoodEntry] {
        (try? AppDatabase.shared.fetchFoodEntries(forMealLog: id)) ?? []
    }

    /// Fetch food items for plant points calculation.
    static func fetchFoodItemsForPlantPoints(from startDate: String, to endDate: String) -> [PlantPointsService.FoodItem] {
        (try? AppDatabase.shared.fetchFoodItemsForPlantPoints(from: startDate, to: endDate)) ?? []
    }

    /// Fetch a food by its database ID.
    static func fetchFoodById(_ id: Int64) -> Food? {
        try? AppDatabase.shared.reader.read { db in try Food.fetchOne(db, id: id) }
    }

    /// Update a food entry's name by entry ID.
    static func updateFoodEntryName(id: Int64, name: String) {
        try? AppDatabase.shared.updateFoodEntryName(id: id, name: name)
    }

    /// Update a food entry's macros by entry ID.
    static func updateFoodEntryMacros(id: Int64, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double) {
        try? AppDatabase.shared.updateFoodEntryMacros(id: id, calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG)
        WidgetDataProvider.refreshWidgetData()
    }

    /// Update a food's name and macros by ID.
    static func updateFood(id: Int64, name: String, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double) {
        try? AppDatabase.shared.writer.write { db in
            try db.execute(sql: """
                UPDATE food SET name = ?, calories = ?, protein_g = ?,
                carbs_g = ?, fat_g = ?, fiber_g = ? WHERE id = ?
                """, arguments: [name, calories, proteinG, carbsG, fatG, fiberG, id])
        }
    }

    /// Update a saved recipe in place: rewrites the ingredients JSON and
    /// recomputes per-serving macros from the items sum. Used by the recipe
    /// builder when editing an existing recipe (#192) — avoids the duplicate
    /// row that `saveRecipe` would otherwise create.
    static func updateRecipe(id: Int64, name: String, items: [QuickAddView.RecipeItem], servings: Double = 1, expandOnLog: Bool = false) {
        let safeServings = max(servings, 0.1)
        let totals = items.reduce(into: (cal: 0.0, p: 0.0, c: 0.0, f: 0.0, fb: 0.0)) { acc, item in
            acc.cal += item.calories
            acc.p += item.proteinG
            acc.c += item.carbsG
            acc.f += item.fatG
            acc.fb += item.fiberG
        }
        let ingredientsJson = (try? JSONEncoder().encode(items))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        try? AppDatabase.shared.writer.write { db in
            try db.execute(sql: """
                UPDATE food SET name = ?, calories = ?, protein_g = ?,
                carbs_g = ?, fat_g = ?, fiber_g = ?, ingredients = ?,
                is_recipe = 1, expand_on_log = ? WHERE id = ?
                """, arguments: [
                    name,
                    totals.cal / safeServings,
                    totals.p / safeServings,
                    totals.c / safeServings,
                    totals.f / safeServings,
                    totals.fb / safeServings,
                    ingredientsJson,
                    expandOnLog,
                    id
                ])
        }
    }

    /// Log a recipe: aggregated single entry, or expanded (one entry per ingredient)
    /// when `recipe.expandOnLog == true` and ingredient items are available.
    /// Returns true if expanded (caller can decide feedback text).
    @discardableResult
    static func logRecipe(_ recipe: Food, servings: Double, mealType: MealType,
                          loggedAt: String? = nil, viewModel: FoodLogViewModel) -> Bool {
        if recipe.expandOnLog, let items = recipe.recipeItems, !items.isEmpty {
            for item in items {
                viewModel.quickAdd(
                    name: item.name,
                    calories: item.calories * servings,
                    proteinG: item.proteinG * servings,
                    carbsG: item.carbsG * servings,
                    fatG: item.fatG * servings,
                    fiberG: item.fiberG * servings,
                    mealType: mealType,
                    loggedAt: loggedAt,
                    servingSizeG: item.servingSizeG * servings,
                    servings: 1
                )
            }
            return true
        }
        viewModel.quickAdd(
            name: recipe.name, calories: recipe.calories * servings,
            proteinG: recipe.proteinG * servings, carbsG: recipe.carbsG * servings,
            fatG: recipe.fatG * servings, fiberG: recipe.fiberG * servings,
            mealType: mealType, loggedAt: loggedAt,
            servingSizeG: recipe.servingSize, servings: 1
        )
        return false
    }

    // MARK: - Search with Online Fallback

    /// Search locally first, then fall back to USDA + OpenFoodFacts if enabled and local results < threshold.
    /// Used by AI chat when resolving food names that aren't in the local DB.
    static func searchWithFallback(query: String, localThreshold: Int = 3) async -> [Food] {
        let local = searchFood(query: query)
        guard local.count < localThreshold, Preferences.onlineFoodSearchEnabled else { return local }

        // Fetch from both APIs in parallel
        async let usdaItems = (try? USDAFoodService.search(query: query, limit: 5)) ?? []
        async let offProducts = (try? OpenFoodFactsService.search(query: query, limit: 5)) ?? []

        let usda = await usdaItems
        let off = await offProducts

        var online: [Food] = []
        let localNames = Set(local.map { $0.name.lowercased() })

        for item in usda {
            guard !localNames.contains(item.name.lowercased()) else { continue }
            var food = Food(
                name: item.name, category: "Online",
                servingSize: item.servingSizeG, servingUnit: "g",
                calories: item.calories, proteinG: item.proteinG,
                carbsG: item.carbsG, fatG: item.fatG, fiberG: item.fiberG
            )
            if let saved = saveScannedFood(&food) { online.append(saved) }
        }

        for p in off {
            let name = [p.name, p.brand].compactMap { $0 }.joined(separator: " - ")
            guard !localNames.contains(name.lowercased()) else { continue }
            let servingG = p.servingSizeG ?? 100
            var food = Food(
                name: name, category: "Online",
                servingSize: servingG, servingUnit: "g",
                calories: p.calories * servingG / 100, proteinG: p.proteinG * servingG / 100,
                carbsG: p.carbsG * servingG / 100, fatG: p.fatG * servingG / 100,
                fiberG: p.fiberG * servingG / 100
            )
            if let saved = saveScannedFood(&food) { online.append(saved) }
        }

        return local + online
    }

    // MARK: - Nutrition Lookup

    /// Get nutrition for a food by name. Returns best match or nil.
    static func getNutrition(name: String) -> (food: Food, perServing: String)? {
        let corrected = SpellCorrectService.correct(name)
        guard let results = try? AppDatabase.shared.searchFoodsRanked(query: corrected),
              let food = results.first else { return nil }
        let desc = "\(food.name) (per \(Int(food.servingSize))\(food.servingUnit)): \(Int(food.calories)) cal, \(Int(food.proteinG))g protein, \(Int(food.carbsG))g carbs, \(Int(food.fatG))g fat"
        return (food: food, perServing: desc)
    }

    // MARK: - Daily Totals

    /// Single source of truth for daily calorie target. All calorie "remaining" displays should use this.
    static func resolvedCalorieTarget() -> Int {
        let currentKg = WeightTrendService.shared.latestWeightKg ?? 80
        if let goalTarget = WeightGoal.load()?.macroTargets(currentWeightKg: currentKg)?.calorieTarget {
            return max(1200, Int(goalTarget))
        }
        let tdee = TDEEEstimator.shared.current?.tdee ?? 2000
        let deficit = WeightGoal.load()?.requiredDailyDeficit(currentWeightKg: currentKg) ?? 0
        return max(1200, Int(tdee + deficit))
    }

    /// Get today's nutrition totals with target and remaining.
    static func getDailyTotals(date: String? = nil) -> DailyTotals {
        let dateStr = date ?? DateFormatters.todayString
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: dateStr)) ?? .zero
        let target = resolvedCalorieTarget()
        let remaining = target - Int(nutrition.calories)

        return DailyTotals(
            eaten: Int(nutrition.calories),
            target: target,
            remaining: remaining,
            proteinG: Int(nutrition.proteinG),
            carbsG: Int(nutrition.carbsG),
            fatG: Int(nutrition.fatG),
            fiberG: Int(nutrition.fiberG)
        )
    }

    /// Calories left with protein context.
    static func getCaloriesLeft() -> String {
        let totals = getDailyTotals()
        if totals.eaten == 0 {
            return "No food logged yet. Target: \(totals.target) cal."
        }

        var response = "\(totals.remaining > 0 ? totals.remaining : 0) cal remaining (\(totals.eaten)/\(totals.target))"

        // Protein context
        if let goal = WeightGoal.load(), let targets = goal.macroTargets(currentWeightKg: WeightTrendService.shared.latestWeightKg) {
            let pLeft = max(0, Int(targets.proteinG) - totals.proteinG)
            if pLeft > 20 { response += ". Still need \(pLeft)g protein" }
        }

        return response + "."
    }

    /// Formats a macro-goal-progress line: "Protein: 87g / 120g goal — 73% (33g to go)".
    /// Pure — no I/O. Returns percent of target (capped at 999 to avoid absurd values on bad input).
    nonisolated static func macroProgressLine(label: String, currentG: Int, targetG: Int, unit: String = "g") -> String {
        let c = max(0, currentG)
        let t = max(0, targetG)
        guard t > 0 else { return "\(label): \(c)\(unit)." }
        let pct = min(999, Int((Double(c) / Double(t)) * 100.0))
        let tail: String
        if c >= t {
            let over = c - t
            tail = over == 0 ? "target reached!" : "\(over)\(unit) over"
        } else {
            tail = "\(t - c)\(unit) to go"
        }
        return "\(label): \(c)\(unit) / \(t)\(unit) goal — \(pct)% (\(tail))."
    }

    // MARK: - Suggestions

    /// High-protein foods the user actually eats, that fit remaining calories.
    /// Falls back to DB top-protein if no user history.
    static func topProteinFoods(limit: Int = 5) -> [Food] {
        let totals = getDailyTotals()
        let calBudget = max(0, totals.remaining)

        // Prefer user's recent foods — they actually eat these
        let recents = (try? AppDatabase.shared.fetchRecentFoods(limit: 30)) ?? []
        let fitting = recents
            .filter { $0.proteinG >= 15 && $0.calories <= Double(max(calBudget, 200)) }
            .sorted { $0.proteinG > $1.proteinG }

        if fitting.count >= limit { return Array(fitting.prefix(limit)) }

        // Fill with DB high-protein foods not already in list
        let recentNames = Set(fitting.map(\.name))
        let dbFoods = (try? AppDatabase.shared.reader.read { db in
            try Food.filter(Column("protein_g") >= 15)
                .order(Column("protein_g").desc)
                .limit(limit * 2)
                .fetchAll(db)
        }) ?? []
        let extra = dbFoods.filter { !recentNames.contains($0.name) && $0.calories <= Double(max(calBudget, 200)) }

        return Array((fitting + extra).prefix(limit))
    }

    /// Suggest foods that fit remaining calorie/protein budget.
    static func suggestMeal(caloriesLeft: Int? = nil, proteinNeeded: Int? = nil) -> [Food] {
        let totals = getDailyTotals()
        let calBudget = caloriesLeft ?? max(0, totals.remaining)
        let protBudget = proteinNeeded ?? {
            if let goal = WeightGoal.load(), let targets = goal.macroTargets(currentWeightKg: WeightTrendService.shared.latestWeightKg) {
                return max(0, Int(targets.proteinG) - totals.proteinG)
            }
            return 50
        }()

        // Get recent foods the user actually eats, filtered by calorie budget
        let recents = (try? AppDatabase.shared.fetchRecentFoods(limit: 20)) ?? []
        let fitting = recents.filter { $0.calories <= Double(calBudget) && $0.calories > 50 }

        // Sort by protein (prioritize high protein when protein is needed)
        if protBudget > 30 {
            return Array(fitting.sorted { $0.proteinG > $1.proteinG }.prefix(3))
        }
        return Array(fitting.prefix(3))
    }

    // MARK: - Delete

    /// Delete by stable entry id (preferred path when the AI resolves a multi-turn
    /// reference to a specific row via the recentEntries window). Verifies the id
    /// belongs to today so a stale reference can't nuke an unrelated row.
    static func deleteEntry(id: Int64) -> String? {
        let today = DateFormatters.todayString
        guard let mealLogs = try? AppDatabase.shared.fetchMealLogs(for: today) else { return nil }
        for ml in mealLogs {
            guard let mlId = ml.id,
                  let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: mlId) else { continue }
            if let entry = entries.first(where: { $0.id == id }) {
                try? AppDatabase.shared.deleteFoodEntry(id: id)
                WidgetDataProvider.refreshWidgetData()
                ConversationState.shared.dropRecentEntry(id: id)
                return "Removed \(entry.foodName) (\(Int(entry.calories)) cal)."
            }
        }
        return nil
    }

    /// Delete the most recent food entry matching a name. Returns confirmation or error.
    static func deleteEntry(matching name: String) -> String {
        let today = DateFormatters.todayString
        guard let mealLogs = try? AppDatabase.shared.fetchMealLogs(for: today) else {
            return "No food logged today."
        }
        // Search all today's entries for a name match (newest first)
        var allEntries: [(entry: FoodEntry, foodName: String)] = []
        for ml in mealLogs {
            guard let mlId = ml.id,
                  let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: mlId) else { continue }
            for entry in entries {
                let entryName = entry.foodName
                allEntries.append((entry: entry, foodName: entryName))
            }
        }

        let lower = name.lowercased()
        // Try exact match first, then contains
        let match = allEntries.last(where: { $0.foodName.lowercased() == lower })
            ?? allEntries.last(where: { $0.foodName.lowercased().contains(lower) })

        guard let found = match, let entryId = found.entry.id else {
            if lower == "last" || lower == "last entry" {
                // Delete the very last entry
                guard let last = allEntries.last, let lastId = last.entry.id else {
                    return "No food entries today."
                }
                try? AppDatabase.shared.deleteFoodEntry(id: lastId)
                WidgetDataProvider.refreshWidgetData()
                ConversationState.shared.dropRecentEntry(id: lastId)
                return "Removed \(last.foodName) (\(Int(last.entry.calories)) cal)."
            }
            return "Couldn't find '\(name)' in today's food log."
        }
        try? AppDatabase.shared.deleteFoodEntry(id: entryId)
        WidgetDataProvider.refreshWidgetData()
        ConversationState.shared.dropRecentEntry(id: entryId)
        return "Removed \(found.foodName) (\(Int(found.entry.calories)) cal)."
    }

    // MARK: - Edit Meal

    /// Edit a food entry within a specific meal (or today overall when meal is nil).
    /// Actions:
    ///   - "remove" / "delete" — delete the matched entry
    ///   - "update_quantity" / "update" — newValue is servings ("2") or grams ("200g");
    ///     grams convert back to servings using the entry's servingSizeG.
    ///   - "replace" — newValue is the replacement food name; looks it up in the
    ///     local food DB, updates name + per-serving macros, keeps meal + servings.
    ///
    /// When `entryId` is provided AND matches a today-dated row, bypass name
    /// search entirely — this is the multi-turn reference path (#227).
    static func editMealEntry(
        mealPeriod: String?,
        targetFood: String,
        action: String,
        newValue: String?,
        entryId: Int64? = nil
    ) -> String {
        let today = DateFormatters.todayString
        guard let mealLogs = try? AppDatabase.shared.fetchMealLogs(for: today), !mealLogs.isEmpty else {
            return "No food logged today."
        }

        // Fast path: operate on a specific row resolved via recentEntries window.
        if let id = entryId,
           let found = findTodayEntry(id: id, in: mealLogs) {
            return applyEditAction(
                action: action, entry: found.entry,
                meal: found.meal, newValue: newValue
            )
        }

        // Filter by meal period when provided.
        let wantedMeal = mealPeriod?.lowercased()
        let filtered = wantedMeal.map { mt in mealLogs.filter { $0.mealType.lowercased() == mt } } ?? mealLogs
        if filtered.isEmpty, let mt = wantedMeal {
            return "No \(mt) logged today."
        }

        // Gather candidate entries across matching meals (newest last).
        var candidates: [(entry: FoodEntry, meal: String)] = []
        for ml in filtered {
            guard let mlId = ml.id,
                  let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: mlId) else { continue }
            for entry in entries {
                candidates.append((entry: entry, meal: ml.mealType))
            }
        }
        if candidates.isEmpty {
            if let mt = wantedMeal { return "No entries found in \(mt)." }
            return "No food entries today."
        }

        let query = targetFood.lowercased()
        let match = candidates.last(where: { $0.entry.foodName.lowercased() == query })
            ?? candidates.last(where: { $0.entry.foodName.lowercased().contains(query) })
        guard let found = match else {
            let where_ = wantedMeal.map { " in \($0)" } ?? ""
            return "Couldn't find '\(targetFood)'\(where_)."
        }
        return applyEditAction(action: action, entry: found.entry, meal: found.meal, newValue: newValue)
    }

    /// Locate a today-dated food entry by id across all of today's meal logs.
    /// Returns nil when the id is stale (entry deleted, or user referenced an
    /// entry from yesterday).
    private static func findTodayEntry(
        id: Int64, in mealLogs: [MealLog]
    ) -> (entry: FoodEntry, meal: String)? {
        for ml in mealLogs {
            guard let mlId = ml.id,
                  let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: mlId) else { continue }
            if let entry = entries.first(where: { $0.id == id }) {
                return (entry: entry, meal: ml.mealType)
            }
        }
        return nil
    }

    /// Apply a remove/update/replace action to a resolved FoodEntry. Kept
    /// separate from lookup so both the entry-id fast path and the name-match
    /// path can share the same write logic and response wording.
    private static func applyEditAction(
        action: String, entry: FoodEntry, meal: String, newValue: String?
    ) -> String {
        guard let entryId = entry.id else { return "Couldn't edit that entry." }
        switch action.lowercased() {
        case "remove", "delete":
            try? AppDatabase.shared.deleteFoodEntry(id: entryId)
            WidgetDataProvider.refreshWidgetData()
            ConversationState.shared.dropRecentEntry(id: entryId)
            let cal = Int(entry.calories * entry.servings)
            return "Removed \(entry.foodName) from \(meal) (\(cal) cal)."

        case "update_quantity", "update":
            guard let rawValue = newValue, !rawValue.isEmpty else {
                return "Missing new quantity for \(entry.foodName)."
            }
            let newServings = parseServings(rawValue, servingSizeG: entry.servingSizeG)
            guard let servings = newServings, servings > 0 else {
                return "Couldn't parse '\(rawValue)' as a quantity."
            }
            try? AppDatabase.shared.updateFoodEntryServings(id: entryId, servings: servings)
            WidgetDataProvider.refreshWidgetData()
            let formatted = servings == Double(Int(servings))
                ? "\(Int(servings))"
                : String(format: "%.1f", servings)
            return "Updated \(entry.foodName) to \(formatted) serving\(servings == 1 ? "" : "s") in \(meal)."

        case "replace", "swap":
            guard let raw = newValue?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
                return "Missing replacement food for \(entry.foodName)."
            }
            let candidates = searchFood(query: raw)
            guard let replacement = candidates.first else {
                return "Couldn't find '\(raw)' in the food DB — try logging it manually."
            }
            updateFoodEntryName(id: entryId, name: replacement.name)
            updateFoodEntryMacros(
                id: entryId,
                calories: replacement.calories,
                proteinG: replacement.proteinG,
                carbsG: replacement.carbsG,
                fatG: replacement.fatG,
                fiberG: replacement.fiberG
            )
            WidgetDataProvider.refreshWidgetData()
            if let mealType = MealType(rawValue: meal) {
                ConversationState.shared.pushRecentEntry(.init(
                    id: entryId, name: replacement.name, mealType: mealType.rawValue,
                    calories: Int(replacement.calories), loggedAt: Date()
                ))
            }
            return "Replaced \(entry.foodName) with \(replacement.name) in \(meal)."

        default:
            return "Unknown edit action '\(action)'."
        }
    }

    /// Parse a quantity string into servings. Supports plain numbers ("2", "1.5")
    /// and gram suffixes ("200g") — grams divide by the entry's serving size.
    private static func parseServings(_ raw: String, servingSizeG: Double) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasSuffix("g"), servingSizeG > 0 {
            let numPart = String(trimmed.dropLast())
            if let grams = Double(numPart), grams > 0 {
                return grams / servingSizeG
            }
            return nil
        }
        return Double(trimmed)
    }

    // MARK: - Copy Yesterday

    /// Preview yesterday's food entries without copying. Returns summary for confirmation.
    static func previewYesterday() -> String {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else {
            return "Couldn't determine yesterday's date."
        }
        let yesterdayStr = DateFormatters.dateOnly.string(from: yesterday)
        guard let mealLogs = try? AppDatabase.shared.fetchMealLogs(for: yesterdayStr), !mealLogs.isEmpty else {
            return "No food logged yesterday."
        }
        var names: [String] = []
        var totalCal = 0.0
        for ml in mealLogs {
            guard let mlId = ml.id,
                  let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: mlId) else { continue }
            for entry in entries {
                names.append(entry.foodName)
                totalCal += entry.calories
            }
        }
        if names.isEmpty { return "No entries to copy from yesterday." }
        let list = names.prefix(6).joined(separator: ", ")
        let more = names.count > 6 ? " + \(names.count - 6) more" : ""
        return "Yesterday: \(list)\(more) — \(names.count) items, \(Int(totalCal)) cal total. Say **\"confirm copy\"** to copy them to today."
    }

    /// Copy all of yesterday's food entries to today. Returns confirmation.
    static func copyYesterday() -> String {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else {
            return "Couldn't determine yesterday's date."
        }
        let yesterdayStr = DateFormatters.dateOnly.string(from: yesterday)
        let todayStr = DateFormatters.todayString
        guard let mealLogs = try? AppDatabase.shared.fetchMealLogs(for: yesterdayStr), !mealLogs.isEmpty else {
            return "No food logged yesterday."
        }

        var copied = 0
        for ml in mealLogs {
            guard let mlId = ml.id,
                  let entries = try? AppDatabase.shared.fetchFoodEntries(forMealLog: mlId),
                  !entries.isEmpty else { continue }
            // Create a meal log for today with same meal type
            var newLog = MealLog(date: todayStr, mealType: ml.mealType)
            guard let _ = try? AppDatabase.shared.saveMealLog(&newLog), let newLogId = newLog.id else { continue }
            for entry in entries {
                // Preserve yesterday's time-of-day but with today's date
                let adjustedLoggedAt: String
                let isoFmt = ISO8601DateFormatter()
                if let originalDate = isoFmt.date(from: entry.loggedAt),
                   let todayDate = DateFormatters.dateOnly.date(from: todayStr) {
                    let cal = Calendar.current
                    let time = cal.dateComponents([.hour, .minute, .second], from: originalDate)
                    if let adjusted = cal.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0,
                                                second: time.second ?? 0, of: todayDate) {
                        adjustedLoggedAt = isoFmt.string(from: adjusted)
                    } else { adjustedLoggedAt = isoFmt.string(from: Date()) }
                } else { adjustedLoggedAt = isoFmt.string(from: Date()) }

                var newEntry = FoodEntry(mealLogId: newLogId, foodId: entry.foodId, foodName: entry.foodName,
                                          servingSizeG: entry.servingSizeG, servings: entry.servings,
                                          calories: entry.calories, proteinG: entry.proteinG,
                                          carbsG: entry.carbsG, fatG: entry.fatG,
                                          fiberG: entry.fiberG, loggedAt: adjustedLoggedAt)
                try? AppDatabase.shared.saveFoodEntry(&newEntry)
                copied += 1
            }
        }
        if copied == 0 { return "No entries to copy from yesterday." }
        let cal = mealLogs.flatMap { ml in
            (try? AppDatabase.shared.fetchFoodEntries(forMealLog: ml.id ?? 0)) ?? []
        }.reduce(0.0) { $0 + $1.calories }
        WidgetDataProvider.refreshWidgetData()
        return "Copied \(copied) items from yesterday (\(Int(cal)) cal total)."
    }

    // MARK: - Explain

    /// Break down the calories math: TDEE, deficit, target, eaten, remaining.
    static func explainCalories() -> String {
        let totals = getDailyTotals()
        let tdee = TDEEEstimator.shared.current?.tdee ?? 2000
        let currentKg = WeightTrendService.shared.latestWeightKg ?? 80
        let deficit = WeightGoal.load()?.requiredDailyDeficit(currentWeightKg: currentKg) ?? 0

        var lines: [String] = []
        lines.append("Your estimated TDEE (total daily energy expenditure): \(Int(tdee)) cal")
        if deficit > 0 {
            lines.append("Daily deficit for your goal: \(Int(deficit)) cal")
        }
        lines.append("Calorie target: \(totals.target) cal (TDEE \(deficit > 0 ? "- deficit" : ""))")
        lines.append("Eaten today: \(totals.eaten) cal")
        lines.append("Remaining: \(totals.remaining > 0 ? "\(totals.remaining) cal" : "\(abs(totals.remaining)) cal over target")")
        lines.append("Macros: \(totals.proteinG)g protein, \(totals.carbsG)g carbs, \(totals.fatG)g fat")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Data Types

struct DailyTotals: Sendable {
    let eaten: Int
    let target: Int
    let remaining: Int
    let proteinG: Int
    let carbsG: Int
    let fatG: Int
    let fiberG: Int
}
