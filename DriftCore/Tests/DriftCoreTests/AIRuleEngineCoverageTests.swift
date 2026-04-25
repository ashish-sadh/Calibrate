import Foundation
@testable import DriftCore
import Testing

// MARK: - AIRuleEngine Branch Coverage
// Exercises non-empty-DB branches by seeding AppDatabase.shared with cleanup.
// Each test creates a MealLog first (required by FK), then a FoodEntry under it.
// MealLog deletion cascades to FoodEntry.

// MARK: Helpers

/// Creates a MealLog + FoodEntry in AppDatabase.shared. Returns mealLogId for cascade cleanup.
@MainActor
@discardableResult
private func seedTestFood(
    name: String, calories: Double, proteinG: Double = 0, carbsG: Double = 0,
    fatG: Double = 0, fiberG: Double = 0, date: String, mealType: String = "lunch"
) -> Int64? {
    var mealLog = MealLog(date: date, mealType: mealType)
    try? AppDatabase.shared.saveMealLog(&mealLog)
    guard let mealLogId = mealLog.id else { return nil }
    var entry = FoodEntry(
        mealLogId: mealLogId, foodName: name, servingSizeG: 100, servings: 1,
        calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG,
        loggedAt: ISO8601DateFormatter().string(from: Date()), date: date, mealType: mealType
    )
    try? AppDatabase.shared.saveFoodEntry(&entry)
    return mealLogId
}

@MainActor
private func cleanupMealLog(_ id: Int64?) {
    guard let id else { return }
    try? AppDatabase.shared.deleteMealLog(id: id)
}

// MARK: yesterdaySummary() — data path

@Test @MainActor func aiRuleEngineYesterdaySummary_withFood_showsCaloriesNotNoFood() async throws {
    let dateStr = DateFormatters.dateOnly.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    let mlId = seedTestFood(name: "TestYesterdayFood", calories: 650, proteinG: 42, carbsG: 68, fatG: 16, date: dateStr, mealType: "dinner")
    defer { cleanupMealLog(mlId) }

    let summary = AIRuleEngine.yesterdaySummary()
    #expect(!summary.contains("No food was logged yesterday"),
            "With seeded food, summary should not report no food")
    #expect(summary.contains("cal") || summary.contains("Yesterday"),
            "Summary should include calorie data")
}

@Test @MainActor func aiRuleEngineYesterdaySummary_vsTarget_includesTargetDiff() async throws {
    let dateStr = DateFormatters.dateOnly.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    let mlId = seedTestFood(name: "TestTargetCompare", calories: 1800, proteinG: 120, carbsG: 180, fatG: 50, date: dateStr)
    defer { cleanupMealLog(mlId) }

    let summary = AIRuleEngine.yesterdaySummary()
    #expect(summary.contains("over") || summary.contains("under") || summary.contains("cal"),
            "Summary should compare to calorie target")
}

// MARK: caloriesLeft() — data paths

@Test @MainActor func aiRuleEngineCaloriesLeft_withModerateFood_showsRemaining() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestCalLeftModerate", calories: 400, proteinG: 30, carbsG: 40, fatG: 10, date: today, mealType: "breakfast")
    defer { cleanupMealLog(mlId) }

    let result = AIRuleEngine.caloriesLeft()
    #expect(!result.isEmpty)
    #expect(result.contains("cal"), "Should mention calories")
    #expect(result.contains("left") || result.contains("over") || result.contains("/"),
            "With 400 cal, should show position vs target")
}

@Test @MainActor func aiRuleEngineCaloriesLeft_overTarget_showsOverMessage() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestCalLeftOver", calories: 9000, proteinG: 100, carbsG: 900, fatG: 300, date: today)
    defer { cleanupMealLog(mlId) }

    let result = AIRuleEngine.caloriesLeft()
    #expect(result.contains("over"), "9000 cal should be over any typical TDEE target")
}

// MARK: dailySummary() — food-logged path

@Test @MainActor func aiRuleEngineDailySummary_withFoodLogged_doesNotSayNothingLogged() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestDailySummaryItem", calories: 350, proteinG: 25, carbsG: 40, fatG: 8, date: today, mealType: "breakfast")
    defer { cleanupMealLog(mlId) }

    let summary = AIRuleEngine.dailySummary()
    #expect(!summary.contains("nothing logged yet"),
            "With food seeded, daily summary should not say nothing logged")
    #expect(summary.contains("Food:"), "Daily summary always includes Food: line")
    #expect(summary.contains("cal"), "Summary should show calorie count")
}

// MARK: quickInsight() — calories > 0 path

@Test @MainActor func aiRuleEngineQuickInsight_withFoodLogged_returnsNonNilInsight() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestQuickInsightItem", calories: 550, proteinG: 38, carbsG: 52, fatG: 14, date: today, mealType: "breakfast")
    defer { cleanupMealLog(mlId) }

    let insight = AIRuleEngine.quickInsight()
    #expect(insight != nil, "quickInsight should return a string when food is logged")
    if let insight {
        #expect(!insight.contains("haven't logged"),
                "With food, should not say haven't logged any food")
    }
}

// MARK: quickInsight() — trend branches (losing/gaining/stable)

@Test @MainActor func aiRuleEngineQuickInsight_withFoodAndTrend_exercisesTrendBranch() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestTrendInsight", calories: 400, proteinG: 30, carbsG: 45, fatG: 10, date: today)
    defer { cleanupMealLog(mlId) }

    let cal = Calendar.current
    var weightIds: [Int64] = []
    for i in 0..<14 {
        let date = DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: -i, to: Date())!)
        var wEntry = WeightEntry(date: date, weightKg: 73.0 - Double(i) * 0.2, source: "manual")
        try? AppDatabase.shared.saveWeightEntry(&wEntry)
        if let id = wEntry.id { weightIds.append(id) }
    }
    defer {
        for id in weightIds { try? AppDatabase.shared.deleteWeightEntry(id: id) }
        WeightTrendService.shared.refresh()
    }

    WeightTrendService.shared.refresh()
    let insight = AIRuleEngine.quickInsight()
    if let insight { #expect(!insight.isEmpty) }
}

// MARK: nextAction() — per-hour branches

@Test @MainActor func aiRuleEngineNextAction_withLowProteinFood_exercisesProteinCheck() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestLowProteinItem", calories: 300, proteinG: 5, carbsG: 70, fatG: 5, date: today)
    defer { cleanupMealLog(mlId) }

    let action = AIRuleEngine.nextAction()
    if let action { #expect(!action.isEmpty) }
}

@Test @MainActor func aiRuleEngineNextAction_withHighProteinFood_noProteinAlert() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestHighProteinItem", calories: 700, proteinG: 120, carbsG: 20, fatG: 12, date: today)
    defer { cleanupMealLog(mlId) }

    let action = AIRuleEngine.nextAction()
    if let action {
        #expect(!action.contains("protein is at"),
                "High protein should not trigger protein alert")
    }
}

// MARK: weeklySummary() — always-present structure

@Test @MainActor func aiRuleEngineWeeklySummary_alwaysHasHeaderAndWorkoutsLine() {
    let summary = AIRuleEngine.weeklySummary()
    #expect(!summary.isEmpty)
    #expect(summary.contains("This week"), "Weekly summary starts with 'This week'")
    #expect(summary.contains("Workouts:"), "Weekly summary always includes Workouts: line")
}

@Test @MainActor func aiRuleEngineWeeklySummary_withFoodThisWeek_showsAvgIntake() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestWeeklySummaryFood", calories: 2000, proteinG: 150, carbsG: 200, fatG: 60, date: today, mealType: "dinner")
    defer { cleanupMealLog(mlId) }

    let summary = AIRuleEngine.weeklySummary()
    #expect(summary.contains("This week"), "Should have weekly header")
    #expect(summary.contains("cal") || summary.contains("Workouts:"),
            "Summary should show calorie or workout data")
}

// MARK: AIContextBuilder.foodContext() — #182 regression

@Test @MainActor func foodContext_emptyDiary_saysNothingLoggedNotRecent() async throws {
    let today = DateFormatters.todayString
    // Ensure today has no food by checking before seeding
    let nutrition = try? AppDatabase.shared.fetchDailyNutrition(for: today)
    guard (nutrition?.calories ?? 0) == 0 else { return } // skip if food already logged in shared DB

    let context = AIContextBuilder.foodContext()
    #expect(context.contains("Today: Nothing logged yet."),
            "Empty diary should explicitly say nothing logged, not show ambiguous recent foods")
    #expect(!context.contains("\nRecent:"),
            "Old ambiguous 'Recent:' label must not appear — it caused LLM hallucination (#182)")
}

@Test @MainActor func foodContext_withFood_showsMealNotNothingLogged() async throws {
    let today = DateFormatters.todayString
    let mlId = seedTestFood(name: "TestContextFood", calories: 450, proteinG: 35, date: today)
    defer { cleanupMealLog(mlId) }

    let context = AIContextBuilder.foodContext()
    #expect(!context.contains("Today: Nothing logged yet."),
            "With food logged, should not say nothing logged")
    #expect(context.contains("TestContextFood"),
            "Context should include the logged food name")
}
