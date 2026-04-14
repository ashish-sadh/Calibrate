import Foundation
import Testing
@testable import Drift

// MARK: - Widget Data Provider Tests

@Test @MainActor func widgetDataWritesToSharedDefaults() async throws {
    let defaults = UserDefaults(suiteName: "group.com.drift.health")!
    // Clear any previous data
    defaults.removeObject(forKey: WidgetDataProvider.caloriesEatenKey)
    defaults.removeObject(forKey: WidgetDataProvider.calorieTargetKey)
    defaults.removeObject(forKey: WidgetDataProvider.dateKey)

    WidgetDataProvider.refreshWidgetData()

    // Should write a calorie target (always > 0 even with no goal)
    let target = defaults.integer(forKey: WidgetDataProvider.calorieTargetKey)
    #expect(target > 0, "Calorie target should be positive, got \(target)")

    // Should write today's date
    let date = defaults.string(forKey: WidgetDataProvider.dateKey)
    let todayStr = DateFormatters.todayString
    #expect(date == todayStr, "Widget date should be today: expected \(todayStr), got \(date ?? "nil")")

    // Should write a last-updated timestamp
    let lastUpdated = defaults.double(forKey: WidgetDataProvider.lastUpdatedKey)
    #expect(lastUpdated > 0, "Last updated timestamp should be set")
}

@Test @MainActor func widgetDataCaloriesMatchFoodService() async throws {
    let totals = FoodService.getDailyTotals()
    let defaults = UserDefaults(suiteName: "group.com.drift.health")!

    WidgetDataProvider.refreshWidgetData()

    let eaten = defaults.integer(forKey: WidgetDataProvider.caloriesEatenKey)
    let target = defaults.integer(forKey: WidgetDataProvider.calorieTargetKey)
    let remaining = defaults.integer(forKey: WidgetDataProvider.caloriesRemainingKey)
    let proteinG = defaults.integer(forKey: WidgetDataProvider.proteinGKey)
    let carbsG = defaults.integer(forKey: WidgetDataProvider.carbsGKey)
    let fatG = defaults.integer(forKey: WidgetDataProvider.fatGKey)

    #expect(eaten == totals.eaten, "Eaten mismatch: widget \(eaten) vs service \(totals.eaten)")
    #expect(target == totals.target, "Target mismatch: widget \(target) vs service \(totals.target)")
    #expect(remaining == totals.remaining, "Remaining mismatch: widget \(remaining) vs service \(totals.remaining)")
    #expect(proteinG == totals.proteinG, "Protein mismatch: widget \(proteinG) vs service \(totals.proteinG)")
    #expect(carbsG == totals.carbsG, "Carbs mismatch")
    #expect(fatG == totals.fatG, "Fat mismatch")
}

@Test @MainActor func widgetSharedDefaultsKeysAreConsistent() async throws {
    // Verify keys match between provider and what widget reads
    #expect(WidgetDataProvider.caloriesEatenKey == "widget_calories_eaten")
    #expect(WidgetDataProvider.calorieTargetKey == "widget_calorie_target")
    #expect(WidgetDataProvider.caloriesRemainingKey == "widget_calories_remaining")
    #expect(WidgetDataProvider.proteinGKey == "widget_protein_g")
    #expect(WidgetDataProvider.carbsGKey == "widget_carbs_g")
    #expect(WidgetDataProvider.fatGKey == "widget_fat_g")
    #expect(WidgetDataProvider.dateKey == "widget_date")
    #expect(WidgetDataProvider.lastUpdatedKey == "widget_last_updated")
}

@Test @MainActor func widgetDataRefreshIsIdempotent() async throws {
    let defaults = UserDefaults(suiteName: "group.com.drift.health")!

    WidgetDataProvider.refreshWidgetData()
    let target1 = defaults.integer(forKey: WidgetDataProvider.calorieTargetKey)
    let eaten1 = defaults.integer(forKey: WidgetDataProvider.caloriesEatenKey)

    WidgetDataProvider.refreshWidgetData()
    let target2 = defaults.integer(forKey: WidgetDataProvider.calorieTargetKey)
    let eaten2 = defaults.integer(forKey: WidgetDataProvider.caloriesEatenKey)

    #expect(target1 == target2, "Repeated refresh should produce same target")
    #expect(eaten1 == eaten2, "Repeated refresh should produce same eaten")
}
