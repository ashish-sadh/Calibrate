import Foundation
import Testing
import GRDB
@testable import DriftCore

// MARK: - FoodCSVExportTests (Tier 0)
// The food-log CSV export: full history (it used to stop 90 days back) + format.
// In-memory DB — no shared state.

private func makeTestDB() throws -> AppDatabase {
    let queue = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    Migrations.registerAll(&migrator)
    try migrator.migrate(queue)
    return try AppDatabase(queue)
}

@discardableResult
private func log(_ db: AppDatabase,
                 date: String,
                 food: String = "Dal",
                 servings: Double = 1.0,
                 calories: Double = 200,
                 withMealLog: Bool = true) throws -> FoodEntry {
    var mealLogId: Int64 = 0
    if withMealLog {
        var ml = MealLog(date: date, mealType: "lunch")
        try db.saveMealLog(&ml)
        mealLogId = ml.id!
    }
    var entry = FoodEntry(
        mealLogId: mealLogId, foodName: food, servingSizeG: 100, servings: servings,
        calories: calories, proteinG: 10, carbsG: 30, fatG: 5, fiberG: 2,
        createdAt: "\(date)T12:00:00Z", loggedAt: "\(date)T12:00:00Z",
        date: date, mealType: "lunch"
    )
    try db.saveFoodEntry(&entry)
    return entry
}

// MARK: - Full history (the bug)

@Test func exportIncludesEntriesOlderThan90Days() throws {
    let db = try makeTestDB()
    try log(db, date: "2024-01-15", food: "Old Roti")
    try log(db, date: "2025-06-01", food: "Older Dal")
    try log(db, date: "2026-08-16", food: "Fresh Idli")

    let rows = try db.fetchAllFoodEntriesForExport()
    #expect(rows.count == 3)
    #expect(rows.map(\.entry.foodName) == ["Old Roti", "Older Dal", "Fresh Idli"])  // oldest first
}

@Test func exportSpansEveryDayThatHasEntries() throws {
    let db = try makeTestDB()
    // 400 consecutive days — more than any fixed window would return.
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = .current
    let start = cal.date(from: DateComponents(year: 2025, month: 1, day: 1))!
    for offset in 0..<400 {
        let day = DateFormatters.dateOnly.string(from: cal.date(byAdding: .day, value: offset, to: start)!)
        try log(db, date: day, food: "Meal \(offset)")
    }

    let rows = try db.fetchAllFoodEntriesForExport()
    #expect(rows.count == 400)
    #expect(Set(rows.map(\.date)).count == 400)
}

@Test func exportFallsBackToMealLogDateWhenEntryHasNone() throws {
    let db = try makeTestDB()
    var ml = MealLog(date: "2023-03-04", mealType: "dinner")
    try db.saveMealLog(&ml)
    var entry = FoodEntry(
        mealLogId: ml.id!, foodName: "Legacy Poha", servingSizeG: 100, servings: 1,
        calories: 180, createdAt: "2023-03-04T19:00:00Z", loggedAt: "2023-03-04T19:00:00Z",
        date: nil
    )
    try db.saveFoodEntry(&entry)

    let rows = try db.fetchAllFoodEntriesForExport()
    #expect(rows.count == 1)
    #expect(rows.first?.date == "2023-03-04")
}

// MARK: - CSV format

@Test func csvHasHeaderAndOneLinePerEntry() throws {
    let db = try makeTestDB()
    try log(db, date: "2026-08-01", food: "Rajma")
    try log(db, date: "2026-08-02", food: "Chawal")

    let csv = FoodCSVExport.csv(rows: try db.fetchAllFoodEntriesForExport())
    let lines = csv.split(separator: "\n", omittingEmptySubsequences: false).dropLast()
    #expect(lines.count == 3)
    #expect(lines.first == "Date,Time,Food,Calories,Protein,Carbs,Fat,Fiber,Servings")
}

@Test func csvOfNoEntriesIsHeaderOnly() {
    #expect(FoodCSVExport.csv(rows: []) == FoodCSVExport.header)
}

@Test func csvScalesMacrosByServings() {
    let entry = FoodEntry(
        foodName: "Paneer", servingSizeG: 100, servings: 2.5,
        calories: 100, proteinG: 8, carbsG: 4, fatG: 6, fiberG: 1,
        loggedAt: "2026-08-16T13:30:00Z"
    )
    let csv = FoodCSVExport.csv(rows: [FoodExportRow(date: "2026-08-16", entry: entry)])
    let fields = csv.split(separator: "\n")[1].split(separator: ",", omittingEmptySubsequences: false)
    #expect(fields[0] == "\"2026-08-16\"")
    #expect(fields[2] == "\"Paneer\"")
    #expect(fields[3] == "250")   // calories
    #expect(fields[4] == "20")    // protein
    #expect(fields[5] == "10")    // carbs
    #expect(fields[6] == "15")    // fat
    #expect(fields[7] == "2")     // fiber
    #expect(fields[8] == "2.5")   // servings
}

@Test func csvEscapesQuotesInFoodNames() {
    let entry = FoodEntry(
        foodName: "Amul \"Masti\" Dahi", servingSizeG: 100, servings: 1,
        calories: 60, loggedAt: "2026-08-16T09:00:00Z"
    )
    let csv = FoodCSVExport.csv(rows: [FoodExportRow(date: "2026-08-16", entry: entry)])
    #expect(csv.contains("\"Amul \"\"Masti\"\" Dahi\""))
}
