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
        try dbWriter.write { [entry] db in
            var mutable = entry
            try mutable.save(db)
        }
    }

    func deleteFoodEntry(id: Int64) throws {
        try dbWriter.write { db in
            _ = try FoodEntry.deleteOne(db, id: id)
        }
    }

    func fetchMealLogs(for date: String) throws -> [MealLog] {
        try dbWriter.read { db in
            try MealLog.filter(Column("date") == date).fetchAll(db)
        }
    }

    func fetchFoodEntries(forMealLog mealLogId: Int64) throws -> [FoodEntry] {
        try dbWriter.read { db in
            try FoodEntry.filter(Column("meal_log_id") == mealLogId).fetchAll(db)
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
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM food")
            guard count == 0 else { return }

            guard let url = Bundle.main.url(forResource: "foods", withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let foods = try? JSONDecoder().decode([Food].self, from: data) else {
                return
            }

            for var food in foods {
                try food.insert(db)
            }
        }
    }

    func searchFoods(query: String, limit: Int = 50) throws -> [Food] {
        try dbWriter.read { db in
            if query.isEmpty { return [] }
            let pattern = "%\(query)%"
            return try Food
                .filter(Column("name").like(pattern))
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetchAllFoodCategories() throws -> [String] {
        try dbWriter.read { db in
            try String.fetchAll(db, sql: "SELECT DISTINCT category FROM food ORDER BY category")
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
