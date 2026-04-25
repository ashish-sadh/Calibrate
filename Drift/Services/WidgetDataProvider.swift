import Foundation
import DriftCore
import WidgetKit

/// Bridges daily nutrition data to the widget extension via App Groups UserDefaults.
/// Called after every food mutation (log, delete, edit) so the widget stays current.
@MainActor
enum WidgetDataProvider {

    private static let suiteName = "group.com.drift.health"

    // Shared keys — widget reads these
    static let caloriesEatenKey = "widget_calories_eaten"
    static let calorieTargetKey = "widget_calorie_target"
    static let caloriesRemainingKey = "widget_calories_remaining"
    static let proteinGKey = "widget_protein_g"
    static let carbsGKey = "widget_carbs_g"
    static let fatGKey = "widget_fat_g"
    static let proteinTargetKey = "widget_protein_target"
    static let carbsTargetKey = "widget_carbs_target"
    static let fatTargetKey = "widget_fat_target"
    static let lastUpdatedKey = "widget_last_updated"
    static let dateKey = "widget_date"

    /// Write current daily totals to shared UserDefaults and reload widget timelines.
    static func refreshWidgetData() {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }

        let totals = FoodService.getDailyTotals()
        let today = DateFormatters.todayString

        defaults.set(totals.eaten, forKey: caloriesEatenKey)
        defaults.set(totals.target, forKey: calorieTargetKey)
        defaults.set(totals.remaining, forKey: caloriesRemainingKey)
        defaults.set(totals.proteinG, forKey: proteinGKey)
        defaults.set(totals.carbsG, forKey: carbsGKey)
        defaults.set(totals.fatG, forKey: fatGKey)
        defaults.set(today, forKey: dateKey)
        defaults.set(Date().timeIntervalSince1970, forKey: lastUpdatedKey)

        // Write macro targets if a weight goal exists
        let currentKg = WeightTrendService.shared.latestWeightKg ?? 80
        if let goal = WeightGoal.load(), let macros = goal.macroTargets(currentWeightKg: currentKg) {
            defaults.set(Int(macros.proteinG), forKey: proteinTargetKey)
            defaults.set(Int(macros.carbsG), forKey: carbsTargetKey)
            defaults.set(Int(macros.fatG), forKey: fatTargetKey)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }
}
