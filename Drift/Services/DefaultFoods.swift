import Foundation

/// Seeds food usage data and recipe favorites from user's historical MacroFactor logs.
/// Only runs once on first launch. Respects user edits.
enum DefaultFoods {
    private static let seededKey = "drift_default_foods_seeded_v1"

    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let db = AppDatabase.shared

        // Seed food usage for frequently logged items (boosts search ranking + shows in recents)
        for (name, count) in topFoods {
            // Find the food ID if it exists in the DB
            let foodId = (try? db.searchFoods(query: name, limit: 1))?.first?.id
            for _ in 0..<count {
                try? db.trackFoodUsage(name: name, foodId: foodId, servings: 1)
            }
        }

        // Seed recipe favorites for common meals
        for recipe in recipes {
            var fav = FavoriteFood(name: recipe.name, calories: recipe.calories,
                                   proteinG: recipe.protein, carbsG: recipe.carbs,
                                   fatG: recipe.fat, fiberG: recipe.fiber, isRecipe: true)
            try? db.saveFavorite(&fav)
        }

        UserDefaults.standard.set(true, forKey: seededKey)
        Log.app.info("Seeded \(topFoods.count) food usage entries + \(recipes.count) recipes")
    }

    // MARK: - Top foods from MacroFactor logs (logged 5+ times)

    private static let topFoods: [(String, Int)] = [
        // Protein (most used)
        ("Whey Protein Powder, 24 Grams of Protein Per Scoop", 10),
        ("Chicken Meatballs", 10),
        ("Gold Standard Chocolate 100% Whey Protein", 5),
        ("Fully Cooked Chicken Breast Bites", 5),
        ("Egg Scrambled", 5),
        ("Atlantic Salmon", 3),

        // Eggs & Dairy
        ("Organic Large Grade a Eggs", 8),
        ("Organic Large Grade A Eggs By Kirkland Signature", 8),
        ("Organic Plain Greek Yogurt", 5),
        ("2% Milk", 5),
        ("Milk, Whole", 4),
        ("Fage Total 2% With Blueberry", 3),

        // Indian staples
        ("Toor Dal", 8),
        ("Uncooked Whole Durum Wheat Flour Phulka", 5),
        ("Roti (Indian Bread), Whole Wheat", 5),
        ("Moong Daal", 4),
        ("Quinoa, Dry", 8),

        // Salad kits
        ("Organic Mediterranean Style Salad Kit", 5),
        ("Lemon Tahini Crunch Chopped Salad Kit", 4),
        ("Dill-Icious Chopped Salad Kit", 3),
        ("Avocado Ranch Salad Kit", 3),
        ("Miso Crunch Chopped Salad Kit", 3),

        // Fruits & nuts
        ("Banana, Fresh", 5),
        ("Avocados Raw", 5),
        ("Blueberries, Fresh", 4),
        ("Pistachio Nuts, Roasted, Salted", 4),
        ("Almonds, Raw", 3),
        ("Walnuts", 3),
        ("Chia Seeds", 3),

        // Oils & supplements
        ("MCT Oil", 5),
        ("Avocado Oil", 4),
        ("Ag1", 3),

        // Oatmeal
        ("Cereals, Quaker, Quick Oats, Dry", 3),
    ]

    // MARK: - Pre-built recipes from common meals

    private struct Recipe {
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let fiber: Double
    }

    private static let recipes: [Recipe] = [
        // Costco bowls
        Recipe(name: "Costco Santa Fe Chicken Bowl", calories: 410, protein: 22, carbs: 46, fat: 16, fiber: 5),

        // Trader Joe's / Whole Foods meals
        Recipe(name: "TJ's Harvest Bowl", calories: 450, protein: 20, carbs: 54, fat: 18, fiber: 8),
        Recipe(name: "TJ's Chicken Tikka Masala + Rice", calories: 550, protein: 28, carbs: 60, fat: 18, fiber: 3),

        // Protein shake combos
        Recipe(name: "Morning Protein Shake", calories: 280, protein: 50, carbs: 12, fat: 4, fiber: 2),
        Recipe(name: "Post-Workout Shake (2 scoops + milk)", calories: 370, protein: 56, carbs: 20, fat: 8, fiber: 0),

        // Indian meals
        Recipe(name: "Dal + Rice + Roti", calories: 520, protein: 20, carbs: 85, fat: 8, fiber: 12),
        Recipe(name: "Egg Bhurji + 2 Rotis", calories: 420, protein: 22, carbs: 38, fat: 20, fiber: 4),
        Recipe(name: "Chole + Rice", calories: 480, protein: 16, carbs: 72, fat: 12, fiber: 10),

        // Quick meals
        Recipe(name: "Salad Kit + Chicken Meatballs (6)", calories: 380, protein: 28, carbs: 16, fat: 22, fiber: 4),
        Recipe(name: "Greek Yogurt + Berries + Nuts", calories: 300, protein: 22, carbs: 28, fat: 10, fiber: 4),
        Recipe(name: "Oatmeal + Banana + Protein", calories: 420, protein: 32, carbs: 56, fat: 8, fiber: 6),
    ]
}
