import Foundation
import DriftCore

extension FoodService {
    /// Log a recipe: aggregated single entry, or expanded (one entry per ingredient)
    /// when `recipe.expandOnLog == true` and ingredient items are available.
    /// Returns true if expanded (caller can decide feedback text).
    /// Lives in Drift app (not DriftCore) because it dispatches through
    /// `FoodLogViewModel`, an iOS-only ViewModel.
    @MainActor @discardableResult
    static func logRecipe(_ recipe: Food, servings: Double, mealType: MealType,
                          loggedAt: String? = nil, viewModel: FoodLogViewModel) -> Bool {
        if recipe.expandOnLog, let items = recipe.recipeItems, !items.isEmpty {
            // Batch so an N-ingredient recipe reloads + refreshes the widget once. (#949)
            viewModel.quickAddBatch(items.map { item in
                FoodLogViewModel.BatchFoodItem(
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
            })
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
}
