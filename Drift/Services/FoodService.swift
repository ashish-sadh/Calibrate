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
                return "Removed \(last.foodName) (\(Int(last.entry.calories)) cal)."
            }
            return "Couldn't find '\(name)' in today's food log."
        }
        try? AppDatabase.shared.deleteFoodEntry(id: entryId)
        return "Removed \(found.foodName) (\(Int(found.entry.calories)) cal)."
    }

    // MARK: - Quick Add Calories

    /// Quick-add raw calories: "log 500 cal for lunch". Creates a manual entry.
    static func quickAddCalories(_ calories: Int, meal: String? = nil, name: String? = nil) -> String {
        let today = DateFormatters.todayString
        let foodName = name ?? "Quick Add"
        let mealType = meal ?? {
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour { case ..<11: return "breakfast"; case ..<15: return "lunch"; case ..<21: return "dinner"; default: return "snack" }
        }()
        do {
            var mealLogs = try AppDatabase.shared.fetchMealLogs(for: today)
            var mealLog = mealLogs.first { $0.mealType == mealType }
            if mealLog == nil {
                var newLog = MealLog(date: today, mealType: mealType)
                try AppDatabase.shared.saveMealLog(&newLog)
                mealLog = newLog
            }
            guard let mlId = mealLog?.id else { return "Failed to create meal log." }
            var entry = FoodEntry(mealLogId: mlId, foodName: foodName, servingSizeG: 0, servings: 1,
                                   calories: Double(calories), proteinG: 0, carbsG: 0, fatG: 0)
            try AppDatabase.shared.saveFoodEntry(&entry)
            return "Logged \(foodName) (\(calories) cal) for \(mealType)."
        } catch {
            return "Failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Copy Yesterday

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
