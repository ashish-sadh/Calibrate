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

        // v7: Expanded DEXA with regional L/R data
        migrator.registerMigration("v7_dexa_regional") { db in
            try db.create(table: "dexa_region") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("scan_id", .integer).notNull().references("dexa_scan", onDelete: .cascade)
                t.column("region", .text).notNull() // arms, legs, trunk, android, gynoid, total, r_arm, l_arm, r_leg, l_leg
                t.column("fat_pct", .double)
                t.column("total_mass_lbs", .double)
                t.column("fat_mass_lbs", .double)
                t.column("lean_mass_lbs", .double)
                t.column("bmc_lbs", .double)
            }
            try db.create(index: "idx_dexa_region_scan", on: "dexa_region", columns: ["scan_id"])

            // Add RMR and VAT volume to dexa_scan
            try db.alter(table: "dexa_scan") { t in
                t.add(column: "rmr_calories", .double)
                t.add(column: "vat_volume_in3", .double)
                t.add(column: "ag_ratio", .double)
            }
        }

        // v8: Barcode cache + serving sizes
        migrator.registerMigration("v8_barcode_cache") { db in
            try db.create(table: "barcode_cache") { t in
                t.primaryKey("barcode", .text)
                t.column("name", .text).notNull()
                t.column("brand", .text)
                t.column("calories_per_100g", .double).notNull()
                t.column("protein_g_per_100g", .double).notNull().defaults(to: 0)
                t.column("carbs_g_per_100g", .double).notNull().defaults(to: 0)
                t.column("fat_g_per_100g", .double).notNull().defaults(to: 0)
                t.column("fiber_g_per_100g", .double).notNull().defaults(to: 0)
                t.column("serving_size_g", .double)
                t.column("serving_description", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }

            // Add serving columns to food table
            try db.alter(table: "food") { t in
                t.add(column: "serving_size_2", .double)
                t.add(column: "serving_unit_2", .text)
                t.add(column: "serving_size_3", .double)
                t.add(column: "serving_unit_3", .text)
            }
        }

        // v9: Favorites and recipes
        migrator.registerMigration("v9_favorites_recipes") { db in
            try db.create(table: "favorite_food") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("calories", .double).notNull()
                t.column("protein_g", .double).notNull().defaults(to: 0)
                t.column("carbs_g", .double).notNull().defaults(to: 0)
                t.column("fat_g", .double).notNull().defaults(to: 0)
                t.column("fiber_g", .double).notNull().defaults(to: 0)
                t.column("default_servings", .double).notNull().defaults(to: 1)
                t.column("is_recipe", .boolean).notNull().defaults(to: false)
                t.column("sort_order", .integer).notNull().defaults(to: 0)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }

        // v10: Workout tracker
        migrator.registerMigration("v10_workouts") { db in
            try db.create(table: "exercise") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("body_part", .text).notNull()  // chest, back, legs, shoulders, arms, core, full_body
                t.column("category", .text).notNull()    // barbell, dumbbell, machine, cable, bodyweight, other
                t.column("is_custom", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "workout") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("date", .text).notNull()
                t.column("duration_seconds", .integer)
                t.column("notes", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_workout_date", on: "workout", columns: ["date"])

            try db.create(table: "workout_set") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("workout_id", .integer).notNull().references("workout", onDelete: .cascade)
                t.column("exercise_name", .text).notNull()
                t.column("set_order", .integer).notNull()
                t.column("weight_lbs", .double)
                t.column("reps", .integer)
                t.column("is_warmup", .boolean).notNull().defaults(to: false)
                t.column("rpe", .double)
            }
            try db.create(index: "idx_workout_set_workout", on: "workout_set", columns: ["workout_id"])

            try db.create(table: "workout_template") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("exercises_json", .text).notNull() // JSON array of exercise names + default sets
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
        }

        // v11: Supplement frequency
        migrator.registerMigration("v11_supplement_frequency") { db in
            try db.alter(table: "supplement") { t in
                t.add(column: "daily_doses", .integer).defaults(to: 1)     // how many times per day
                t.add(column: "reminder_time", .text)                       // HH:mm format, nil = no reminder
            }
        }

        // v12: Biomarker tracking
        migrator.registerMigration("v12_biomarkers") { db in
            try db.create(table: "lab_report") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("report_date", .text).notNull()
                t.column("lab_name", .text)
                t.column("file_name", .text).notNull()
                t.column("file_data_hash", .text).notNull().defaults(to: "")
                t.column("marker_count", .integer).notNull().defaults(to: 0)
                t.column("notes", .text)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_lab_report_date", on: "lab_report", columns: ["report_date"])

            try db.create(table: "biomarker_result") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("report_id", .integer).notNull()
                    .references("lab_report", onDelete: .cascade)
                t.column("biomarker_id", .text).notNull()
                t.column("value", .double).notNull()
                t.column("unit", .text).notNull()
                t.column("normalized_value", .double).notNull()
                t.column("normalized_unit", .text).notNull()
                t.column("reference_low", .double)
                t.column("reference_high", .double)
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(index: "idx_biomarker_result_report", on: "biomarker_result", columns: ["report_id"])
            try db.create(index: "idx_biomarker_result_marker", on: "biomarker_result", columns: ["biomarker_id"])
        }

        // v13: Food usage tracking for smart search ranking
        migrator.registerMigration("v13_food_usage") { db in
            try db.create(table: "food_usage") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("food_name", .text).notNull().unique()
                t.column("food_id", .integer)
                t.column("use_count", .integer).notNull().defaults(to: 1)
                t.column("last_used", .text).notNull()
                t.column("last_servings", .double).notNull().defaults(to: 1)
            }
            try db.create(index: "idx_food_usage_count", on: "food_usage", columns: ["use_count"])
            try db.create(index: "idx_food_usage_last", on: "food_usage", columns: ["last_used"])
        }
    }
}
