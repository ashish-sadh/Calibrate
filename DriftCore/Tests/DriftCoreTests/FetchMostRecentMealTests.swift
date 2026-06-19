import Foundation
import Testing
import GRDB
@testable import DriftCore

// AppDatabase.fetchMostRecentMeal — powers "log my usual lunch". Tier 0,
// in-memory DB. #usual-meal

private func makeDB() throws -> AppDatabase {
    let queue = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    Migrations.registerAll(&migrator)
    try migrator.migrate(queue)
    return try AppDatabase(queue)
}

private func insert(_ db: AppDatabase, name: String, date: String, meal: String,
                    cal: Double, servings: Double, loggedAt: String) throws {
    var log = MealLog(date: date, mealType: meal)
    try db.saveMealLog(&log)
    var entry = FoodEntry(
        mealLogId: log.id!, foodName: name, servingSizeG: 100, servings: servings,
        calories: cal, proteinG: 5, carbsG: 40, fatG: 2, fiberG: 1,
        createdAt: "\(date)T12:00:00Z", loggedAt: loggedAt,
        date: date, mealType: meal)
    try db.saveFoodEntry(&entry)
}

@Test func returnsLatestMealOfTypeOnly() throws {
    let db = try makeDB()
    try insert(db, name: "Old Rice", date: "2026-05-01", meal: "lunch", cal: 200, servings: 1, loggedAt: "2026-05-01T12:00:00Z")
    try insert(db, name: "Roti", date: "2026-05-10", meal: "lunch", cal: 160, servings: 2, loggedAt: "2026-05-10T12:00:00Z")
    try insert(db, name: "Dal", date: "2026-05-10", meal: "lunch", cal: 180, servings: 1, loggedAt: "2026-05-10T12:01:00Z")
    try insert(db, name: "Paneer", date: "2026-05-10", meal: "dinner", cal: 300, servings: 1, loggedAt: "2026-05-10T20:00:00Z")

    let now = DateFormatters.dateOnly.date(from: "2026-05-12")!
    let meal = db.fetchMostRecentMeal(forType: "lunch", withinDays: 30, now: now)
    #expect(meal.count == 2)
    #expect(Set(meal.map(\.foodName)) == ["Roti", "Dal"])   // newest lunch, both items
    #expect(!meal.contains { $0.foodName == "Old Rice" })    // not the older lunch
    #expect(!meal.contains { $0.foodName == "Paneer" })      // not the dinner
}

@Test func emptyWhenNoHistory() throws {
    let db = try makeDB()
    let now = DateFormatters.dateOnly.date(from: "2026-05-12")!
    #expect(db.fetchMostRecentMeal(forType: "lunch", now: now).isEmpty)
}

@Test func ignoresMealsOutsideWindow() throws {
    let db = try makeDB()
    try insert(db, name: "Ancient", date: "2026-01-01", meal: "lunch", cal: 200, servings: 1, loggedAt: "2026-01-01T12:00:00Z")
    let now = DateFormatters.dateOnly.date(from: "2026-05-12")!
    #expect(db.fetchMostRecentMeal(forType: "lunch", withinDays: 30, now: now).isEmpty)
}
