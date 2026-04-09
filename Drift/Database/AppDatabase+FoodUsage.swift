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
                       calories, protein_g, carbs_g, fat_g, serving_size_g
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
                       fu.calories, fu.protein_g, fu.carbs_g, fu.fat_g, fu.serving_size_g
                FROM food_usage fu
                WHERE fu.is_favorite = 1
                ORDER BY fu.food_name
                """)
            return rows.map { row in
                RecentEntry(name: row["food_name"], foodId: row["food_id"],
                            calories: row["calories"], proteinG: row["protein_g"],
                            carbsG: row["carbs_g"], fatG: row["fat_g"],
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
