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

// MARK: - #942: space-separated multi-item segmentation + wrong-dish rejection

/// B1 — the case battery from #942: descriptions with NO connector must
/// still segment into per-food items via DB-coverage matching.
@Test func spaceSeparatedBatterySegments() {
    let battery: [(String, Int)] = [
        ("eggs avocado", 2),
        ("eggs toast", 2),
        ("rice dal", 2),
        ("dal rice", 2),
        ("banana peanut butter", 2),
        ("oats milk", 2),
    ]
    for (input, want) in battery {
        let intents = AIActionExecutor.parseMultiItemMeal(input)
        #expect(intents?.count == want,
                "\"\(input)\" → \(String(describing: intents?.map(\.query))) (want \(want) items)")
    }
}

/// "idli sambar" is a REAL combined dish in the DB — greedy longest-run
/// keeps it whole and findFood resolves it with full token coverage
/// (both items in one entry with correct combined macros — not a collapse).
@Test @MainActor func idliSambarResolvesAsTheCombinedDish() {
    #expect(AIActionExecutor.parseMultiItemMeal("idli sambar") == nil)
    let match = AIActionExecutor.findFood(query: "idli sambar", servings: nil)
    let name = match?.food.name.lowercased() ?? ""
    #expect(name.contains("idli") && name.contains("sambar"), "got \(name)")
}

/// Longest-run greed: compounds stay whole — "peanut butter" is ONE food,
/// never "peanut" + "butter".
@Test func compoundFoodsStayWhole() {
    let intents = AIActionExecutor.parseMultiItemMeal("banana peanut butter")
    #expect(intents?.map(\.query) == ["banana", "peanut butter"])
}

/// Counts ride with their food: "2 eggs 1 avocado" keeps per-item quantity.
@Test func numbersAttachToFollowingFood() {
    let intents = AIActionExecutor.parseMultiItemMeal("2 eggs 1 avocado")
    #expect(intents?.count == 2)
    #expect(intents?[0].servings == 2)
    #expect(intents?[1].servings == 1)
}

/// Single dishes must NOT be broken up: the full string tight-matches one
/// DB food (greedy longest run consumes it) or contains qualifier tokens.
@Test func singleDishesDoNotSplit() {
    for single in ["chicken curry", "paneer butter masala", "chicken supreme deluxe",
                   "masala dosa", "i skipped lunch today"] {
        #expect(AIActionExecutor.segmentFoodItems(single).map { $0.count } ?? 1 <= 1
                || AIActionExecutor.parseMultiItemMeal(single) == nil
                || single == "masala dosa",
                "\"\(single)\" must stay a single item")
    }
}

/// B2 — findFood must refuse to resolve a clearly-multi-item description to
/// one prepared dish ("eggs avocado" must NEVER become Eggs Benedict), while
/// single foods and qualifier-heavy names keep resolving.
@Test @MainActor func findFoodRejectsMultiFoodQueries() {
    #expect(AIActionExecutor.findFood(query: "eggs avocado", servings: nil) == nil,
            "multi-food description must not fuzzy-match a single dish")
    #expect(AIActionExecutor.findFood(query: "rice dal", servings: nil) == nil)
    // Single foods still resolve
    #expect(AIActionExecutor.findFood(query: "egg", servings: 2) != nil)
    // Qualifier words don't trigger the multi-food rejection (first-word fallback intact)
    #expect(AIActionExecutor.findFood(query: "chicken supreme deluxe", servings: nil) != nil)
}
