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

        // v14: Template favorites
        migrator.registerMigration("v14_template_favorites") { db in
            try db.alter(table: "workout_template") { t in
                t.add(column: "is_favorite", .boolean).notNull().defaults(to: false)
            }
        }

        // v15: Food favorites (user-starred items)
        migrator.registerMigration("v15_food_favorites") { db in
            try db.alter(table: "food_usage") { t in
                t.add(column: "is_favorite", .boolean).notNull().defaults(to: false)
            }
        }

        // v16: Food entry logged_at (time eaten, for ordering)
        migrator.registerMigration("v16_food_logged_at") { db in
            try db.alter(table: "food_entry") { t in
                t.add(column: "logged_at", .text).notNull().defaults(to: "")
            }
            try db.execute(sql: "UPDATE food_entry SET logged_at = created_at WHERE logged_at = ''")
        }

        // v17: Workout set duration + exercise order
        migrator.registerMigration("v17_workout_duration_order") { db in
            try db.alter(table: "workout_set") { t in
                t.add(column: "duration_sec", .integer)
                t.add(column: "exercise_order", .integer).notNull().defaults(to: 0)
            }
        }

        // v18: Body composition fields on weight entries
        migrator.registerMigration("v18_body_composition") { db in
            try db.alter(table: "weight_entry") { t in
                t.add(column: "body_fat_pct", .double)
                t.add(column: "bmi", .double)
                t.add(column: "water_pct", .double)
            }
        }

        // v19: Separate body_composition table + migrate from weight_entry
        migrator.registerMigration("v19_body_composition_table") { db in
            try db.create(table: "body_composition") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("date", .text).notNull()
                t.column("body_fat_pct", .double)
                t.column("bmi", .double)
                t.column("water_pct", .double)
                t.column("source", .text).notNull().defaults(to: "manual")
                t.column("created_at", .text).notNull().defaults(sql: "(datetime('now'))")
            }
            try db.create(indexOn: "body_composition", columns: ["date"])

            // Migrate existing data from weight_entry
            try db.execute(sql: """
                INSERT INTO body_composition (date, body_fat_pct, bmi, water_pct, source, created_at)
                SELECT date, body_fat_pct, bmi, water_pct, 'manual', created_at
                FROM weight_entry
                WHERE body_fat_pct IS NOT NULL OR bmi IS NOT NULL OR water_pct IS NOT NULL
            """)
        }

        // v20: Extended body composition fields (muscle, bone, visceral, metabolic age)
        migrator.registerMigration("v20_extended_body_comp") { db in
            try db.alter(table: "body_composition") { t in
                t.add(column: "muscle_mass_kg", .double)
                t.add(column: "bone_mass_kg", .double)
                t.add(column: "visceral_fat", .double)
                t.add(column: "metabolic_age", .integer)
            }
        }

        // v21: Add macros to food_usage for reliable recents (manual entries had 0 cal)
        migrator.registerMigration("v21_food_usage_macros") { db in
            try db.alter(table: "food_usage") { t in
                t.add(column: "calories", .double).notNull().defaults(to: 0)
                t.add(column: "protein_g", .double).notNull().defaults(to: 0)
                t.add(column: "carbs_g", .double).notNull().defaults(to: 0)
                t.add(column: "fat_g", .double).notNull().defaults(to: 0)
                t.add(column: "fiber_g", .double).notNull().defaults(to: 0)
                t.add(column: "serving_size_g", .double).notNull().defaults(to: 0)
            }
            // Backfill existing food_usage rows from the food table where possible
            try db.execute(sql: """
                UPDATE food_usage SET
                    calories = COALESCE((SELECT f.calories FROM food f WHERE f.id = food_usage.food_id), 0),
                    protein_g = COALESCE((SELECT f.protein_g FROM food f WHERE f.id = food_usage.food_id), 0),
                    carbs_g = COALESCE((SELECT f.carbs_g FROM food f WHERE f.id = food_usage.food_id), 0),
                    fat_g = COALESCE((SELECT f.fat_g FROM food f WHERE f.id = food_usage.food_id), 0),
                    fiber_g = COALESCE((SELECT f.fiber_g FROM food f WHERE f.id = food_usage.food_id), 0),
                    serving_size_g = COALESCE((SELECT f.serving_size FROM food f WHERE f.id = food_usage.food_id), 0)
                WHERE food_id IS NOT NULL
                """)
        }

        // v22: Add ingredients column to food and favorite_food for plant points
        migrator.registerMigration("v22_food_ingredients") { db in
            try db.alter(table: "food") { t in
                t.add(column: "ingredients", .text) // JSON array: '["rice","onion","turmeric"]'
            }
            try db.alter(table: "favorite_food") { t in
                t.add(column: "ingredients", .text)
            }
            // Default: simple foods get [self.name]
            try db.execute(sql: """
                UPDATE food SET ingredients = '["' || REPLACE(name, '"', '\\"') || '"]'
                WHERE ingredients IS NULL
                """)
        }

        // v23: Rename favorite_food → saved_food (cleaner data model)
        migrator.registerMigration("v23_rename_saved_food") { db in
            try db.rename(table: "favorite_food", to: "saved_food")
        }

        // v24: Add source column to food table for unified food storage
        migrator.registerMigration("v24_food_source") { db in
            try db.alter(table: "food") { t in
                t.add(column: "source", .text) // "database", "recipe", "barcode", "custom"
            }
            // Mark existing seeded foods
            try db.execute(sql: "UPDATE food SET source = 'database' WHERE source IS NULL AND category != 'Scanned'")
            // Mark barcode scans
            try db.execute(sql: "UPDATE food SET source = 'barcode' WHERE source IS NULL AND category = 'Scanned'")
        }

        // v25: Merge saved_food into food table — unified food storage
        migrator.registerMigration("v25_merge_saved_food") { db in
            // Add saved_food columns to food table
            try db.alter(table: "food") { t in
                t.add(column: "is_recipe", .boolean).notNull().defaults(to: false)
                t.add(column: "sort_order", .integer).notNull().defaults(to: 0)
                t.add(column: "default_servings", .double).notNull().defaults(to: 1)
            }
            // Copy saved_food rows into food table
            try db.execute(sql: """
                INSERT INTO food (name, category, serving_size, serving_unit, calories,
                                  protein_g, carbs_g, fat_g, fiber_g, ingredients,
                                  source, is_recipe, sort_order, default_servings)
                SELECT sf.name, CASE WHEN sf.is_recipe THEN 'Recipe' ELSE 'Saved' END,
                       1.0, 'serving', sf.calories,
                       sf.protein_g, sf.carbs_g, sf.fat_g, sf.fiber_g, sf.ingredients,
                       'recipe', sf.is_recipe, sf.sort_order, sf.default_servings
                FROM saved_food sf
                WHERE NOT EXISTS (SELECT 1 FROM food f WHERE LOWER(f.name) = LOWER(sf.name))
                """)
        }

        // v26: Flatten meal_log into food_entry — add date + meal_type columns
        migrator.registerMigration("v26_flatten_meal_log") { db in
            try db.alter(table: "food_entry") { t in
                t.add(column: "date", .text)       // "YYYY-MM-DD"
                t.add(column: "meal_type", .text)   // "breakfast" | "lunch" | "dinner" | "snack"
            }
            // Backfill from meal_log
            try db.execute(sql: """
                UPDATE food_entry SET
                    date = (SELECT ml.date FROM meal_log ml WHERE ml.id = food_entry.meal_log_id),
                    meal_type = (SELECT ml.meal_type FROM meal_log ml WHERE ml.id = food_entry.meal_log_id)
                """)
            // Index for date queries
            try db.create(index: "idx_food_entry_date", on: "food_entry", columns: ["date"])
        }

        // v27: Add NOVA processing group to food table for plant points accuracy
        migrator.registerMigration("v27_food_nova_group") { db in
            try db.alter(table: "food") { t in
                t.add(column: "nova_group", .integer) // 1=unprocessed, 2=culinary, 3=processed, 4=ultra-processed
            }
            // Backfill NOVA groups based on food category
            // NOVA 1: Unprocessed/minimally processed
            try db.execute(sql: """
                UPDATE food SET nova_group = 1 WHERE category IN (
                    'Fruits', 'Vegetables', 'Nuts & Seeds', 'Proteins'
                ) AND nova_group IS NULL
                """)
            // NOVA 2: Processed culinary ingredients
            try db.execute(sql: """
                UPDATE food SET nova_group = 2 WHERE category IN (
                    'Oils & Fats', 'Condiments', 'Sweeteners'
                ) AND nova_group IS NULL
                """)
            // NOVA 4: Ultra-processed
            try db.execute(sql: """
                UPDATE food SET nova_group = 4 WHERE category IN (
                    'Fast Food', 'Snacks', 'Ready Meals', 'Desserts', 'Indian Sweets',
                    'Supplements & Shakes'
                ) AND nova_group IS NULL
                """)
            // NOVA 3: Everything else (Dairy, Grains, Indian Staples, US Staples, Mexican, etc.)
            try db.execute(sql: "UPDATE food SET nova_group = 3 WHERE nova_group IS NULL")
        }

        // v28: Soft-delete for weight entries (hidden flag prevents HealthKit re-sync)
        migrator.registerMigration("v28_weight_hidden") { db in
            try db.alter(table: "weight_entry") { t in
                t.add(column: "hidden", .boolean).notNull().defaults(to: false)
            }
        }

        // v29: Search miss tracking — log queries that return zero local results
        migrator.registerMigration("v29_search_miss") { db in
            try db.create(table: "search_miss") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("query", .text).notNull().unique()
                t.column("miss_count", .integer).notNull().defaults(to: 1)
                t.column("last_seen", .text).notNull().defaults(sql: "(date('now'))")
            }
        }

        // v30: LLM confidence + AI-parsed flag on biomarker results
        migrator.registerMigration("v30_biomarker_ai_parsed") { db in
            try db.alter(table: "biomarker_result") { t in
                t.add(column: "confidence", .double)
                t.add(column: "is_ai_parsed", .boolean).notNull().defaults(to: false)
            }
        }

        // v31: expand_on_log on food — when true for a recipe, re-logging
        // inserts one FoodEntry per ingredient instead of one aggregated
        // entry (lets a recipe act as a named "meal group").
        migrator.registerMigration("v31_recipe_expand_on_log") { db in
            try db.alter(table: "food") { t in
                t.add(column: "expand_on_log", .boolean).notNull().defaults(to: false)
            }
        }

        // v32: AI chat local telemetry (opt-in, on-device only). #261
        // Stores hashed fingerprint (not raw text), routed intent, tool, outcome,
        // and latency so we can surface real failure categories. 5k-row ring buffer.
        migrator.registerMigration("v32_chat_telemetry") { db in
            try db.create(table: "chat_turn") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("timestamp", .text).notNull()
                t.column("query_fingerprint", .text).notNull()
                t.column("intent_label", .text)
                t.column("tool_called", .text)
                t.column("outcome", .text).notNull()
                t.column("latency_ms", .integer).notNull().defaults(to: 0)
                t.column("turn_index", .integer).notNull().defaults(to: 0)
            }
            try db.create(index: "idx_chat_turn_timestamp", on: "chat_turn", columns: ["timestamp"])
        }

        // v33: Store raw query + response text in telemetry so exports can feed
        // multi-turn failure analysis. Nullable so pre-v33 rows (fingerprint-only)
        // stay valid. Still on-device only; transmission only via user-initiated
        // Export JSON.
        migrator.registerMigration("v33_chat_telemetry_text") { db in
            try db.alter(table: "chat_turn") { t in
                t.add(column: "query_text", .text)
                t.add(column: "response_text", .text)
            }
        }
    }
}
