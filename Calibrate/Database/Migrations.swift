import Foundation
import GRDB

/// All database schema migrations.
enum Migrations {
    static func registerAll(_ migrator: inout DatabaseMigrator) {
        // v1: Weight tracking
        migrator.registerMigration("v1_weight") { db in
            try db.create(table: "weight_entry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull().unique()
                t.column("weight_kg", .double).notNull()
                t.column("source", .text).notNull().defaults(to: "manual")
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
                t.column("synced_from_hk", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "idx_weight_entry_date", on: "weight_entry", columns: ["date"])
        }

        // v2: Food logging
        migrator.registerMigration("v2_food_logging") { db in
            try db.create(table: "food") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("category", .text).notNull()
                t.column("serving_size", .double).notNull()
                t.column("serving_unit", .text).notNull()
                t.column("calories", .double).notNull()
                t.column("protein_g", .double).notNull().defaults(to: 0)
                t.column("carbs_g", .double).notNull().defaults(to: 0)
                t.column("fat_g", .double).notNull().defaults(to: 0)
                t.column("fiber_g", .double).notNull().defaults(to: 0)
            }

            try db.create(table: "meal_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull()
                t.column("meal_type", .text).notNull()
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_meal_log_date", on: "meal_log", columns: ["date"])

            try db.create(table: "food_entry") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meal_log_id", .integer).notNull()
                    .references("meal_log", onDelete: .cascade)
                t.column("food_id", .integer)
                t.column("food_name", .text).notNull()
                t.column("serving_size_g", .double).notNull()
                t.column("servings", .double).notNull().defaults(to: 1.0)
                t.column("calories", .double).notNull()
                t.column("protein_g", .double).notNull().defaults(to: 0)
                t.column("carbs_g", .double).notNull().defaults(to: 0)
                t.column("fat_g", .double).notNull().defaults(to: 0)
                t.column("fiber_g", .double).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_food_entry_meal", on: "food_entry", columns: ["meal_log_id"])
        }

        // v3: Supplements
        migrator.registerMigration("v3_supplements") { db in
            try db.create(table: "supplement") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("dosage", .text)
                t.column("unit", .text)
                t.column("is_active", .boolean).notNull().defaults(to: true)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
            }

            try db.create(table: "supplement_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("supplement_id", .integer).notNull()
                    .references("supplement", onDelete: .cascade)
                t.column("date", .text).notNull()
                t.column("taken", .boolean).notNull().defaults(to: false)
                t.column("taken_at", .text)
                t.column("notes", .text)
            }
            try db.create(
                index: "idx_supplement_log_unique",
                on: "supplement_log",
                columns: ["supplement_id", "date"],
                unique: true
            )
        }

        // v4: CGM glucose readings
        migrator.registerMigration("v4_glucose") { db in
            try db.create(table: "glucose_reading") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .text).notNull()
                t.column("glucose_mgdl", .double).notNull()
                t.column("source", .text).notNull().defaults(to: "lingo_csv")
                t.column("import_batch", .text)
            }
            try db.create(index: "idx_glucose_timestamp", on: "glucose_reading", columns: ["timestamp"])
        }

        // v5: HealthKit sync anchors
        migrator.registerMigration("v5_hk_sync") { db in
            try db.create(table: "hk_sync_anchor") { t in
                t.primaryKey("data_type", .text)
                t.column("last_anchor", .blob)
            }
        }

        // v6: DEXA scans
        migrator.registerMigration("v6_dexa") { db in
            try db.create(table: "dexa_scan") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("scan_date", .text).notNull()
                t.column("location", .text)
                t.column("total_mass_kg", .double)
                t.column("fat_mass_kg", .double)
                t.column("lean_mass_kg", .double)
                t.column("bone_mass_kg", .double)
                t.column("body_fat_pct", .double)
                t.column("visceral_fat_kg", .double)
                t.column("trunk_fat_pct", .double)
                t.column("arms_fat_pct", .double)
                t.column("legs_fat_pct", .double)
                t.column("bone_density_total", .double)
                t.column("notes", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_dexa_scan_date", on: "dexa_scan", columns: ["scan_date"])
        }
    }
}
