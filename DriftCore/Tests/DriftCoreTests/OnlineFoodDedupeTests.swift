import Testing
import Foundation
import GRDB
@testable import DriftCore

/// Tier 0 — the AG1 field-bug fix set (2026-07-14): online-import dedupe,
/// brand-join naming, the phantom "1 scoop (100g)" serving, and the v43
/// cleanup migration.
struct OnlineFoodDedupeTests {

    // MARK: - Normalized key

    @Test func normalizedKeyCollapsesRebrandings() {
        let variants = ["AG1", "Ag1", "ag1", " AG1 ", "AG1!"]
        let keys = Set(variants.map(FoodService.normalizedFoodKey))
        #expect(keys.count == 1)
        // Token-order-insensitive: "AG1 - Athletic Greens" == "Athletic Greens - AG1".
        #expect(FoodService.normalizedFoodKey("AG1 - Athletic Greens")
                == FoodService.normalizedFoodKey("Athletic Greens - AG1"))
        // But genuinely different products stay distinct.
        #expect(FoodService.normalizedFoodKey("AG1")
                != FoodService.normalizedFoodKey("AG1 Travel Packs"))
    }

    // MARK: - OFF display name

    @Test func offDisplayNameSkipsRedundantBrand() {
        #expect(FoodService.offDisplayName(name: "AG1", brand: "AG1") == "AG1")
        #expect(FoodService.offDisplayName(name: "AG1", brand: "Athletic Greens") == "AG1 - Athletic Greens")
        #expect(FoodService.offDisplayName(name: "AG1 by Athletic Greens", brand: "Athletic Greens") == "AG1 by Athletic Greens")
        #expect(FoodService.offDisplayName(name: nil, brand: "Athletic Greens") == "Athletic Greens")
        #expect(FoodService.offDisplayName(name: "AG1", brand: nil) == "AG1")
    }

    // MARK: - Scoop 100 g guard

    @Test func seededScoopAt100gFallsBackToGrams() {
        // "1 scoop (100g)" is per-100g fallback data, not a real scoop (the
        // 416-cal AG1 sheet). Must NOT produce a scoop unit.
        #expect(FoodUnit.unitFromSeededServingUnit("scoop", servingSize: 100) == nil)
        // Real scoop-scale seeds keep their scoop.
        let whey = FoodUnit.unitFromSeededServingUnit("scoop", servingSize: 30)
        #expect(whey?.label == "scoop")
        #expect(whey?.gramsEquivalent == 30)
        // Other units at 100 g are untouched (a 100 g cup is plausible).
        #expect(FoodUnit.unitFromSeededServingUnit("cup", servingSize: 100)?.label == "cup")
    }

    // MARK: - v43 migration dedupe

    private func insertFood(_ db: AppDatabase, name: String, category: String, calories: Double) throws -> Int64 {
        try db.writer.write { conn in
            try conn.execute(sql: """
                INSERT INTO food (name, category, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, fiber_g)
                VALUES (?, ?, 100, 'g', ?, 0, 0, 0, 0)
                """, arguments: [name, category, calories])
            return conn.lastInsertedRowID
        }
    }

    @Test func dedupeDeletesOnlineDupesKeepsCanonical() throws {
        let db = try AppDatabase.empty()
        let curated = try insertFood(db, name: "Ag1", category: "Supplements & Shakes", calories: 50)
        let dupe1 = try insertFood(db, name: "AG1", category: "Online", calories: 416)
        let dupe2 = try insertFood(db, name: "AG1 - Athletic Greens", category: "Online", calories: 416)
        let dupe3 = try insertFood(db, name: "Athletic Greens - AG1", category: "Online", calories: 416)
        let unrelated = try insertFood(db, name: "AG1 Travel Packs", category: "Online", calories: 50)

        try db.writer.write { try Migrations.dedupeOnlineFoods($0) }

        let survivors: Set<Int64> = try db.reader.read {
            Set(try Int64.fetchAll($0, sql: "SELECT id FROM food WHERE id IN (?,?,?,?,?)",
                                    arguments: [curated, dupe1, dupe2, dupe3, unrelated]))
        }
        #expect(survivors.contains(curated))            // canonical survives
        #expect(!survivors.contains(dupe1))             // exact dupe of curated → gone
        #expect(survivors.contains(unrelated))          // different product → kept
        // dupe2/dupe3 share a key with each other (not with curated) → oldest kept.
        #expect(survivors.contains(dupe2))
        #expect(!survivors.contains(dupe3))
    }

    @Test func saveScannedFoodRejectsNormalizedDuplicates() throws {
        // The choke-point fix: EVERY caller (FoodSearchView, chat fallback,
        // barcode, OCR) goes through saveScannedFood, so same-token dupes
        // ("AG1"/"Ag1"/"ag1!") can't persist regardless of surface. Brand-
        // AUGMENTED names ("Athletic Greens - AG1") carry extra tokens and are
        // deliberately allowed — token-subset matching would wrongly reject
        // real distinct products like "AG1 Travel Packs".
        let db = try AppDatabase.empty()
        _ = try insertFood(db, name: "Ag1", category: "Supplements & Shakes", calories: 50)
        var caseDupe = Food(name: "AG1", category: "Online",
                            servingSize: 100, servingUnit: "g",
                            calories: 416, proteinG: 16, carbsG: 50, fatG: 0, fiberG: 17)
        try db.saveScannedFood(&caseDupe)
        var punctDupe = Food(name: " ag1! ", category: "Online",
                             servingSize: 100, servingUnit: "g",
                             calories: 416, proteinG: 16, carbsG: 50, fatG: 0, fiberG: 17)
        try db.saveScannedFood(&punctDupe)
        var genuinelyNew = Food(name: "AG1 Travel Packs", category: "Online",
                                servingSize: 100, servingUnit: "g",
                                calories: 50, proteinG: 2, carbsG: 6, fatG: 0, fiberG: 2)
        try db.saveScannedFood(&genuinelyNew)

        let names = try db.reader.read { try String.fetchAll($0, sql: "SELECT name FROM food ORDER BY name") }
        #expect(names.contains("Ag1"))
        #expect(!names.contains("AG1"))                       // case dupe rejected
        #expect(!names.contains(" ag1! "))                    // punctuation dupe rejected
        #expect(names.contains("AG1 Travel Packs"))           // real product saved
        #expect(names.count == 2, "got \(names)")
    }

    @Test func saveScannedFoodDedupeSurvivesTokenPrefilter() throws {
        // The dedupe scan prefilters candidates with a LIKE on the longest
        // token (perf fix, field report 2026-07-15). Multi-token reorderings
        // must still be caught through that path…
        let db = try AppDatabase.empty()
        _ = try insertFood(db, name: "Athletic Greens - AG1", category: "Online", calories: 416)
        var reordered = Food(name: "AG1 - Athletic Greens", category: "Online",
                             servingSize: 100, servingUnit: "g",
                             calories: 416, proteinG: 16, carbsG: 50, fatG: 0, fiberG: 17)
        try db.saveScannedFood(&reordered)
        // …and non-ASCII probes (LIKE is only ASCII-case-insensitive) must
        // fall back to the full scan rather than silently missing the dupe.
        _ = try insertFood(db, name: "Crème Brûlée", category: "Online", calories: 300)
        var accentDupe = Food(name: "crème brûlée!", category: "Online",
                              servingSize: 100, servingUnit: "g",
                              calories: 300, proteinG: 4, carbsG: 30, fatG: 18, fiberG: 0)
        try db.saveScannedFood(&accentDupe)

        let names = try db.reader.read { try String.fetchAll($0, sql: "SELECT name FROM food") }
        #expect(names.count == 2, "both dupes rejected, got \(names)")
        #expect(names.contains("Athletic Greens - AG1"))
        #expect(names.contains("Crème Brûlée"))
    }

    @Test func dedupeNeverDeletesNonOnlineRows() throws {
        let db = try AppDatabase.empty()
        let a = try insertFood(db, name: "Paneer Tikka", category: "Indian", calories: 300)
        let b = try insertFood(db, name: "paneer tikka", category: "Indian", calories: 280)
        try db.writer.write { try Migrations.dedupeOnlineFoods($0) }
        let count = try db.reader.read {
            try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM food WHERE id IN (?,?)", arguments: [a, b]) ?? 0
        }
        #expect(count == 2)   // curated near-dupes are a curation decision, not this migration's
    }
}
