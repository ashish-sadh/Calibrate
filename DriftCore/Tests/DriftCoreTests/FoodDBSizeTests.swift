import Foundation
import Testing
@testable import DriftCore

// Tier-0: foods.json size ceiling (#717).
//
// foods.json ships embedded in the bundle and seeds the DB on cold launch.
// Without a hard cap, USDA-style bulk imports silently bloat install size,
// cold-launch time, and search-result clutter.
//
// Ceiling: 6,000 entries. Hand-curated Indian-first + international cuisine
// sits around 5,000. New imports must be curated, not bulk.

struct FoodDBSizeTests {

    /// Rows of foods.json read from the SOURCE path — Bundle.module of the
    /// test target does not include the source target's resources. The
    /// production code path is `Bundle.module` from inside DriftCore
    /// (AppDatabase.seedFoodsFromJSON).
    private func seedRows() throws -> [[String: Any]] {
        let sourcePath = #filePath
            .replacingOccurrences(of: "Tests/DriftCoreTests/FoodDBSizeTests.swift",
                                  with: "Sources/DriftCore/Resources/foods.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test func foodsJSONSizeUnderCeiling() throws {
        let decoded = try seedRows()
        #expect(decoded.count <= 6000,
            "foods.json has \(decoded.count) entries — ceiling is 6,000. New imports must be curated, not bulk.")
    }

    // #1015/#1017: the curated food DB must stay clean — no duplicate names, no
    // title-cased apostrophes ("Denny'S"), no raw USDA distribution-program cruft.
    @Test func foodsJSONIsCleanAndDeduped() throws {
        let rows = try seedRows()
        let names = rows.compactMap { $0["name"] as? String }

        // #1015: no exact-duplicate names (case-insensitive)
        let dups = Dictionary(grouping: names.map { $0.lowercased() }, by: { $0 })
            .filter { $0.value.count > 1 }.keys
        #expect(dups.isEmpty, "duplicate food names: \(Array(dups).prefix(5))")

        // #1017: no title-cased apostrophes ("Denny'S") and no raw USDA cruft
        let brokenCase = names.filter { $0.range(of: "[a-z]'[A-Z]", options: .regularExpression) != nil }
        #expect(brokenCase.isEmpty, "title-cased apostrophes: \(brokenCase.prefix(5))")
        let cruft = names.filter { $0.contains("Includes Foods For") }
        #expect(cruft.isEmpty, "USDA cruft rows: \(cruft.prefix(5))")
    }

    // Chia audit 2026-07-27: 31 rows stored a COUNT in serving_size ("Chia
    // Seeds" 2 tbsp) where every conversion expects GRAMS — 1 tbsp of chia
    // rendered 690 cal instead of ~69 (10g ÷ 2 "grams" = 5 servings). All rows
    // were gram-normalized; this lint stops the pattern from coming back.
    @Test func foodsJSONServingSizesAreGramSemantics() throws {
        let rows = try seedRows()
        #expect(rows.count > 5000)

        var countSemantics: [String] = []
        var implausibleDensity: [String] = []
        for row in rows {
            let name = row["name"] as? String ?? "?"
            let unit = (row["serving_unit"] as? String ?? "g").lowercased()
            let size = (row["serving_size"] as? NSNumber)?.doubleValue ?? 0
            let cal = (row["calories"] as? NSNumber)?.doubleValue ?? 0
            // A non-gram unit with a tiny serving_size means the field holds a
            // count ("2 tbsp", "3 pieces"), which the serving math divides by
            // as if it were grams. Human units are fine when size is grams
            // ("packet" 46, "sandwich" 210).
            if unit != "g", unit != "ml", size < 15 {
                countSemantics.append("\(name): \(size) \(unit)")
            }
            // Pure fat is 9 cal/g — anything denser is a data error.
            if size > 0, cal / size > 9.2 {
                implausibleDensity.append("\(name): \(cal) cal / \(size)g")
            }
        }
        #expect(countSemantics.isEmpty,
            "serving_size holds a count, not grams (the chia 10× bug): \(countSemantics.prefix(5))")
        #expect(implausibleDensity.isEmpty,
            "calorie density above pure fat: \(implausibleDensity.prefix(5))")
    }
}
