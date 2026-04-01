import Foundation

/// Seeds recipe favorites on first launch. Does NOT pre-seed recents.
enum DefaultFoods {
    private static let seededKey = "drift_default_foods_seeded_v1"

    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let db = AppDatabase.shared

        // Only seed recipe favorites — no fake "recent" usage data
        for recipe in recipes {
            var fav = FavoriteFood(name: recipe.name, calories: recipe.calories,
                                   proteinG: recipe.protein, carbsG: recipe.carbs,
                                   fatG: recipe.fat, fiberG: recipe.fiber, isRecipe: true)
            try? db.saveFavorite(&fav)
        }

        UserDefaults.standard.set(true, forKey: seededKey)
        Log.app.info("Seeded \(recipes.count) recipe favorites")
    }

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
