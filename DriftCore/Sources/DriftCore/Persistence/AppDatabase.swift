import Foundation
import GRDB
import CryptoKit

/// The main application database providing read-write access to all user data.
public struct AppDatabase: @unchecked Sendable {
    private let dbWriter: any DatabaseWriter

    init(_ dbWriter: any DatabaseWriter) throws {
        self.dbWriter = dbWriter
        try migrator.migrate(dbWriter)
    }

    /// The database migrator that defines all schema migrations.
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        Migrations.registerAll(&migrator)
        return migrator
    }
}

// MARK: - Database Access

extension AppDatabase {
    /// Provides read access.
    public var reader: any DatabaseReader { dbWriter }

    /// Provides write access.
    public var writer: any DatabaseWriter { dbWriter }

    /// Delete ALL data from ALL tables. Nuclear option for factory reset.
    public func factoryReset() throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM food_entry")
            try db.execute(sql: "DELETE FROM meal_log")
            try db.execute(sql: "DELETE FROM weight_entry")
            try db.execute(sql: "DELETE FROM supplement_log")
            try db.execute(sql: "DELETE FROM supplement")
            try db.execute(sql: "DELETE FROM glucose_reading")
            try db.execute(sql: "DELETE FROM dexa_region")
            try db.execute(sql: "DELETE FROM dexa_scan")
            try db.execute(sql: "DELETE FROM hk_sync_anchor")
            try db.execute(sql: "DELETE FROM barcode_cache")
            try db.execute(sql: "DELETE FROM food")
            try db.execute(sql: "DELETE FROM biomarker_result")
            try db.execute(sql: "DELETE FROM lab_report")
            try db.execute(sql: "DELETE FROM workout_set")
            try db.execute(sql: "DELETE FROM workout")
            try db.execute(sql: "DELETE FROM workout_template")
            try db.execute(sql: "DELETE FROM saved_food")  // legacy table (may be empty after v25)
            try db.execute(sql: "DELETE FROM food WHERE source != 'database' AND source IS NOT NULL")
            try db.execute(sql: "DELETE FROM food_usage")
            try? db.execute(sql: "DELETE FROM chat_turn")
        }
        // Clear the seed hash so seedFoodsFromJSON() actually runs (hash-gated
        // skip otherwise — would leave the food table empty after the wipe).
        UserDefaults.standard.removeObject(forKey: Self.foodsJSONHashKey)
        // Re-seed default foods
        try seedFoodsFromJSON()
        Log.database.info("Factory reset complete - all data deleted, foods re-seeded")
    }
}

// MARK: - Weight Entry Operations

extension AppDatabase {
    public func saveWeightEntry(_ entry: inout WeightEntry) throws {
        try dbWriter.write { [entry] db in
            // Upsert: if date already exists, update the weight (with priority rules)
            if let existing = try WeightEntry.filter(Column("date") == entry.date).fetchOne(db) {
                // Don't overwrite manual entries with HealthKit data
                if existing.source == "manual" && entry.source == "healthkit" { return }
                // Don't overwrite user-deleted entries with HealthKit data
                if existing.hidden && entry.source == "healthkit" { return }
                var updated = existing
                updated.weightKg = entry.weightKg
                updated.source = entry.source
                updated.syncedFromHk = entry.syncedFromHk
                updated.hidden = false  // un-hide if manually re-added
                try updated.update(db)
            } else {
                var mutable = entry
                try mutable.insert(db)
            }
        }
        entry = try dbWriter.read { db in
            try WeightEntry.filter(Column("date") == entry.date).fetchOne(db)
        } ?? entry
    }

    public func deleteWeightEntry(id: Int64) throws {
        try dbWriter.write { db in
            // Soft-delete: mark hidden instead of deleting (prevents HealthKit re-sync)
            try db.execute(sql: "UPDATE weight_entry SET hidden = 1 WHERE id = ?", arguments: [id])
        }
    }

    public func fetchWeightEntries(from startDate: String? = nil, to endDate: String? = nil) throws -> [WeightEntry] {
        try dbWriter.read { db in
            var request = WeightEntry.filter(Column("hidden") == false).order(Column("date").desc)
            if let start = startDate {
                request = request.filter(Column("date") >= start)
            }
            if let end = endDate {
                request = request.filter(Column("date") <= end)
            }
            return try request.fetchAll(db)
        }
    }

    func fetchLatestWeight() throws -> WeightEntry? {
        try dbWriter.read { db in
            try WeightEntry.order(Column("date").desc).fetchOne(db)
        }
    }
}

// MARK: - Meal Log Operations

extension AppDatabase {
    public func saveMealLog(_ log: inout MealLog) throws {
        let isNew = log.id == nil
        try dbWriter.write { [log] db in
            var mutable = log
            try mutable.save(db)
        }
        if isNew {
            log = try dbWriter.read { db in
                try MealLog.filter(Column("date") == log.date).filter(Column("meal_type") == log.mealType).fetchOne(db)
            } ?? log
        }
    }

    func deleteMealLog(id: Int64) throws {
        try dbWriter.write { db in try MealLog.deleteOne(db, id: id) }
    }

    public func saveFoodEntry(_ entry: inout FoodEntry) throws {
        // Auto-populate date/mealType from meal_log if not set (backwards compat)
        if entry.date == nil && entry.mealLogId > 0 {
            if let ml = try? dbWriter.read({ db in try MealLog.fetchOne(db, id: entry.mealLogId) }) {
                entry.date = ml.date
                entry.mealType = ml.mealType
            }
        }
        let isNew = entry.id == nil
        try dbWriter.write { [entry] db in
            var mutable = entry
            try mutable.save(db)
        }
        if isNew {
            entry = try dbWriter.read { db in
                try FoodEntry.order(Column("id").desc).fetchOne(db)
            } ?? entry
        }
    }

    public func updateFoodEntryMacros(id: Int64, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double) throws {
        try dbWriter.write { db in
            try db.execute(sql: """
                UPDATE food_entry SET calories = ?, protein_g = ?, carbs_g = ?, fat_g = ?, fiber_g = ? WHERE id = ?
                """, arguments: [calories, proteinG, carbsG, fatG, fiberG, id])
        }
    }

    public func updateFoodEntryLoggedAt(id: Int64, loggedAt: String) throws {
        try dbWriter.write { db in
            try db.execute(sql: "UPDATE food_entry SET logged_at = ? WHERE id = ?", arguments: [loggedAt, id])
        }
    }

    public func updateFoodEntryMealType(id: Int64, mealType: String) throws {
        try dbWriter.write { db in
            try db.execute(sql: "UPDATE food_entry SET meal_type = ? WHERE id = ?", arguments: [mealType, id])
        }
    }

    public func updateFoodEntryName(id: Int64, name: String) throws {
        try dbWriter.write { db in
            try db.execute(sql: "UPDATE food_entry SET food_name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    public func updateFoodEntryServings(id: Int64, servings: Double) throws {
        try dbWriter.write { db in
            try db.execute(sql: "UPDATE food_entry SET servings = ? WHERE id = ?", arguments: [servings, id])
        }
    }

    public func deleteFoodEntry(id: Int64) throws {
        try dbWriter.write { db in
            // Get the meal_log_id before deleting
            let mealLogId = try Int64.fetchOne(db, sql: "SELECT meal_log_id FROM food_entry WHERE id = ?", arguments: [id])
            _ = try FoodEntry.deleteOne(db, id: id)
            // Clean up empty meal_logs (no remaining entries)
            if let mlId = mealLogId {
                let remaining = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM food_entry WHERE meal_log_id = ?", arguments: [mlId]) ?? 0
                if remaining == 0 {
                    try db.execute(sql: "DELETE FROM meal_log WHERE id = ?", arguments: [mlId])
                }
            }
        }
    }

    public func fetchMealLogs(for date: String) throws -> [MealLog] {
        try dbWriter.read { db in
            try MealLog.filter(Column("date") == date)
                .order(Column("id").asc)
                .fetchAll(db)
        }
    }

    /// Fetch all food entries for a given date. Uses date column (v26+) with meal_log fallback.
    public func fetchFoodEntries(for date: String) throws -> [FoodEntry] {
        try dbWriter.read { db in
            try FoodEntry.fetchAll(db, sql: """
                SELECT fe.* FROM food_entry fe
                LEFT JOIN meal_log ml ON fe.meal_log_id = ml.id
                WHERE fe.date = ? OR (fe.date IS NULL AND ml.date = ?)
                ORDER BY fe.logged_at DESC
                """, arguments: [date, date])
        }
    }

    public func fetchFoodEntries(forMealLog mealLogId: Int64) throws -> [FoodEntry] {
        try dbWriter.read { db in
            try FoodEntry
                .filter(Column("meal_log_id") == mealLogId)
                .order(Column("logged_at").asc)
                .fetchAll(db)
        }
    }

    public func fetchDailyNutrition(for date: String) throws -> DailyNutrition {
        try dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT
                    COALESCE(SUM(fe.calories * fe.servings), 0) as total_calories,
                    COALESCE(SUM(fe.protein_g * fe.servings), 0) as total_protein,
                    COALESCE(SUM(fe.carbs_g * fe.servings), 0) as total_carbs,
                    COALESCE(SUM(fe.fat_g * fe.servings), 0) as total_fat,
                    COALESCE(SUM(fe.fiber_g * fe.servings), 0) as total_fiber
                FROM food_entry fe
                LEFT JOIN meal_log ml ON fe.meal_log_id = ml.id
                WHERE fe.date = ? OR (fe.date IS NULL AND ml.date = ?)
                """, arguments: [date, date])

            return DailyNutrition(
                calories: row?["total_calories"] ?? 0,
                proteinG: row?["total_protein"] ?? 0,
                carbsG: row?["total_carbs"] ?? 0,
                fatG: row?["total_fat"] ?? 0,
                fiberG: row?["total_fiber"] ?? 0
            )
        }
    }

    /// Count of days with food logged in a date range.
    public func daysWithFoodLogged(from startDate: String, to endDate: String) throws -> Int {
        try dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT fe.date) as days
                FROM food_entry fe
                WHERE fe.date BETWEEN ? AND ?
                """, arguments: [startDate, endDate])
            return row?["days"] ?? 0
        }
    }

    /// Daily calorie totals for a date range (batch query for consistency heatmap).
    public func fetchDailyCalories(from startDate: String, to endDate: String) throws -> [String: Double] {
        try dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT fe.date, SUM(fe.calories * fe.servings) as total_cal
                FROM food_entry fe
                WHERE fe.date BETWEEN ? AND ?
                GROUP BY fe.date
                """, arguments: [startDate, endDate])
            var result: [String: Double] = [:]
            for row in rows {
                if let date: String = row["date"], let cal: Double = row["total_cal"] {
                    result[date] = cal
                }
            }
            return result
        }
    }

    /// Average daily calories over a date range (for TDEE estimation).
    public func averageDailyCalories(from startDate: String, to endDate: String) throws -> Double {
        try dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT AVG(daily_cal) as avg_cal FROM (
                    SELECT fe.date, SUM(fe.calories * fe.servings) as daily_cal
                    FROM food_entry fe
                    WHERE fe.date BETWEEN ? AND ?
                    GROUP BY fe.date
                    HAVING daily_cal > 200
                )
                """, arguments: [startDate, endDate])
            return row?["avg_cal"] ?? 0
        }
    }

    /// Unique ingredient names for plant points. Uses ingredients JSON when available, falls back to food_name.
    /// Fetch food items with ingredients + NOVA for plant points calculation.
    public func fetchFoodItemsForPlantPoints(from startDate: String, to endDate: String) throws -> [PlantPointsFoodItem] {
        try dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT fe.food_name,
                       COALESCE(f.ingredients, f2.ingredients) as ingredients,
                       COALESCE(f.nova_group, f2.nova_group) as nova_group
                FROM food_entry fe
                LEFT JOIN food f ON f.id = fe.food_id
                LEFT JOIN food f2 ON fe.food_id IS NULL AND LOWER(f2.name) = LOWER(fe.food_name)
                LEFT JOIN meal_log ml ON fe.meal_log_id = ml.id
                WHERE fe.date BETWEEN ? AND ?
                   OR (fe.date IS NULL AND ml.date BETWEEN ? AND ?)
                """, arguments: [startDate, endDate, startDate, endDate])
            return rows.map { row in
                let foodName: String = row["food_name"]
                let ingredientsJson: String? = row["ingredients"]
                let novaGroup: Int? = row["nova_group"]
                let ingredients: [String]? = ingredientsJson.flatMap { json in
                    guard let data = json.data(using: .utf8),
                          let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty else { return nil }
                    return arr
                }
                return PlantPointsFoodItem(name: foodName, ingredients: ingredients, novaGroup: novaGroup)
            }
        }
    }

    /// Legacy: unique ingredient names flattened (for backwards compat).
    func fetchUniqueIngredients(from startDate: String, to endDate: String) throws -> [String] {
        let items = try fetchFoodItemsForPlantPoints(from: startDate, to: endDate)
        var all: Set<String> = []
        for item in items {
            if let ingredients = item.ingredients, !ingredients.isEmpty {
                for i in ingredients { all.insert(i.lowercased()) }
            } else {
                all.insert(item.name.lowercased())
            }
        }
        return Array(all)
    }

    // Legacy fetchUniqueFoodNames and fetchUniqueFoodNamesByDay removed.
    // Use fetchFoodItemsForPlantPoints() or fetchUniqueIngredients() instead.
}

// MARK: - Supplement Operations

extension AppDatabase {
    public func saveSupplement(_ supplement: inout Supplement) throws {
        let isNew = supplement.id == nil
        try dbWriter.write { [supplement] db in
            var mutable = supplement
            try mutable.save(db)
        }
        if isNew {
            supplement = try dbWriter.read { db in
                try Supplement.filter(Column("name") == supplement.name).fetchOne(db)
            } ?? supplement
        }
    }

    func saveSupplementLog(_ log: inout SupplementLog) throws {
        try dbWriter.write { [log] db in
            var mutable = log
            try mutable.save(db)
        }
    }

    public func fetchActiveSupplements() throws -> [Supplement] {
        try dbWriter.read { db in
            try Supplement.filter(Column("is_active") == true)
                .order(Column("sort_order"))
                .fetchAll(db)
        }
    }

    public func fetchSupplementLogs(for date: String) throws -> [SupplementLog] {
        try dbWriter.read { db in
            try SupplementLog.filter(Column("date") == date).fetchAll(db)
        }
    }

    public func fetchSupplementLogs(from startDate: String, to endDate: String) throws -> [SupplementLog] {
        try dbWriter.read { db in
            try SupplementLog
                .filter(Column("date") >= startDate)
                .filter(Column("date") <= endDate)
                .order(Column("date"))
                .fetchAll(db)
        }
    }

    public func toggleSupplementTaken(supplementId: Int64, date: String) throws {
        try dbWriter.write { db in
            if var existing = try SupplementLog
                .filter(Column("supplement_id") == supplementId)
                .filter(Column("date") == date)
                .fetchOne(db) {
                existing.taken.toggle()
                existing.takenAt = existing.taken ? ISO8601DateFormatter().string(from: Date()) : nil
                try existing.update(db)
            } else {
                var log = SupplementLog(
                    supplementId: supplementId,
                    date: date,
                    taken: true,
                    takenAt: ISO8601DateFormatter().string(from: Date())
                )
                try log.insert(db)
            }
        }
    }
}

// MARK: - Glucose Operations

extension AppDatabase {
    public func saveGlucoseReadings(_ readings: [GlucoseReading]) throws {
        try dbWriter.write { db in
            for var reading in readings {
                try reading.insert(db)
            }
        }
    }

    public func fetchGlucoseReadings(from start: String, to end: String) throws -> [GlucoseReading] {
        try dbWriter.read { db in
            try GlucoseReading
                .filter(Column("timestamp") >= start)
                .filter(Column("timestamp") <= end)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }
}


    // DEXA Scan + Lab Report operations in AppDatabase+LabsAndScans.swift

// MARK: - HealthKit Sync Anchor

extension AppDatabase {
    public func saveAnchor(dataType: String, anchor: Data) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO hk_sync_anchor (data_type, last_anchor) VALUES (?, ?)",
                arguments: [dataType, anchor]
            )
        }
    }

    public func fetchAnchor(dataType: String) throws -> Data? {
        try dbWriter.read { db in
            try Data.fetchOne(db, sql: "SELECT last_anchor FROM hk_sync_anchor WHERE data_type = ?", arguments: [dataType])
        }
    }
}

// MARK: - Food Database (bundled read-only)

extension AppDatabase {
    /// UserDefaults key for the SHA-256 of the last-seeded `foods.json`. Used
    /// to skip the seed loop on launches where the bundle didn't change.
    private static let foodsJSONHashKey = "drift_foods_json_hash"

    /// Seed or refresh the food DB from the bundled `foods.json`.
    ///
    /// Runs on every cold start but exits in O(1) when `foods.json` hasn't
    /// changed since the last successful seed (SHA-256 compared against
    /// `UserDefaults`). The full 2.5k-row insert/update loop only runs:
    ///
    /// 1. On first install (no stored hash)
    /// 2. After an app update that ships a new `foods.json` (hash differs)
    /// 3. After `factoryReset` clears UserDefaults
    ///
    /// When the loop does run, JSON is authoritative for *all* nutrition
    /// fields, not just ingredients/NOVA. Previously calories + macros only
    /// got set at first-install and never refreshed — users who installed
    /// early versions kept seeing stale/wrong calories (e.g. "Coffee (with
    /// milk)" at 0 cal) even after the JSON was corrected. Refresh is
    /// scoped to DB-sourced rows; user-scanned foods (source='barcode',
    /// 'recipe', 'photo_log', 'custom') are never overwritten.
    public func seedFoodsFromJSON() throws {
        guard let url = Bundle.module.url(forResource: "foods", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return
        }

        // Hash-gate: skip the whole loop when the bundle bytes are identical
        // to the last successful seed AND the food table is non-empty. Turns
        // production cold start from ~2.5k SQL queries into a single
        // ~50µs SHA-256 hash + tiny COUNT(*) when nothing changed.
        //
        // The hash includes CFBundleVersion so every TestFlight bump forces
        // a one-time reseed even when foods.json bytes are unchanged. Users
        // reporting stale values ("Coffee with milk 0 cal") after an update
        // was the signal — JSON byte equality alone isn't enough since we
        // sometimes fix downstream code that affects how JSON is interpreted.
        //
        // The `foodCount > 0` guard matters for tests (each in-memory
        // `AppDatabase.empty()` gets a fresh food table, so without this
        // check the UserDefaults hash set by an earlier test would make
        // later tests skip seeding and see an empty DB).
        let bundleVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        var hashInput = Data(bundleVersion.utf8)
        hashInput.append(data)
        let currentHash = SHA256.hash(data: hashInput)
            .map { String(format: "%02x", $0) }
            .joined()
        let lastHash = UserDefaults.standard.string(forKey: Self.foodsJSONHashKey) ?? ""
        let foodCount = try dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM food") ?? 0
        }
        if foodCount > 0 && currentHash == lastHash {
            return
        }

        guard let foods = try? JSONDecoder().decode([Food].self, from: data) else { return }

        try dbWriter.write { db in
            // Delete stale photo_log rows that shadow a canonical JSON name.
            // These are ephemeral AI scans — if the JSON ships the same food
            // (e.g. "Coffee (with milk)"), the curated entry must win so
            // searches return the right macros. Without this, a past bad scan
            // with 0 cal blocks the seed UPDATE (WHERE source='database' skips
            // it) AND blocks the INSERT (name-exists check), leaving the user
            // permanently stuck on the 0-cal row.
            let jsonNames = foods.map { $0.name.lowercased() }
            if !jsonNames.isEmpty {
                let placeholders = Array(repeating: "?", count: jsonNames.count).joined(separator: ",")
                try db.execute(sql: """
                    DELETE FROM food
                    WHERE source = 'photo_log'
                      AND LOWER(name) IN (\(placeholders))
                    """, arguments: StatementArguments(jsonNames))
            }

            let existingNames = try Set(String.fetchAll(db, sql: "SELECT LOWER(name) FROM food"))

            for var food in foods {
                if !existingNames.contains(food.name.lowercased()) {
                    try food.insert(db)
                } else {
                    try db.execute(sql: """
                        UPDATE food SET
                            calories = ?,
                            protein_g = ?,
                            carbs_g = ?,
                            fat_g = ?,
                            fiber_g = ?,
                            serving_size = ?,
                            serving_unit = ?,
                            ingredients = COALESCE(?, ingredients),
                            nova_group = COALESCE(?, nova_group),
                            piece_size_g = ?,
                            cup_size_g = ?,
                            tbsp_size_g = ?,
                            scoop_size_g = ?,
                            bowl_size_g = ?
                        WHERE LOWER(name) = ?
                          AND (source IS NULL OR source = 'database')
                        """, arguments: [
                            food.calories, food.proteinG, food.carbsG, food.fatG, food.fiberG,
                            food.servingSize, food.servingUnit,
                            food.ingredients, food.novaGroup,
                            food.pieceSizeG, food.cupSizeG, food.tbspSizeG,
                            food.scoopSizeG, food.bowlSizeG,
                            food.name.lowercased()
                        ])
                }
            }
        }

        // Only write the hash after a successful seed so a mid-seed crash
        // leaves us in a state that retries on next launch.
        UserDefaults.standard.set(currentHash, forKey: Self.foodsJSONHashKey)
    }

    /// Escape SQL LIKE special characters in user input.
    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "%", with: "\\%")
         .replacingOccurrences(of: "_", with: "\\_")
    }

    /// Fetch foods by category, sorted by name.
    public func fetchFoodsByCategory(_ category: String, limit: Int = 20) throws -> [Food] {
        try dbWriter.read { db in
            try Food.filter(Column("category") == category)
                .order(Column("name"))
                .limit(limit)
                .fetchAll(db)
        }
    }

    public func searchFoods(query: String, limit: Int = 50) throws -> [Food] {
        try dbWriter.read { db in
            if query.isEmpty { return [] }
            let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if words.isEmpty { return [] }

            let whereClauses = words.map { _ in "LOWER(name) LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
            let patterns: [DatabaseValueConvertible] = words.map { "%\(Self.escapeLike($0))%" }
            let prefixPattern: DatabaseValueConvertible = "\(Self.escapeLike(query.lowercased()))%"
            let allArgs: [DatabaseValueConvertible] = patterns + [prefixPattern, limit]

            return try Food.fetchAll(db, sql: """
                SELECT * FROM food WHERE \(whereClauses)
                ORDER BY
                    CASE WHEN LOWER(name) LIKE ? ESCAPE '\\' THEN 0 ELSE 1 END,
                    name
                LIMIT ?
                """, arguments: StatementArguments(allArgs))
        }
    }

    /// Save a scanned/OCR food to the food table so it appears in future searches.
    /// Skips if a food with the same name already exists.
    public func saveScannedFood(_ food: inout Food) throws {
        food.source = food.source ?? "barcode"
        try dbWriter.write { db in
            let exists = try Food.filter(Column("name") == food.name).fetchCount(db) > 0
            if !exists {
                try food.insert(db)
            }
        }
    }

    func fetchAllFoodCategories() throws -> [String] {
        try dbWriter.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT category FROM food ORDER BY category")
        }
    }
}

// MARK: - Favorites & Recipes

extension AppDatabase {
    public func saveFavorite(_ fav: inout SavedFood) throws {
        // SavedFood is now Food — save to food table with source='recipe'
        if fav.source == nil { fav.source = "recipe" }
        try dbWriter.write { [fav] db in
            var m = fav
            try m.save(db)
        }
        fav = try dbWriter.read { db in
            try Food.filter(Column("name") == fav.name && Column("source") == "recipe")
                .order(Column("id").desc).fetchOne(db)
        } ?? fav
    }

    public func fetchFavorites() throws -> [SavedFood] {
        try dbWriter.read { db in
            try Food.filter(Column("source") == "recipe")
                .order(Column("sort_order")).fetchAll(db)
        }
    }

    public func deleteFavorite(id: Int64) throws {
        try dbWriter.write { db in
            let name = try String.fetchOne(db, sql: "SELECT name FROM food WHERE id = ?", arguments: [id])
            _ = try Food.deleteOne(db, id: id)
            if let name {
                try db.execute(sql: "DELETE FROM food_usage WHERE food_name = ? AND food_id IS NULL", arguments: [name])
            }
        }
    }
}

// MARK: - Barcode Cache

extension AppDatabase {
    public func cacheBarcodeProduct(_ cache: BarcodeCache) throws {
        try dbWriter.write { [cache] db in
            var mutable = cache
            try mutable.save(db)
        }
    }

    public func fetchCachedBarcode(_ barcode: String) throws -> BarcodeCache? {
        try dbWriter.read { db in
            try BarcodeCache.fetchOne(db, key: barcode)
        }
    }

    func fetchRecentBarcodes(limit: Int = 20) throws -> [BarcodeCache] {
        try dbWriter.read { db in
            try BarcodeCache.order(Column("created_at").desc).limit(limit).fetchAll(db)
        }
    }
}


    // Lab Report operations in AppDatabase+LabsAndScans.swift

// MARK: - Body Composition

extension AppDatabase {
    public func saveBodyComposition(_ entry: inout BodyComposition) throws {
        try dbWriter.write { db in
            try entry.save(db)
        }
    }

    public func fetchBodyComposition() throws -> [BodyComposition] {
        try dbWriter.read { db in
            try BodyComposition.order(Column("date").desc).fetchAll(db)
        }
    }

    public func fetchLatestBodyComposition() throws -> BodyComposition? {
        try dbWriter.read { db in
            try BodyComposition.order(Column("date").desc).fetchOne(db)
        }
    }

    func deleteBodyComposition(id: Int64) throws {
        try dbWriter.write { db in
            _ = try BodyComposition.deleteOne(db, id: id)
        }
    }
}

// MARK: - Search Miss Tracking

extension AppDatabase {
    /// Record a food search query that returned zero local results.
    /// Deduplicates by normalizing (lowercase, trimmed). Increments count on repeat.
    /// Skips short queries (<3 chars) or single punctuation that aren't real food names.
    public func trackSearchMiss(query: String) throws {
        let normalized = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 3, normalized.first?.isLetter == true else { return }
        try dbWriter.write { db in
            if let existing = try Row.fetchOne(db, sql: "SELECT id, miss_count FROM search_miss WHERE query = ?", arguments: [normalized]) {
                let newCount = (existing["miss_count"] as Int64? ?? 1) + 1
                try db.execute(sql: "UPDATE search_miss SET miss_count = ?, last_seen = date('now') WHERE query = ?", arguments: [newCount, normalized])
            } else {
                try db.execute(sql: "INSERT INTO search_miss (query, miss_count, last_seen) VALUES (?, 1, date('now'))", arguments: [normalized])
            }
        }
    }

    /// Returns the top N most-searched missing foods, ordered by search count descending.
    func topSearchMisses(limit: Int = 20) throws -> [(query: String, count: Int)] {
        try dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT query, miss_count FROM search_miss ORDER BY miss_count DESC LIMIT ?", arguments: [limit])
            return rows.map { (query: $0["query"] as String? ?? "", count: Int(exactly: $0["miss_count"] as Int64? ?? 0) ?? 0) }
        }
    }
}

// MARK: - Chat Telemetry (opt-in, #261)

extension AppDatabase {
    /// Insert one telemetry record. Caller is responsible for the opt-in gate.
    func insertChatTurn(_ row: ChatTurnRow) throws {
        try dbWriter.write { db in
            try db.execute(sql: """
                INSERT INTO chat_turn
                (timestamp, query_fingerprint, intent_label, tool_called, outcome, latency_ms, turn_index, query_text, response_text)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    row.timestamp, row.queryFingerprint, row.intentLabel,
                    row.toolCalled, row.outcome, row.latencyMs, row.turnIndex,
                    row.queryText, row.responseText
                ])
        }
    }

    /// Evict oldest rows past `cap`. No-op if total row count is ≤ cap.
    func evictChatTurnsOver(cap: Int) throws {
        try dbWriter.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat_turn") ?? 0
            guard count > cap else { return }
            let excess = count - cap
            try db.execute(sql: """
                DELETE FROM chat_turn WHERE id IN
                (SELECT id FROM chat_turn ORDER BY id ASC LIMIT ?)
                """, arguments: [excess])
        }
    }

    func fetchChatTurns(limit: Int = 5000) throws -> [ChatTurnRow] {
        try dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT timestamp, query_fingerprint, intent_label, tool_called, outcome, latency_ms, turn_index, query_text, response_text
                FROM chat_turn ORDER BY id DESC LIMIT ?
                """, arguments: [limit])
            return rows.map { r in
                ChatTurnRow(
                    timestamp: r["timestamp"] as String? ?? "",
                    queryFingerprint: r["query_fingerprint"] as String? ?? "",
                    intentLabel: r["intent_label"] as String?,
                    toolCalled: r["tool_called"] as String?,
                    outcome: r["outcome"] as String? ?? "",
                    latencyMs: Int(r["latency_ms"] as Int64? ?? 0),
                    turnIndex: Int(r["turn_index"] as Int64? ?? 0),
                    queryText: r["query_text"] as String?,
                    responseText: r["response_text"] as String?
                )
            }
        }
    }

    func chatTurnCount() throws -> Int {
        try dbWriter.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM chat_turn") ?? 0
        }
    }

    func deleteAllChatTurns() throws {
        try dbWriter.write { db in
            try db.execute(sql: "DELETE FROM chat_turn")
        }
    }
}

/// Transport struct for chat telemetry rows. Not a GRDB `Record` — intentionally
/// plain so tests and service code can construct rows without DB setup.
///
/// `queryText` and `responseText` are nullable to preserve v32 rows that
/// pre-date raw-text capture. Written only when opt-in is on.
public struct ChatTurnRow: Equatable, Codable, Sendable {
    public var timestamp: String
    public var queryFingerprint: String
    public var intentLabel: String?
    public var toolCalled: String?
    public var outcome: String
    public var latencyMs: Int
    public var turnIndex: Int
    public var queryText: String? = nil
    public var responseText: String? = nil

    init(timestamp: String, queryFingerprint: String, intentLabel: String? = nil, toolCalled: String? = nil, outcome: String, latencyMs: Int, turnIndex: Int, queryText: String? = nil, responseText: String? = nil) {
        self.timestamp = timestamp
        self.queryFingerprint = queryFingerprint
        self.intentLabel = intentLabel
        self.toolCalled = toolCalled
        self.outcome = outcome
        self.latencyMs = latencyMs
        self.turnIndex = turnIndex
        self.queryText = queryText
        self.responseText = responseText
    }
}
