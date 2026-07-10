import Foundation
import Testing
import GRDB
@testable import DriftCore

// AppDatabase.fetchSuggestionChips — the diary Suggestions strip. Tier 0,
// in-memory DB. Field report 2026-07-09: combos always rendered before any
// recent food; ranking must be unified most-clicked-first across both types.

private func makeDB() throws -> AppDatabase {
    let queue = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    Migrations.registerAll(&migrator)
    try migrator.migrate(queue)
    return try AppDatabase(queue)
}

@discardableResult
private func insertFood(_ db: AppDatabase, name: String, isRecipe: Bool = false) throws -> Int64 {
    try db.writer.write { dbc in
        var food = Food(name: name, category: isRecipe ? "Combo" : "Test",
                        servingSize: 100, servingUnit: isRecipe ? "serving" : "g",
                        calories: 200, proteinG: 10,
                        source: isRecipe ? "recipe" : nil, isRecipe: isRecipe)
        try food.insert(dbc)
        return dbc.lastInsertedRowID
    }
}

private func setUsage(_ db: AppDatabase, name: String, foodId: Int64?,
                      uses: Int, lastUsed: String, favorite: Bool = false) throws {
    try db.writer.write { dbc in
        try dbc.execute(sql: """
            INSERT INTO food_usage (food_name, food_id, use_count, last_used, last_servings, is_favorite)
            VALUES (?, ?, ?, ?, 1, ?)
            """, arguments: [name, foodId, uses, lastUsed, favorite])
    }
}

@Test func mostClickedFirstRegardlessOfType() throws {
    let db = try makeDB()
    let comboId = try insertFood(db, name: "Dal + Rice", isRecipe: true)
    let foodId = try insertFood(db, name: "Khichdi")
    try setUsage(db, name: "Dal + Rice", foodId: comboId, uses: 2, lastUsed: "2026-07-09T10:00:00Z")
    try setUsage(db, name: "Khichdi", foodId: foodId, uses: 7, lastUsed: "2026-07-01T10:00:00Z")

    let chips = try db.fetchSuggestionChips()
    // 7-click food beats 2-click combo even though the combo was used more recently
    #expect(chips.map(\.name) == ["Khichdi", "Dal + Rice"])
}

@Test func favoriteOutranksClickCount() throws {
    let db = try makeDB()
    let comboId = try insertFood(db, name: "Usual Breakfast", isRecipe: true)
    let foodId = try insertFood(db, name: "Avocado")
    try setUsage(db, name: "Usual Breakfast", foodId: comboId, uses: 1, lastUsed: "2026-07-01T08:00:00Z", favorite: true)
    try setUsage(db, name: "Avocado", foodId: foodId, uses: 20, lastUsed: "2026-07-09T08:00:00Z")

    let chips = try db.fetchSuggestionChips()
    #expect(chips.first?.name == "Usual Breakfast")
}

@Test func lastUsedBreaksClickTies() throws {
    let db = try makeDB()
    let aId = try insertFood(db, name: "Roti")
    let bId = try insertFood(db, name: "Paneer")
    try setUsage(db, name: "Roti", foodId: aId, uses: 3, lastUsed: "2026-07-01T12:00:00Z")
    try setUsage(db, name: "Paneer", foodId: bId, uses: 3, lastUsed: "2026-07-08T12:00:00Z")

    let chips = try db.fetchSuggestionChips()
    #expect(chips.map(\.name) == ["Paneer", "Roti"])
}

@Test func neverUsedComboStillIncludedAtBottom() throws {
    let db = try makeDB()
    try insertFood(db, name: "Fresh Auto Combo", isRecipe: true) // no usage row
    let foodId = try insertFood(db, name: "Egg")
    try setUsage(db, name: "Egg", foodId: foodId, uses: 4, lastUsed: "2026-07-09T08:00:00Z")

    let chips = try db.fetchSuggestionChips()
    #expect(chips.map(\.name) == ["Egg", "Fresh Auto Combo"])
}

@Test func plainFoodWithoutUsageExcluded() throws {
    let db = try makeDB()
    try insertFood(db, name: "Never Logged Curd")
    let chips = try db.fetchSuggestionChips()
    #expect(!chips.contains { $0.name == "Never Logged Curd" })
}

@Test func trackFoodUsageSurfacesFoodInChips() throws {
    let db = try makeDB()
    let foodId = try insertFood(db, name: "Tofu")
    try db.trackFoodUsage(name: "Tofu", foodId: foodId, servings: 1, calories: 150)

    let chips = try db.fetchSuggestionChips()
    #expect(chips.contains { $0.name == "Tofu" })
}

@Test func usageRowJoinsRecipeByNameWithoutFoodId() throws {
    let db = try makeDB()
    // Older builds tracked combo usage with foodId=nil — join must fall back to name.
    try insertFood(db, name: "Chole + Rice", isRecipe: true)
    let foodId = try insertFood(db, name: "Milk")
    try setUsage(db, name: "chole + rice", foodId: nil, uses: 9, lastUsed: "2026-07-09T13:00:00Z")
    try setUsage(db, name: "Milk", foodId: foodId, uses: 5, lastUsed: "2026-07-09T08:00:00Z")

    let chips = try db.fetchSuggestionChips()
    #expect(chips.map(\.name) == ["Chole + Rice", "Milk"])
}

@Test func respectsLimit() throws {
    let db = try makeDB()
    for i in 1...6 {
        let id = try insertFood(db, name: "Food \(i)")
        try setUsage(db, name: "Food \(i)", foodId: id, uses: i, lastUsed: "2026-07-0\(min(i, 9))T08:00:00Z")
    }
    let chips = try db.fetchSuggestionChips(limit: 3)
    #expect(chips.map(\.name) == ["Food 6", "Food 5", "Food 4"])
}
