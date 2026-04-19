import Foundation

/// SavedFood is now a typealias for Food — all food types live in one table.
/// Use source="recipe" for recipes, source="custom" for user-created entries.
typealias SavedFood = Food

extension Food {
    /// Convenience init matching the old SavedFood signature for backwards compatibility.
    init(id: Int64? = nil, name: String, calories: Double, proteinG: Double = 0, carbsG: Double = 0,
         fatG: Double = 0, fiberG: Double = 0, defaultServings: Double = 1, isRecipe: Bool = false,
         sortOrder: Int = 0, createdAt: String = ISO8601DateFormatter().string(from: Date()),
         ingredients: String? = nil, expandOnLog: Bool = false) {
        self.init(id: id, name: name,
                  category: isRecipe ? "Recipe" : "Saved",
                  servingSize: 1, servingUnit: "serving",
                  calories: calories, proteinG: proteinG, carbsG: carbsG,
                  fatG: fatG, fiberG: fiberG,
                  ingredients: ingredients, source: "recipe",
                  isRecipe: isRecipe, sortOrder: sortOrder, defaultServings: defaultServings,
                  expandOnLog: expandOnLog)
    }
}
