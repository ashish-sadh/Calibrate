import Foundation
import GRDB

/// The main application database providing read-write access to all user data.
struct AppDatabase: @unchecked Sendable {
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
    var reader: any DatabaseReader { dbWriter }

    /// Provides write access.
    var writer: any DatabaseWriter { dbWriter }

    /// Delete ALL data from ALL tables. Nuclear option for factory reset.
    func factoryReset() throws {
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
            try db.execute(sql: "DELETE FROM saved_food")
            try db.execute(sql: "DELETE FROM food_usage")
        }
        // Re-seed default foods
        try seedFoodsFromJSON()
        Log.database.info("Factory reset complete - all data deleted, foods re-seeded")
    }
}

// MARK: - Weight Entry Operations

extension AppDatabase {
    func saveWeightEntry(_ entry: inout WeightEntry) throws {
        try dbWriter.write { [entry] db in
            // Upsert: if date already exists, update the weight
            if let existing = try WeightEntry.filter(Column("date") == entry.date).fetchOne(db) {
                var updated = existing
                updated.weightKg = entry.weightKg
                updated.source = entry.source
                updated.syncedFromHk = entry.syncedFromHk
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

    func deleteWeightEntry(id: Int64) throws {
        try dbWriter.write { db in
            _ = try WeightEntry.deleteOne(db, id: id)
        }
    }

    func fetchWeightEntries(from startDate: String? = nil, to endDate: String? = nil) throws -> [WeightEntry] {
        try dbWriter.read { db in
            var request = WeightEntry.order(Column("date").desc)
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
    func saveMealLog(_ log: inout MealLog) throws {
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

    func saveFoodEntry(_ entry: inout FoodEntry) throws {
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

    func updateFoodEntryServings(id: Int64, servings: Double) throws {
        try dbWriter.write { db in
            try db.execute(sql: "UPDATE food_entry SET servings = ? WHERE id = ?", arguments: [servings, id])
        }
    }

    func deleteFoodEntry(id: Int64) throws {
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

    func fetchMealLogs(for date: String) throws -> [MealLog] {
        try dbWriter.read { db in
            try MealLog.filter(Column("date") == date)
                .order(Column("id").asc)
                .fetchAll(db)
        }
    }

    /// Fetch all food entries for a given date (joins through meal_log).
    func fetchFoodEntries(for date: String) throws -> [FoodEntry] {
        try dbWriter.read { db in
            try FoodEntry.fetchAll(db, sql: """
                SELECT fe.* FROM food_entry fe
                JOIN meal_log ml ON fe.meal_log_id = ml.id
                WHERE ml.date = ?
                ORDER BY fe.logged_at DESC
                """, arguments: [date])
        }
    }

    func fetchFoodEntries(forMealLog mealLogId: Int64) throws -> [FoodEntry] {
        try dbWriter.read { db in
            try FoodEntry
                .filter(Column("meal_log_id") == mealLogId)
                .order(Column("logged_at").asc)
                .fetchAll(db)
        }
    }

    func fetchDailyNutrition(for date: String) throws -> DailyNutrition {
        try dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT
                    COALESCE(SUM(fe.calories * fe.servings), 0) as total_calories,
                    COALESCE(SUM(fe.protein_g * fe.servings), 0) as total_protein,
                    COALESCE(SUM(fe.carbs_g * fe.servings), 0) as total_carbs,
                    COALESCE(SUM(fe.fat_g * fe.servings), 0) as total_fat,
                    COALESCE(SUM(fe.fiber_g * fe.servings), 0) as total_fiber
                FROM food_entry fe
                JOIN meal_log ml ON fe.meal_log_id = ml.id
                WHERE ml.date = ?
                """, arguments: [date])

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
    func daysWithFoodLogged(from startDate: String, to endDate: String) throws -> Int {
        try dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT ml.date) as days
                FROM meal_log ml
                JOIN food_entry fe ON fe.meal_log_id = ml.id
                WHERE ml.date BETWEEN ? AND ?
                """, arguments: [startDate, endDate])
            return row?["days"] ?? 0
        }
    }

    /// Daily calorie totals for a date range (batch query for consistency heatmap).
    func fetchDailyCalories(from startDate: String, to endDate: String) throws -> [String: Double] {
        try dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT ml.date, SUM(fe.calories * fe.servings) as total_cal
                FROM food_entry fe
                JOIN meal_log ml ON fe.meal_log_id = ml.id
                WHERE ml.date BETWEEN ? AND ?
                GROUP BY ml.date
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
    func averageDailyCalories(from startDate: String, to endDate: String) throws -> Double {
        try dbWriter.read { db in
            let row = try Row.fetchOne(db, sql: """
                SELECT AVG(daily_cal) as avg_cal FROM (
                    SELECT ml.date, SUM(fe.calories * fe.servings) as daily_cal
                    FROM food_entry fe
                    JOIN meal_log ml ON fe.meal_log_id = ml.id
                    WHERE ml.date BETWEEN ? AND ?
                    GROUP BY ml.date
                    HAVING daily_cal > 200
                )
                """, arguments: [startDate, endDate])
            return row?["avg_cal"] ?? 0
        }
    }

    /// Unique ingredient names for plant points. Uses ingredients JSON when available, falls back to food_name.
    func fetchUniqueIngredients(from startDate: String, to endDate: String) throws -> [String] {
        try dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT fe.food_name, f.ingredients
                FROM food_entry fe
                JOIN meal_log ml ON fe.meal_log_id = ml.id
                LEFT JOIN food f ON f.id = fe.food_id
                WHERE ml.date BETWEEN ? AND ?
                """, arguments: [startDate, endDate])
            var allIngredients: Set<String> = []
            for row in rows {
                let foodName: String = row["food_name"]
                if let json: String = row["ingredients"],
                   let data = json.data(using: .utf8),
                   let arr = try? JSONDecoder().decode([String].self, from: data), !arr.isEmpty {
                    for ingredient in arr { allIngredients.insert(ingredient.lowercased()) }
                } else {
                    allIngredients.insert(foodName.lowercased())
                }
            }
            return Array(allIngredients)
        }
    }

    /// Unique food names logged in a date range (for plant points — legacy, prefer fetchUniqueIngredients).
    func fetchUniqueFoodNames(from startDate: String, to endDate: String) throws -> [String] {
        try dbWriter.read { db in
            try String.fetchAll(db, sql: """
                SELECT DISTINCT fe.food_name
                FROM food_entry fe
                JOIN meal_log ml ON fe.meal_log_id = ml.id
                WHERE ml.date BETWEEN ? AND ?
                """, arguments: [startDate, endDate])
        }
    }

    /// Unique food names per day in a date range (for daily plant points breakdown).
    func fetchUniqueFoodNamesByDay(from startDate: String, to endDate: String) throws -> [String: [String]] {
        try dbWriter.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT DISTINCT ml.date, fe.food_name
                FROM food_entry fe
                JOIN meal_log ml ON fe.meal_log_id = ml.id
                WHERE ml.date BETWEEN ? AND ?
                ORDER BY ml.date
                """, arguments: [startDate, endDate])
            var result: [String: [String]] = [:]
            for row in rows {
                if let date: String = row["date"], let name: String = row["food_name"] {
                    result[date, default: []].append(name)
                }
            }
            return result
        }
    }
}

// MARK: - Supplement Operations

extension AppDatabase {
    func saveSupplement(_ supplement: inout Supplement) throws {
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

    func fetchActiveSupplements() throws -> [Supplement] {
        try dbWriter.read { db in
            try Supplement.filter(Column("is_active") == true)
                .order(Column("sort_order"))
                .fetchAll(db)
        }
    }

    func fetchSupplementLogs(for date: String) throws -> [SupplementLog] {
        try dbWriter.read { db in
            try SupplementLog.filter(Column("date") == date).fetchAll(db)
        }
    }

    func fetchSupplementLogs(from startDate: String, to endDate: String) throws -> [SupplementLog] {
        try dbWriter.read { db in
            try SupplementLog
                .filter(Column("date") >= startDate)
                .filter(Column("date") <= endDate)
                .order(Column("date"))
                .fetchAll(db)
        }
    }

    func toggleSupplementTaken(supplementId: Int64, date: String) throws {
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
    func saveGlucoseReadings(_ readings: [GlucoseReading]) throws {
        try dbWriter.write { db in
            for var reading in readings {
                try reading.insert(db)
            }
        }
    }

    func fetchGlucoseReadings(from start: String, to end: String) throws -> [GlucoseReading] {
        try dbWriter.read { db in
            try GlucoseReading
                .filter(Column("timestamp") >= start)
                .filter(Column("timestamp") <= end)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }
}

// MARK: - DEXA Scan Operations

extension AppDatabase {
    func saveDEXAScan(_ scan: inout DEXAScan) throws {
        try dbWriter.write { [scan] db in
            // Upsert by scan_date
            if let existing = try DEXAScan.filter(Column("scan_date") == scan.scanDate).fetchOne(db) {
                var updated = scan
                updated.id = existing.id
                try updated.update(db)
            } else {
                var mutable = scan
                try mutable.insert(db)
            }
        }
        scan = try dbWriter.read { db in
            try DEXAScan.filter(Column("scan_date") == scan.scanDate).fetchOne(db)
        } ?? scan
    }

    func saveDEXARegions(_ regions: [DEXARegion], forScanId scanId: Int64) throws {
        try dbWriter.write { db in
            // Delete existing regions for this scan
            try DEXARegion.filter(Column("scan_id") == scanId).deleteAll(db)
            // Insert new ones
            for var region in regions {
                region.scanId = scanId
                try region.insert(db)
            }
        }
    }

    func fetchDEXAScans() throws -> [DEXAScan] {
        try dbWriter.read { db in
            try DEXAScan.order(Column("scan_date").desc).fetchAll(db)
        }
    }

    func deleteDEXAScan(id: Int64) throws {
        try dbWriter.write { db in
            // Regions cascade-delete via foreign key
            _ = try DEXAScan.deleteOne(db, id: id)
        }
    }

    func deleteAllDEXAScans() throws {
        try dbWriter.write { db in
            _ = try DEXARegion.deleteAll(db)
            _ = try DEXAScan.deleteAll(db)
        }
    }

    func fetchDEXARegions(forScanId scanId: Int64) throws -> [DEXARegion] {
        try dbWriter.read { db in
            try DEXARegion.filter(Column("scan_id") == scanId).fetchAll(db)
        }
    }

    /// Import parsed BodySpec scans (from PDF).
    func importBodySpecScans(_ parsedScans: [BodySpecPDFParser.ParsedScan]) throws -> Int {
        var count = 0
        for parsed in parsedScans {
            var scan = DEXAScan(
                scanDate: parsed.scanDate,
                location: "BodySpec",
                totalMassKg: parsed.totalMassLbs.map { $0 / 2.20462 },
                fatMassKg: parsed.fatMassLbs.map { $0 / 2.20462 },
                leanMassKg: parsed.leanMassLbs.map { $0 / 2.20462 },
                boneMassKg: parsed.bmcLbs.map { $0 / 2.20462 },
                bodyFatPct: parsed.bodyFatPct,
                visceralFatKg: parsed.vatMassLbs.map { $0 / 2.20462 },
                boneDensityTotal: parsed.boneDensityTotal,
                rmrCalories: parsed.rmrCalories,
                vatVolumeIn3: parsed.vatVolumeIn3,
                agRatio: parsed.agRatio
            )
            try saveDEXAScan(&scan)

            if let scanId = scan.id, !parsed.regions.isEmpty {
                let regions = parsed.regions.map { r in
                    DEXARegion(
                        scanId: scanId,
                        region: r.name,
                        fatPct: r.fatPct,
                        totalMassLbs: r.totalMassLbs,
                        fatMassLbs: r.fatMassLbs,
                        leanMassLbs: r.leanMassLbs,
                        bmcLbs: r.bmcLbs
                    )
                }
                try saveDEXARegions(regions, forScanId: scanId)
            }
            count += 1
        }
        Log.bodyComp.info("Imported \(count) DEXA scans")
        return count
    }
}

// MARK: - HealthKit Sync Anchor

extension AppDatabase {
    func saveAnchor(dataType: String, anchor: Data) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO hk_sync_anchor (data_type, last_anchor) VALUES (?, ?)",
                arguments: [dataType, anchor]
            )
        }
    }

    func fetchAnchor(dataType: String) throws -> Data? {
        try dbWriter.read { db in
            try Data.fetchOne(db, sql: "SELECT last_anchor FROM hk_sync_anchor WHERE data_type = ?", arguments: [dataType])
        }
    }
}

// MARK: - Food Database (bundled read-only)

extension AppDatabase {
    func seedFoodsFromJSON() throws {
        try dbWriter.write { db in
            guard let url = Bundle.main.url(forResource: "foods", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let foods = try? JSONDecoder().decode([Food].self, from: data) else {
                return
            }

            let existingNames = try Set(String.fetchAll(db, sql: "SELECT LOWER(name) FROM food"))

            for var food in foods {
                if !existingNames.contains(food.name.lowercased()) {
                    try food.insert(db)
                } else if let ingredients = food.ingredients {
                    // Update ingredients for existing foods (backfill from JSON)
                    try db.execute(sql: "UPDATE food SET ingredients = ? WHERE LOWER(name) = ? AND (ingredients IS NULL OR ingredients = '[\"' || name || '\"]')",
                                   arguments: [ingredients, food.name.lowercased()])
                }
            }
        }
    }

    /// Escape SQL LIKE special characters in user input.
    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "%", with: "\\%")
         .replacingOccurrences(of: "_", with: "\\_")
    }

    func searchFoods(query: String, limit: Int = 50) throws -> [Food] {
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
    func saveScannedFood(_ food: inout Food) throws {
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
    func saveFavorite(_ fav: inout SavedFood) throws {
        try dbWriter.write { [fav] db in
            var m = fav
            try m.save(db)
        }
        fav = try dbWriter.read { db in
            try SavedFood.filter(Column("name") == fav.name).order(Column("created_at").desc).fetchOne(db)
        } ?? fav
    }

    func fetchFavorites() throws -> [SavedFood] {
        try dbWriter.read { db in
            try SavedFood.order(Column("sort_order")).fetchAll(db)
        }
    }

    func deleteFavorite(id: Int64) throws {
        try dbWriter.write { db in
            // Get name before deleting to clean up food_usage
            let name = try String.fetchOne(db, sql: "SELECT name FROM saved_food WHERE id = ?", arguments: [id])
            _ = try SavedFood.deleteOne(db, id: id)
            // Clean up food_usage entry for this recipe name (if no food table entry exists)
            if let name {
                let hasFoodEntry = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM food WHERE LOWER(name) = LOWER(?)", arguments: [name]) ?? 0
                if hasFoodEntry == 0 {
                    try db.execute(sql: "DELETE FROM food_usage WHERE food_name = ? AND food_id IS NULL", arguments: [name])
                }
            }
        }
    }
}

// MARK: - Barcode Cache

extension AppDatabase {
    func cacheBarcodeProduct(_ cache: BarcodeCache) throws {
        try dbWriter.write { [cache] db in
            var mutable = cache
            try mutable.save(db)
        }
    }

    func fetchCachedBarcode(_ barcode: String) throws -> BarcodeCache? {
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

// MARK: - Lab Report Operations

extension AppDatabase {
    func saveLabReport(_ report: inout LabReport) throws {
        try dbWriter.write { [report] db in
            var mutable = report
            try mutable.insert(db)
        }
        report = try dbWriter.read { db in
            try LabReport.order(Column("id").desc).fetchOne(db)
        } ?? report
    }

    func fetchLabReports() throws -> [LabReport] {
        try dbWriter.read { db in
            try LabReport.order(Column("report_date").desc).fetchAll(db)
        }
    }

    func deleteLabReport(id: Int64) throws {
        try dbWriter.write { db in
            // biomarker_results cascade-delete via foreign key
            _ = try LabReport.deleteOne(db, id: id)
        }
    }

    func saveBiomarkerResults(_ results: [BiomarkerResult]) throws {
        try dbWriter.write { db in
            for var result in results {
                try result.insert(db)
            }
        }
    }

    func fetchBiomarkerResults(forReportId reportId: Int64) throws -> [BiomarkerResult] {
        try dbWriter.read { db in
            try BiomarkerResult
                .filter(Column("report_id") == reportId)
                .order(Column("biomarker_id"))
                .fetchAll(db)
        }
    }

    func fetchBiomarkerResults(forBiomarkerId biomarkerId: String) throws -> [BiomarkerResult] {
        try dbWriter.read { db in
            try BiomarkerResult
                .filter(Column("biomarker_id") == biomarkerId)
                .order(sql: """
                    (SELECT report_date FROM lab_report WHERE lab_report.id = biomarker_result.report_id) ASC
                """)
                .fetchAll(db)
        }
    }

    /// Fetch the latest result for each biomarker across all reports.
    func fetchLatestBiomarkerResults() throws -> [BiomarkerResult] {
        try dbWriter.read { db in
            try BiomarkerResult.fetchAll(db, sql: """
                SELECT br.* FROM biomarker_result br
                INNER JOIN (
                    SELECT biomarker_id, MAX(lr.report_date) as max_date
                    FROM biomarker_result br2
                    INNER JOIN lab_report lr ON lr.id = br2.report_id
                    GROUP BY biomarker_id
                ) latest ON br.biomarker_id = latest.biomarker_id
                INNER JOIN lab_report lr2 ON lr2.id = br.report_id AND lr2.report_date = latest.max_date
                ORDER BY br.biomarker_id
            """)
        }
    }

    /// Fetch the report date for a given report ID.
    func fetchReportDate(forId reportId: Int64) throws -> String? {
        try dbWriter.read { db in
            try String.fetchOne(db, sql: "SELECT report_date FROM lab_report WHERE id = ?", arguments: [reportId])
        }
    }
}


// MARK: - Body Composition

extension AppDatabase {
    func saveBodyComposition(_ entry: inout BodyComposition) throws {
        try dbWriter.write { db in
            try entry.save(db)
        }
    }

    func fetchBodyComposition() throws -> [BodyComposition] {
        try dbWriter.read { db in
            try BodyComposition.order(Column("date").desc).fetchAll(db)
        }
    }

    func fetchLatestBodyComposition() throws -> BodyComposition? {
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
