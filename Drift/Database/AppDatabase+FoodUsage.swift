import Foundation
import GRDB

struct RecentEntry: Identifiable, Sendable {
    let id = UUID()
    let name: String
    let foodId: Int64?
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double
    let servingSize: Double
    let lastServings: Double

    var macroSummary: String { "\(Int(calories))cal \(Int(proteinG))P \(Int(carbsG))C \(Int(fatG))F" }
    var isDBFood: Bool { foodId != nil }
}

// MARK: - Food Usage Tracking

extension AppDatabase {
    /// Track food usage for smart search ranking + recents. Upserts with macros.
    func trackFoodUsage(name: String, foodId: Int64?, servings: Double,
                        calories: Double = 0, proteinG: Double = 0, carbsG: Double = 0,
                        fatG: Double = 0, fiberG: Double = 0, servingSizeG: Double = 0) throws {
        try writer.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            try db.execute(sql: """
                INSERT INTO food_usage (food_name, food_id, use_count, last_used, last_servings,
                                        calories, protein_g, carbs_g, fat_g, fiber_g, serving_size_g)
                VALUES (?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(food_name) DO UPDATE SET
                    use_count = use_count + 1,
                    last_used = excluded.last_used,
                    last_servings = excluded.last_servings,
                    food_id = COALESCE(excluded.food_id, food_id),
                    calories = CASE WHEN excluded.calories > 0 THEN excluded.calories ELSE food_usage.calories END,
                    protein_g = CASE WHEN excluded.protein_g > 0 THEN excluded.protein_g ELSE food_usage.protein_g END,
                    carbs_g = CASE WHEN excluded.carbs_g > 0 THEN excluded.carbs_g ELSE food_usage.carbs_g END,
                    fat_g = CASE WHEN excluded.fat_g > 0 THEN excluded.fat_g ELSE food_usage.fat_g END,
                    fiber_g = CASE WHEN excluded.fiber_g > 0 THEN excluded.fiber_g ELSE food_usage.fiber_g END,
                    serving_size_g = CASE WHEN excluded.serving_size_g > 0 THEN excluded.serving_size_g ELSE food_usage.serving_size_g END
                """, arguments: [name, foodId, now, servings, calories, proteinG, carbsG, fatG, fiberG, servingSizeG])
        }
    }

    /// Recent foods by last-used time (DB foods only).
    func fetchRecentFoods(limit: Int = 10) throws -> [Food] {
        try reader.read { db in
            try Food.fetchAll(db, sql: """
                SELECT f.* FROM food f
                INNER JOIN food_usage fu ON f.id = fu.food_id
                WHERE fu.food_id IS NOT NULL
                ORDER BY fu.last_used DESC
                LIMIT ?
                """, arguments: [limit])
        }
    }

    /// Recent entries including recipes and manual adds — reads macros directly from food_usage.
    func fetchRecentEntryNames(limit: Int = 10) throws -> [RecentEntry] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT food_name, food_id, last_servings,
                       calories, protein_g, carbs_g, fat_g, fiber_g, serving_size_g
                FROM food_usage
                ORDER BY last_used DESC
                LIMIT ?
                """, arguments: [limit])
            return rows.map { row in
                RecentEntry(
                    name: row["food_name"],
                    foodId: row["food_id"],
                    calories: row["calories"],
                    proteinG: row["protein_g"],
                    carbsG: row["carbs_g"],
                    fatG: row["fat_g"],
                    fiberG: row["fiber_g"] ?? 0,
                    servingSize: row["serving_size_g"],
                    lastServings: row["last_servings"]
                )
            }
        }
    }

    /// Most-logged foods by usage count.
    func fetchFrequentFoods(limit: Int = 10) throws -> [Food] {
        try reader.read { db in
            try Food.fetchAll(db, sql: """
                SELECT f.* FROM food f
                INNER JOIN food_usage fu ON f.id = fu.food_id
                WHERE fu.food_id IS NOT NULL AND fu.use_count > 1
                ORDER BY fu.use_count DESC
                LIMIT ?
                """, arguments: [limit])
        }
    }

    /// Toggle favorite status for a food item.
    func toggleFoodFavorite(name: String, foodId: Int64?) throws {
        try writer.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            // Resolve foodId if not provided — look up from food table
            var resolvedId = foodId
            if resolvedId == nil {
                resolvedId = try Int64.fetchOne(db, sql: "SELECT id FROM food WHERE name = ? LIMIT 1", arguments: [name])
            }
            try db.execute(sql: """
                INSERT INTO food_usage (food_name, food_id, use_count, last_used, last_servings, is_favorite)
                VALUES (?, ?, 0, ?, 1, 1)
                ON CONFLICT(food_name) DO UPDATE SET
                    is_favorite = NOT is_favorite,
                    food_id = COALESCE(excluded.food_id, food_id)
                """, arguments: [name, resolvedId, now])
        }
    }

    /// Fetch user-favorited food items.
    func fetchSavedFoods() throws -> [Food] {
        try reader.read { db in
            try Food.fetchAll(db, sql: """
                SELECT f.* FROM food f
                INNER JOIN food_usage fu ON f.id = fu.food_id
                WHERE fu.is_favorite = 1
                ORDER BY f.name
                """)
        }
    }

    /// Fetch user-favorited entry names (unified — food table has everything now).
    func fetchFavoriteEntryNames() throws -> [RecentEntry] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT fu.food_name, fu.food_id, fu.last_servings,
                       fu.calories, fu.protein_g, fu.carbs_g, fu.fat_g, fu.fiber_g, fu.serving_size_g
                FROM food_usage fu
                WHERE fu.is_favorite = 1
                ORDER BY fu.food_name
                """)
            return rows.map { row in
                RecentEntry(name: row["food_name"], foodId: row["food_id"],
                            calories: row["calories"], proteinG: row["protein_g"],
                            carbsG: row["carbs_g"], fatG: row["fat_g"],
                            fiberG: row["fiber_g"] ?? 0,
                            servingSize: row["serving_size_g"], lastServings: row["last_servings"])
            }
        }
    }

    /// Check if a food is favorited.
    func isFoodFavorite(name: String) throws -> Bool {
        try reader.read { db in
            let val = try Bool.fetchOne(db, sql: "SELECT is_favorite FROM food_usage WHERE food_name = ?", arguments: [name])
            return val ?? false
        }
    }

    /// Search foods ranked by usage frequency, then prefix match, then alphabetical.
    func searchFoodsRanked(query: String, limit: Int = 50) throws -> [Food] {
        try reader.read { db in
            if query.isEmpty { return [] }
            let words = query.lowercased().split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if words.isEmpty { return [] }

            let whereClauses = words.map { _ in "LOWER(f.name) LIKE ? ESCAPE '\\'" }.joined(separator: " AND ")
            let patterns: [DatabaseValueConvertible] = words.map { "%\(Self.escapeLike($0))%" }
            let prefixPattern: DatabaseValueConvertible = "\(Self.escapeLike(query.lowercased()))%"
            let allArgs: [DatabaseValueConvertible] = patterns + [prefixPattern, limit]

            let queryEscaped: DatabaseValueConvertible = "%\(Self.escapeLike(query.lowercased()))%"
            let allArgsWithPhrase: [DatabaseValueConvertible] = patterns + [prefixPattern, queryEscaped, limit]

            return try Food.fetchAll(db, sql: """
                SELECT f.* FROM food f
                LEFT JOIN food_usage fu ON f.id = fu.food_id OR LOWER(fu.food_name) = LOWER(f.name)
                WHERE \(whereClauses)
                GROUP BY f.id
                ORDER BY
                    COALESCE(fu.is_favorite, 0) DESC,
                    COALESCE(fu.use_count, 0) DESC,
                    CASE WHEN LOWER(f.name) LIKE ? ESCAPE '\\' THEN 0 ELSE 1 END,
                    CASE WHEN LOWER(f.name) LIKE ? ESCAPE '\\' THEN 0 ELSE 1 END,
                    LENGTH(f.name),
                    f.name
                LIMIT ?
                """, arguments: StatementArguments(allArgsWithPhrase))
        }
    }

    /// Fetch combos (recipes with isRecipe=true) ranked by pinned → use_count → last_used.
    func fetchCombos(limit: Int = 8) throws -> [Food] {
        try reader.read { db in
            try Food.fetchAll(db, sql: """
                SELECT f.* FROM food f
                LEFT JOIN food_usage fu ON LOWER(fu.food_name) = LOWER(f.name)
                WHERE f.source = 'recipe' AND f.is_recipe = 1
                GROUP BY f.id
                ORDER BY
                    COALESCE(fu.is_favorite, 0) DESC,
                    COALESCE(fu.use_count, 0) DESC,
                    COALESCE(fu.last_used, '') DESC,
                    f.name
                LIMIT ?
                """, arguments: [limit])
        }
    }

    /// Scan food_entry history and auto-save frequently co-logged groups as combos.
    /// Groups entries logged within 25 minutes on the same date into sessions;
    /// signatures appearing on 2+ distinct dates become saved recipe combos.
    func detectAndSaveCombos() throws {
        struct EntryRow {
            let date: String; let name: String
            let calories: Double; let proteinG: Double
            let carbsG: Double; let fatG: Double; let fiberG: Double
            let servingSizeG: Double; let servings: Double; let loggedAt: String
        }

        let entries: [EntryRow] = try reader.read { db in
            try Row.fetchAll(db, sql: """
                SELECT date, food_name, calories, protein_g, carbs_g, fat_g, fiber_g,
                       serving_size_g, servings, logged_at
                FROM food_entry
                WHERE date IS NOT NULL AND logged_at IS NOT NULL AND food_name IS NOT NULL
                ORDER BY date, logged_at
                """).compactMap { row in
                guard let date = row["date"] as String?,
                      let name = row["food_name"] as String?,
                      let loggedAt = row["logged_at"] as String?,
                      !name.isEmpty else { return nil }
                return EntryRow(
                    date: date, name: name,
                    calories: row["calories"] ?? 0, proteinG: row["protein_g"] ?? 0,
                    carbsG: row["carbs_g"] ?? 0, fatG: row["fat_g"] ?? 0,
                    fiberG: row["fiber_g"] ?? 0,
                    servingSizeG: row["serving_size_g"] ?? 0,
                    servings: row["servings"] ?? 1, loggedAt: loggedAt
                )
            }
        }

        let iso = ISO8601DateFormatter()
        let window: TimeInterval = 25 * 60

        // Group into 25-min sessions per date
        typealias SessionItem = (name: String, cal: Double, p: Double, c: Double, f: Double, fb: Double, ss: Double, sv: Double)
        var sessions: [(date: String, items: [SessionItem])] = []
        var cur: [SessionItem] = []
        var curDate = ""
        var sessionStart: Date? = nil

        func flush() {
            if cur.count >= 2 && cur.count <= 6 { sessions.append((date: curDate, items: cur)) }
        }

        for e in entries {
            guard let ts = iso.date(from: e.loggedAt) else { continue }
            let isNewSession = e.date != curDate || sessionStart == nil || ts.timeIntervalSince(sessionStart!) > window
            if isNewSession { flush(); cur = []; curDate = e.date; sessionStart = ts }
            cur.append((e.name, e.calories * e.servings, e.proteinG * e.servings,
                        e.carbsG * e.servings, e.fatG * e.servings, e.fiberG * e.servings,
                        e.servingSizeG * e.servings, e.servings))
        }
        flush()

        // Count distinct dates per signature
        var sigDates: [String: Set<String>] = [:]
        var sigItems: [String: [SessionItem]] = [:]
        for s in sessions {
            let sig = s.items.map { $0.name.lowercased() }.sorted().joined(separator: "||")
            sigDates[sig, default: []].insert(s.date)
            sigItems[sig] = s.items
        }

        for (sig, dates) in sigDates where dates.count >= 2 {
            guard let items = sigItems[sig] else { continue }
            let recipeItems = items.map { item in
                QuickAddView.RecipeItem(
                    name: item.name,
                    portionText: item.ss > 0 ? "\(Int(item.ss))g" : "",
                    calories: item.cal, proteinG: item.p, carbsG: item.c,
                    fatG: item.f, fiberG: item.fb, servingSizeG: item.ss
                )
            }
            guard let json = try? JSONEncoder().encode(recipeItems),
                  let ingredientsJson = String(data: json, encoding: .utf8) else { continue }

            let comboName = items.prefix(4)
                .map { $0.name.split(separator: " ").prefix(2).joined(separator: " ") }
                .joined(separator: " + ")
            let totalCal = items.reduce(0) { $0 + $1.cal }
            let totalP = items.reduce(0) { $0 + $1.p }
            let totalC = items.reduce(0) { $0 + $1.c }
            let totalF = items.reduce(0) { $0 + $1.f }
            let totalFb = items.reduce(0) { $0 + $1.fb }
            let totalSS = items.reduce(0) { $0 + $1.ss }
            _ = try? writer.write { db in
                let exists = try (Int.fetchOne(db, sql: """
                    SELECT COUNT(*) FROM food WHERE LOWER(name) = ? AND source = 'recipe'
                    """, arguments: [comboName.lowercased()]) ?? 0) > 0
                guard !exists else { return }
                var food = Food(name: comboName, category: "Combo",
                                servingSize: max(totalSS, 1), servingUnit: "serving",
                                calories: totalCal, proteinG: totalP, carbsG: totalC,
                                fatG: totalF, fiberG: totalFb,
                                ingredients: ingredientsJson, source: "recipe",
                                isRecipe: true, defaultServings: 1, expandOnLog: true)
                try food.insert(db)
                Log.app.info("Auto-saved combo: \(comboName)")
            }
        }
    }

    /// Insert sample food entries across the past 5 days for testing history grouping.
    func seedTestData() throws {
        struct SeedItem {
            let name: String, cal: Double, p: Double, c: Double, f: Double, ss: Double, meal: String
        }
        let breakfast: [SeedItem] = [
            SeedItem(name: "Egg", cal: 72, p: 6, c: 0.5, f: 5, ss: 50, meal: "breakfast"),
            SeedItem(name: "Milk (2%)", cal: 122, p: 8, c: 12, f: 5, ss: 244, meal: "breakfast"),
            SeedItem(name: "Protein Powder", cal: 120, p: 25, c: 3, f: 1.5, ss: 30, meal: "breakfast"),
        ]
        let lunchDosa: [SeedItem] = [
            SeedItem(name: "Dosa", cal: 168, p: 3, c: 34, f: 0.5, ss: 100, meal: "lunch"),
            SeedItem(name: "Sambar", cal: 90, p: 5, c: 15, f: 2, ss: 200, meal: "lunch"),
        ]
        let lunchChole: [SeedItem] = [
            SeedItem(name: "Chole", cal: 269, p: 14, c: 45, f: 4, ss: 200, meal: "lunch"),
            SeedItem(name: "Rice", cal: 206, p: 4, c: 45, f: 0.4, ss: 186, meal: "lunch"),
        ]
        let dinner: [SeedItem] = [
            SeedItem(name: "Dal Tadka", cal: 160, p: 10, c: 27, f: 3, ss: 200, meal: "dinner"),
            SeedItem(name: "Roti", cal: 104, p: 3, c: 22, f: 0.3, ss: 40, meal: "dinner"),
        ]
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        for dayOffset in 1...5 {
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            func insertCluster(_ items: [SeedItem], hour: Int, minute: Int) throws {
                guard let base = cal.date(bySettingHour: hour, minute: minute, second: 0, of: date) else { return }
                for (idx, item) in items.enumerated() {
                    let ts = iso.string(from: base.addingTimeInterval(Double(idx * 90)))
                    try writer.write { db in
                        var entry = FoodEntry(foodName: item.name, servingSizeG: item.ss, servings: 1,
                                             calories: item.cal, proteinG: item.p, carbsG: item.c, fatG: item.f,
                                             createdAt: ts, loggedAt: ts, date: dateStr, mealType: item.meal)
                        try entry.insert(db)
                    }
                }
            }
            let clusters: [[SeedItem]] = [
                breakfast,
                dayOffset % 2 == 0 ? lunchChole : lunchDosa,
            ] + (dayOffset <= 3 ? [dinner] : [])
            let hours = [8, 12, 19]
            let minutes = [0, 30, 30]
            for (i, cluster) in clusters.enumerated() {
                try insertCluster(cluster, hour: hours[i], minute: minutes[i])
                for item in cluster {
                    try trackFoodUsage(name: item.name, foodId: nil, servings: 1,
                                       calories: item.cal, proteinG: item.p, carbsG: item.c,
                                       fatG: item.f, fiberG: 0, servingSizeG: item.ss)
                }
            }
        }
    }

    /// Search saved recipes/favorites by name.
    func searchRecipes(query: String) throws -> [SavedFood] {
        try reader.read { db in
            if query.isEmpty {
                return try Food.filter(Column("source") == "recipe")
                    .order(Column("name")).fetchAll(db)
            }
            let escaped = Self.escapeLike(query)
            return try Food.fetchAll(db, sql: """
                SELECT * FROM food WHERE source = 'recipe' AND name LIKE ? ESCAPE '\\' ORDER BY name
                """, arguments: ["%\(escaped)%"])
        }
    }
}
