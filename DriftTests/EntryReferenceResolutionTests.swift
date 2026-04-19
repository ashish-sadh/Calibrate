import Foundation
import Testing
@testable import Drift

/// End-to-end tests for multi-turn entry reference resolution (#227).
/// Seeds real DB rows, populates the ConversationState window, routes the
/// resulting delete/edit calls through the registered tools, and asserts
/// the right entry is affected — especially under duplicate-name conflict.

// MARK: - Shared helpers

@MainActor
@discardableResult
private func seedEntry(
    mealType: String, foodName: String,
    calories: Double = 200, servings: Double = 1, servingSizeG: Double = 100
) -> (mlId: Int64, entry: FoodEntry)? {
    let today = DateFormatters.todayString
    var mealLog = MealLog(date: today, mealType: mealType)
    try? AppDatabase.shared.saveMealLog(&mealLog)
    guard let mlId = mealLog.id else { return nil }
    var entry = FoodEntry(
        mealLogId: mlId, foodName: foodName,
        servingSizeG: servingSizeG, servings: servings,
        calories: calories, proteinG: 10,
        loggedAt: ISO8601DateFormatter().string(from: Date()),
        date: today, mealType: mealType
    )
    try? AppDatabase.shared.saveFoodEntry(&entry)
    return (mlId, entry)
}

@MainActor
private func cleanup(_ mlIds: Int64?...) {
    for case let id? in mlIds { try? AppDatabase.shared.deleteMealLog(id: id) }
}

@MainActor
private func pushToWindow(_ entry: FoodEntry, mealType: String) {
    guard let id = entry.id else { return }
    ConversationState.shared.pushRecentEntry(.init(
        id: id, name: entry.foodName, mealType: mealType,
        calories: Int(entry.calories), loggedAt: Date()
    ))
}

// MARK: - entry_id path picks the right row under duplicate names

@Test @MainActor func deleteByEntryIdPicksCorrectRowAmongDuplicates() {
    let state = ConversationState.shared
    state.reset()
    guard let lunch = seedEntry(mealType: "lunch", foodName: "DupRice227", calories: 180),
          let dinner = seedEntry(mealType: "dinner", foodName: "DupRice227", calories: 240)
    else {
        Issue.record("Seeding failed"); return
    }
    defer { cleanup(lunch.mlId, dinner.mlId) }

    // Window lists both; AI returns entry_id of the dinner row.
    pushToWindow(lunch.entry, mealType: "lunch")
    pushToWindow(dinner.entry, mealType: "dinner")
    guard let dinnerId = dinner.entry.id else { Issue.record("dinner id missing"); return }

    let msg = DeleteFoodHandler.run(params: ToolCallParams(values: [
        "entry_id": "\(dinnerId)", "name": "rice"
    ]))
    #expect(msg.contains("Removed"))
    #expect(state.recentEntries.contains(where: { $0.id == lunch.entry.id }))
    #expect(!state.recentEntries.contains(where: { $0.id == dinnerId }))
}

// MARK: - Ordinal "last" routes to newest window row

@Test @MainActor func deleteByOrdinalLastResolvesNewestWindowRow() {
    let state = ConversationState.shared
    state.reset()
    guard let first = seedEntry(mealType: "breakfast", foodName: "OrdFirst227", calories: 100),
          let last = seedEntry(mealType: "snack", foodName: "OrdLast227", calories: 50)
    else { Issue.record("Seeding failed"); return }
    defer { cleanup(first.mlId, last.mlId) }

    pushToWindow(first.entry, mealType: "breakfast")
    pushToWindow(last.entry, mealType: "snack")
    guard let lastId = last.entry.id else { Issue.record("last id missing"); return }

    let msg = DeleteFoodHandler.run(params: ToolCallParams(values: ["name": "last"]))
    #expect(msg.contains("Removed"))
    // The newest window entry (snack OrdLast227) should now be gone
    #expect(!state.recentEntries.contains(where: { $0.id == lastId }))
}

@Test @MainActor func deleteByOrdinalFirstResolvesOldestWindowRow() {
    let state = ConversationState.shared
    state.reset()
    guard let first = seedEntry(mealType: "breakfast", foodName: "OrdAlpha227", calories: 100),
          let second = seedEntry(mealType: "lunch", foodName: "OrdBeta227", calories: 200)
    else { Issue.record("Seeding failed"); return }
    defer { cleanup(first.mlId, second.mlId) }

    pushToWindow(first.entry, mealType: "breakfast")
    pushToWindow(second.entry, mealType: "lunch")

    let msg = DeleteFoodHandler.run(params: ToolCallParams(values: ["name": "first"]))
    #expect(msg.contains("Removed"))
    #expect(!state.recentEntries.contains(where: { $0.id == first.entry.id }))
    #expect(state.recentEntries.contains(where: { $0.id == second.entry.id }))
}

// MARK: - Stale entry_id degrades to name-match

@Test @MainActor func staleEntryIdFallsBackToNameMatch() {
    let state = ConversationState.shared
    state.reset()
    guard let seeded = seedEntry(mealType: "lunch", foodName: "FallbackRice227", calories: 160) else {
        Issue.record("Seeding failed"); return
    }
    defer { cleanup(seeded.mlId) }
    pushToWindow(seeded.entry, mealType: "lunch")

    // Inject a stale id that isn't in the window — resolver should reject it
    // and the name-match path should still delete the real row.
    let msg = DeleteFoodHandler.run(params: ToolCallParams(values: [
        "entry_id": "99999999",
        "name": "FallbackRice227"
    ]))
    #expect(msg.contains("Removed"))
}

// MARK: - edit_meal by entry_id skips meal-period filter

@Test @MainActor func editByEntryIdSucceedsWithoutMealPeriod() {
    let state = ConversationState.shared
    state.reset()
    guard let seeded = seedEntry(mealType: "dinner", foodName: "EditById227", calories: 300, servings: 1) else {
        Issue.record("Seeding failed"); return
    }
    defer { cleanup(seeded.mlId) }
    pushToWindow(seeded.entry, mealType: "dinner")
    guard let entryId = seeded.entry.id else { Issue.record("entry id missing"); return }

    let msg = EditMealHandler.run(params: ToolCallParams(values: [
        "entry_id": "\(entryId)",
        "action": "update_quantity",
        "new_value": "3"
    ]))
    #expect(msg.contains("Updated"))
    #expect(msg.contains("3 servings"))
}

// MARK: - Empty args prompts for clarification (no crash)

@Test @MainActor func editWithNoTargetAndNoEntryIdAsksForClarification() {
    ConversationState.shared.reset()
    let msg = EditMealHandler.run(params: ToolCallParams(values: ["action": "remove"]))
    #expect(msg.lowercased().contains("which"))
}
