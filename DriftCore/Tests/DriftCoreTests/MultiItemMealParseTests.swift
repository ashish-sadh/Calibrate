import Testing
@testable import DriftCore

/// Tier-0 gate tests for #898 — multi-item Indian meals must parse one row per
/// item with the quantity bound to the item it modifies. Pins
/// `AIActionExecutor.parseMultiItemMeal`, the single entry both surfaces use
/// (iOS deterministic chat path and the Nebius/agent fallback), so
/// "paneer butter masala with 2 naan" can never again collapse into a
/// single ×2 paneer search with the naan silently dropped.
struct MultiItemMealParseTests {

    // MARK: - Done-When 1: "X with N Y" — naan not dropped, qty on the naan

    @Test func testMultiItemNoDroppedNaan() {
        let intents = AIActionExecutor.parseMultiItemMeal("log paneer butter masala with 2 naan")
        #expect(intents?.count == 2, "Both items must survive — the naan was silently dropped pre-#898")
        #expect(intents?.first?.query.contains("paneer butter masala") == true)
        #expect(intents?.last?.query.contains("naan") == true)
        // Done-When 3: the "2" binds to the naan, NOT the paneer dish.
        #expect(intents?.last?.servings == 2)
        #expect(intents?.first?.servings != 2, "Quantity must not migrate onto the first/main dish")
    }

    // MARK: - Done-When 2: per-item quantity + Indian container strip

    @Test func testMultiItem_OneRowPerItem() {
        let intents = AIActionExecutor.parseMultiItemMeal("log 2 rotis with dal and a bowl of curd")
        #expect(intents?.count == 3, "2 rotis + dal + curd = 3 rows; pre-#898 all collapsed into one ×2 search")
        #expect(intents?[0].query.contains("roti") == true)
        #expect(intents?[0].servings == 2)
        #expect(intents?[1].query.contains("dal") == true)
        // "a bowl of curd" → container stripped, one serving of curd — not a
        // food named "bowl of curd" that food search can never match.
        #expect(intents?[2].query.contains("curd") == true)
        #expect(intents?[2].query.contains("bowl") == false)
    }

    // MARK: - Done-When 4: plain "A, B and C" phrasing (no connector)

    @Test func testMultiItemPlainListSplitsPerItem() {
        let intents = AIActionExecutor.parseMultiItemMeal("log rice, dal and curd")
        #expect(intents?.count == 3)
        let queries = intents?.map(\.query) ?? []
        #expect(queries.contains { $0.contains("rice") })
        #expect(queries.contains { $0.contains("dal") })
        #expect(queries.contains { $0.contains("curd") })
    }

    // MARK: - Guard: single dishes stay on the single-food path

    @Test func testSingleDishDoesNotOverSplit() {
        // Multi-word dish names contain neither a connector nor "and"/"," —
        // parseMultiItemMeal must return nil so the single-food path (with its
        // richer matching) handles them.
        #expect(AIActionExecutor.parseMultiItemMeal("log chicken tikka masala") == nil)
        #expect(AIActionExecutor.parseMultiItemMeal("log paneer butter masala") == nil)
    }
}
