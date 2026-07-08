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

    @Test func foodsJSONSizeUnderCeiling() throws {
        // Read from source path — Bundle.module of the test target does not
        // include the source target's resources. The production code path
        // is `Bundle.module` from inside DriftCore (AppDatabase.seedFoodsFromJSON).
        let sourcePath = #filePath
            .replacingOccurrences(of: "Tests/DriftCoreTests/FoodDBSizeTests.swift",
                                  with: "Sources/DriftCore/Resources/foods.json")
        let url = URL(fileURLWithPath: sourcePath)
        let data = try Data(contentsOf: url)
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [Any])
        #expect(decoded.count <= 6000,
            "foods.json has \(decoded.count) entries — ceiling is 6,000. New imports must be curated, not bulk.")
    }

    // #1015/#1017: the curated food DB must stay clean — no duplicate names, no
    // title-cased apostrophes ("Denny'S"), no raw USDA distribution-program cruft.
    @Test func foodsJSONIsCleanAndDeduped() throws {
        let sourcePath = #filePath
            .replacingOccurrences(of: "Tests/DriftCoreTests/FoodDBSizeTests.swift",
                                  with: "Sources/DriftCore/Resources/foods.json")
        let data = try Data(contentsOf: URL(fileURLWithPath: sourcePath))
        let rows = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
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
}
