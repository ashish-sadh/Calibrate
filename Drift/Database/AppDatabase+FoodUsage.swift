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
    /// Track food usage for smart search ranking. Upserts: increments count or inserts new row.
    func trackFoodUsage(name: String, foodId: Int64?, servings: Double) throws {
        try writer.write { db in
            let now = ISO8601DateFormatter().string(from: Date())
            try db.execute(sql: """
                INSERT INTO food_usage (food_name, food_id, use_count, last_used, last_servings)
                VALUES (?, ?, 1, ?, ?)
                ON CONFLICT(food_name) DO UPDATE SET
                    use_count = use_count + 1,
                    last_used = excluded.last_used,
                    last_servings = excluded.last_servings,
                    food_id = COALESCE(excluded.food_id, food_id)
                """, arguments: [name, foodId, now, servings])
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

    /// Recent entries including recipes and manual adds (from food_usage table).
    func fetchRecentEntryNames(limit: Int = 10) throws -> [RecentEntry] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT fu.food_name, fu.food_id, fu.last_servings, fu.use_count,
                       COALESCE(f.calories, f2.calories, ff.calories, 0) as calories,
                       COALESCE(f.protein_g, f2.protein_g, ff.protein_g, 0) as protein_g,
                       COALESCE(f.carbs_g, f2.carbs_g, ff.carbs_g, 0) as carbs_g,
                       COALESCE(f.fat_g, f2.fat_g, ff.fat_g, 0) as fat_g,
                       COALESCE(f.serving_size, f2.serving_size, 0) as serving_size
                FROM food_usage fu
                LEFT JOIN food f ON f.id = fu.food_id
                LEFT JOIN food f2 ON LOWER(f2.name) = LOWER(fu.food_name) AND fu.food_id IS NULL
                LEFT JOIN favorite_food ff ON LOWER(ff.name) = LOWER(fu.food_name)
                ORDER BY fu.last_used DESC
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
                    servingSize: row["serving_size"],
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
    func fetchFavoriteFoods() throws -> [Food] {
        try reader.read { db in
            try Food.fetchAll(db, sql: """
                SELECT f.* FROM food f
                INNER JOIN food_usage fu ON f.id = fu.food_id
                WHERE fu.is_favorite = 1
                ORDER BY f.name
                """)
        }
    }

    /// Fetch user-favorited entry names (includes non-DB items like recipes/manual).
    func fetchFavoriteEntryNames() throws -> [RecentEntry] {
        try reader.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT fu.food_name, fu.food_id, fu.last_servings, fu.use_count,
                       COALESCE(f.calories, f2.calories, ff.calories, 0) as calories,
                       COALESCE(f.protein_g, f2.protein_g, ff.protein_g, 0) as protein_g,
                       COALESCE(f.carbs_g, f2.carbs_g, ff.carbs_g, 0) as carbs_g,
                       COALESCE(f.fat_g, f2.fat_g, ff.fat_g, 0) as fat_g,
                       COALESCE(f.serving_size, f2.serving_size, 0) as serving_size
                FROM food_usage fu
                LEFT JOIN food f ON f.id = fu.food_id
                LEFT JOIN food f2 ON LOWER(f2.name) = LOWER(fu.food_name) AND fu.food_id IS NULL
                LEFT JOIN favorite_food ff ON LOWER(ff.name) = LOWER(fu.food_name)
                WHERE fu.is_favorite = 1
                ORDER BY fu.food_name
                """)
            return rows.map { row in
                RecentEntry(name: row["food_name"], foodId: row["food_id"],
                            calories: row["calories"], proteinG: row["protein_g"],
                            carbsG: row["carbs_g"], fatG: row["fat_g"],
                            servingSize: row["serving_size"], lastServings: row["last_servings"])
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
    func searchRecipes(query: String) throws -> [FavoriteFood] {
        try reader.read { db in
            if query.isEmpty {
                return try FavoriteFood.order(Column("name")).fetchAll(db)
            }
            let escaped = Self.escapeLike(query)
            return try FavoriteFood.fetchAll(db, sql: """
                SELECT * FROM favorite_food WHERE name LIKE ? ESCAPE '\\' ORDER BY name
                """, arguments: ["%\(escaped)%"])
        }
    }
}
