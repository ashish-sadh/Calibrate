import Foundation
import GRDB

/// Unified food service — used by both UI views and AI tool calls.
/// Wraps AppDatabase food methods + adds computed insights.
@MainActor
enum FoodService {

    // MARK: - Search

    /// Search foods by name. Returns ranked results (usage frequency, then relevance).
    static func searchFood(query: String) -> [Food] {
        let corrected = SpellCorrectService.correct(query)
        return (try? AppDatabase.shared.searchFoodsRanked(query: corrected)) ?? []
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

    /// Get today's nutrition totals with target and remaining.
    static func getDailyTotals(date: String? = nil) -> DailyTotals {
        let dateStr = date ?? DateFormatters.todayString
        let nutrition = (try? AppDatabase.shared.fetchDailyNutrition(for: dateStr)) ?? .zero
        let tdee = TDEEEstimator.shared.current?.tdee ?? 2000
        let deficit = WeightGoal.load()?.requiredDailyDeficit ?? 0
        let target = max(500, Int(tdee - deficit))
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
        if let goal = WeightGoal.load(), let targets = goal.macroTargets() {
            let pLeft = max(0, Int(targets.proteinG) - totals.proteinG)
            if pLeft > 20 { response += ". Still need \(pLeft)g protein" }
        }

        return response + "."
    }

    // MARK: - Suggestions

    /// Top protein foods from DB, sorted by protein per serving.
    static func topProteinFoods(limit: Int = 5) -> [Food] {
        // Query foods sorted by protein descending
        guard let foods = try? AppDatabase.shared.reader.read({ db in
            try Food.order(Column("protein_g").desc).limit(limit).fetchAll(db)
        }) else { return [] }
        return foods
    }

    /// Suggest foods that fit remaining calorie/protein budget.
    static func suggestMeal(caloriesLeft: Int? = nil, proteinNeeded: Int? = nil) -> [Food] {
        let totals = getDailyTotals()
        let calBudget = caloriesLeft ?? max(0, totals.remaining)
        let protBudget = proteinNeeded ?? {
            if let goal = WeightGoal.load(), let targets = goal.macroTargets() {
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

    // MARK: - Explain

    /// Break down the calories math: TDEE, deficit, target, eaten, remaining.
    static func explainCalories() -> String {
        let totals = getDailyTotals()
        let tdee = TDEEEstimator.shared.current?.tdee ?? 2000
        let deficit = WeightGoal.load()?.requiredDailyDeficit ?? 0

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
