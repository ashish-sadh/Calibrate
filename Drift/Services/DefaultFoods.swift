import Foundation
import DriftCore

/// Seeds recipe favorites on first launch. Does NOT pre-seed recents.
enum DefaultFoods {
    private static let seededKey = "drift_default_foods_seeded_v1"

    static func seedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }
        let db = AppDatabase.shared

        // Only seed recipe favorites — no fake "recent" usage data
        for recipe in recipes {
            let ingredientsJson = recipe.ingredients.flatMap { arr in
                (try? JSONEncoder().encode(arr)).flatMap { String(data: $0, encoding: .utf8) }
            }
            var fav = SavedFood(name: recipe.name, calories: recipe.calories,
                                   proteinG: recipe.protein, carbsG: recipe.carbs,
                                   fatG: recipe.fat, fiberG: recipe.fiber, isRecipe: true,
                                   ingredients: ingredientsJson)
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
        let ingredients: [String]?

        init(name: String, calories: Double, protein: Double, carbs: Double,
             fat: Double, fiber: Double, ingredients: [String]? = nil) {
            self.name = name; self.calories = calories; self.protein = protein
            self.carbs = carbs; self.fat = fat; self.fiber = fiber; self.ingredients = ingredients
        }
    }

    private static let recipes: [Recipe] = [
        // Costco bowls
        Recipe(name: "Costco Santa Fe Chicken Bowl", calories: 410, protein: 22, carbs: 46, fat: 16, fiber: 5,
               ingredients: ["rice", "beans", "corn", "bell pepper", "onion"]),

        // Trader Joe's / Whole Foods meals
        Recipe(name: "TJ's Harvest Bowl", calories: 450, protein: 20, carbs: 54, fat: 18, fiber: 8,
               ingredients: ["quinoa", "sweet potato", "kale", "chickpeas"]),
        Recipe(name: "TJ's Chicken Tikka Masala + Rice", calories: 550, protein: 28, carbs: 60, fat: 18, fiber: 3,
               ingredients: ["rice", "tomato", "onion", "garam masala"]),

        // Protein shake combos
        Recipe(name: "Morning Protein Shake", calories: 280, protein: 50, carbs: 12, fat: 4, fiber: 2),
        Recipe(name: "Post-Workout Shake (2 scoops + milk)", calories: 370, protein: 56, carbs: 20, fat: 8, fiber: 0),

        // Indian meals
        Recipe(name: "Dal + Rice + Roti", calories: 520, protein: 20, carbs: 85, fat: 8, fiber: 12,
               ingredients: ["dal", "rice", "wheat"]),
        Recipe(name: "Egg Bhurji + 2 Rotis", calories: 420, protein: 22, carbs: 38, fat: 20, fiber: 4,
               ingredients: ["onion", "tomato", "green chili", "wheat"]),
        Recipe(name: "Chole + Rice", calories: 480, protein: 16, carbs: 72, fat: 12, fiber: 10,
               ingredients: ["chickpeas", "onion", "tomato", "rice", "garam masala"]),

        // Quick meals
        Recipe(name: "Salad Kit + Chicken Meatballs (6)", calories: 380, protein: 28, carbs: 16, fat: 22, fiber: 4,
               ingredients: ["romaine lettuce", "croutons"]),
        Recipe(name: "Greek Yogurt + Berries + Nuts", calories: 300, protein: 22, carbs: 28, fat: 10, fiber: 4,
               ingredients: ["yogurt", "blueberry", "strawberry", "almonds"]),
        Recipe(name: "Oatmeal + Banana + Protein", calories: 420, protein: 32, carbs: 56, fat: 8, fiber: 6,
               ingredients: ["oats", "banana"]),

        // Salad/Bowl templates (new — Sweetgreen-style starting points)
        Recipe(name: "Green Salad Base", calories: 150, protein: 8, carbs: 12, fat: 8, fiber: 5,
               ingredients: ["spinach", "romaine lettuce", "cucumber", "tomato"]),
        Recipe(name: "Grain Bowl Base", calories: 320, protein: 10, carbs: 52, fat: 8, fiber: 6,
               ingredients: ["quinoa", "brown rice", "kale", "sweet potato"]),
        Recipe(name: "Protein Bowl", calories: 450, protein: 40, carbs: 35, fat: 14, fiber: 4,
               ingredients: ["rice", "chicken", "broccoli", "edamame"]),
        Recipe(name: "Mediterranean Bowl", calories: 380, protein: 12, carbs: 42, fat: 18, fiber: 8,
               ingredients: ["quinoa", "cucumber", "tomato", "olive", "chickpeas", "feta"]),
        Recipe(name: "Poke Bowl", calories: 420, protein: 28, carbs: 50, fat: 12, fiber: 3,
               ingredients: ["rice", "avocado", "cucumber", "edamame", "sesame seeds"]),
    ]
}
