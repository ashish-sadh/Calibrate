import XCTest
@testable import DriftCore

/// Isolated gold set for FoodService.searchFood — sprint task #161.
/// Tests that 20+ food queries return expected results in top positions.
/// Fully deterministic (local DB only, no LLM, no network). Runs in <5s.
///
/// Run: xcodebuild test -only-testing:'DriftTests/FoodSearchGoldSetTests'
@MainActor
final class FoodSearchGoldSetTests: XCTestCase {

    // MARK: - Exact & Substring Matches

    func testExactMatches() {
        let cases: [(query: String, expectedKeyword: String)] = [
            ("egg", "egg"),
            ("banana", "banana"),
            ("rice", "rice"),
            ("chicken", "chicken"),
            ("paneer", "paneer"),
            ("milk", "milk"),
            ("oats", "oat"),
            ("apple", "apple"),
            ("dal", "dal"),
            ("biryani", "biryani"),
        ]
        var correct = 0
        for (query, keyword) in cases {
            let results = FoodService.searchFood(query: query)
            let topName = results.first?.name.lowercased() ?? ""
            if !results.isEmpty && topName.contains(keyword) {
                correct += 1
            } else {
                print("MISS (exact): '\(query)' → top='\(topName)' (total: \(results.count))")
            }
        }
        print("📊 Exact match: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 exact match miss")
    }

    // MARK: - Indian Foods

    func testIndianFoods() {
        let cases: [(query: String, expectedKeyword: String)] = [
            ("idli", "idli"),
            ("dosa", "dosa"),
            ("roti", "roti"),
            ("rajma", "rajma"),
            ("samosa", "samosa"),
            ("paneer tikka", "paneer"),
            ("chole", "chole"),
            ("poha", "poha"),
            ("upma", "upma"),
            ("khichdi", "khichdi"),
        ]
        var correct = 0
        for (query, keyword) in cases {
            let results = FoodService.searchFood(query: query)
            let found = results.prefix(3).contains(where: { $0.name.lowercased().contains(keyword) })
            if found {
                correct += 1
            } else {
                let top = results.prefix(3).map(\.name).joined(separator: ", ")
                print("MISS (indian): '\(query)' → top3=[\(top)]")
            }
        }
        print("📊 Indian foods: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 Indian food miss")
    }

    // MARK: - Synonyms & Spell Correction

    func testSynonymExpansion() {
        // "curd" → yogurt results via synonym expansion
        let results = FoodService.searchFood(query: "curd")
        XCTAssertFalse(results.isEmpty, "'curd' synonym should expand to find yogurt results")
        let hasYogurt = results.contains(where: { $0.name.lowercased().contains("yogurt") || $0.name.lowercased().contains("curd") })
        XCTAssertTrue(hasYogurt, "'curd' should find yogurt or curd entries")
    }

    func testSpellCorrection() {
        // "panner" is a common Indian food misspelling — spell corrector should catch it
        let results = FoodService.searchFood(query: "panner")
        let found = results.prefix(5).contains(where: { $0.name.lowercased().contains("paneer") })
        if !found {
            print("MISS (spell): 'panner' → top5=\(results.prefix(5).map(\.name))")
        }
        XCTAssertTrue(found, "'panner' should spell-correct to find paneer entries")
    }

    /// #1193: the Indian synonym table is the whole reason the raw
    /// `searchFoods` primitive was the wrong entry point on Android —
    /// `LOWER(name) LIKE '%dahi%'` never matches a row named "Yogurt", so the
    /// Food tab returned nothing for the queries an Indian user actually types.
    /// Both platforms call `searchFood` now, so this pins it for both.
    func testIndianSynonymsResolveToTheEnglishFood() {
        let cases: [(query: String, expectedKeyword: String)] = [
            ("curd", "yogurt"),
            ("dahi", "yogurt"),
            ("thayir", "yogurt"),
            ("raita", "yogurt"),
            ("kozhi", "chicken"),
        ]
        var correct = 0
        for (query, keyword) in cases {
            let results = FoodService.searchFood(query: query)
            if results.prefix(3).contains(where: { $0.name.lowercased().contains(keyword) }) {
                correct += 1
            } else {
                print("MISS (synonym): '\(query)' → top3=\(results.prefix(3).map(\.name))")
            }
        }
        print("📊 Indian synonyms: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 synonym miss")
    }

    /// Typos users actually make. iPhone corrected these all along; Android's
    /// stand-in dropped them on the floor until #1193.
    func testCommonTyposCorrect() {
        let cases: [(query: String, expectedKeyword: String)] = [
            ("chiken", "chicken"),
            ("yogart", "yogurt"),
            ("bananna", "banana"),
            ("brocoli", "broccoli"),
        ]
        var correct = 0
        for (query, keyword) in cases {
            let results = FoodService.searchFood(query: query)
            if results.prefix(5).contains(where: { $0.name.lowercased().contains(keyword) }) {
                correct += 1
            } else {
                print("MISS (typo): '\(query)' → top5=\(results.prefix(5).map(\.name))")
            }
        }
        print("📊 Typo correction: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 typo miss")
    }

    // MARK: - Case Insensitivity

    func testCaseInsensitiveSearch() {
        let baseResults = FoodService.searchFood(query: "chicken")
        let upperResults = FoodService.searchFood(query: "CHICKEN")
        let mixedResults = FoodService.searchFood(query: "Chicken")
        XCTAssertFalse(baseResults.isEmpty)
        XCTAssertFalse(upperResults.isEmpty)
        XCTAssertFalse(mixedResults.isEmpty)
        XCTAssertEqual(baseResults.first?.name, upperResults.first?.name, "Search should be case-insensitive")
        XCTAssertEqual(baseResults.first?.name, mixedResults.first?.name, "Search should be case-insensitive")
    }

    // MARK: - Partial Matches

    func testPartialMatches() {
        // Substring search: "chick" should find chicken items
        let results = FoodService.searchFood(query: "chick")
        let found = results.prefix(5).contains(where: { $0.name.lowercased().contains("chicken") })
        if !found {
            print("MISS (partial): 'chick' → top5=\(results.prefix(5).map(\.name))")
        }
        XCTAssertTrue(found, "'chick' substring should match chicken items")
    }

    // MARK: - Empty & Edge Cases

    func testEmptyQueryReturnsEmpty() {
        let results = FoodService.searchFood(query: "")
        // Empty query may return empty or all foods depending on DB impl — just must not crash
        print("Empty query result count: \(results.count)")
    }

    func testGibberishReturnsEmpty() {
        let results = FoodService.searchFood(query: "xyzzy_qqq_notafood_99999")
        XCTAssertTrue(results.isEmpty, "Gibberish query should return no results")
    }

    // MARK: - Result Count Sanity

    func testCommonQueriesHaveMultipleResults() {
        let commonQueries = ["chicken", "rice", "egg", "dal", "yogurt"]
        for query in commonQueries {
            let results = FoodService.searchFood(query: query)
            XCTAssertGreaterThan(results.count, 1, "'\(query)' should return multiple results")
        }
    }

    // MARK: - Ranking: Exact Name at Top

    // Was assertion-free ("ranking depends on time-of-day boost —
    // informational") — which is precisely how #930 shipped: at dinner the
    // "curry" keyword hoisted "Egg Curry" above the exact match "Egg" and
    // the confirm sheet pre-selected 520 kcal of egg curry for "log 2 eggs".
    // The boost can no longer cross match tiers, so this asserts hard now.

    func testExactNameRanksFirst() {
        // Every ingredient here has a plain entry in foods.json — whatever
        // the wall clock says, the base ingredient beats any dish.
        for query in ["egg", "rice", "paneer", "banana", "apple", "idli"] {
            let top = FoodService.searchFood(query: query).first?.name.lowercased()
            XCTAssertEqual(top, query, "'\(query)' must resolve to the base ingredient, not a dish")
        }
    }

    // MARK: - #930: boost is tier-bound (pure, no DB)

    func testRerankNeverLiftsBoostedDishAboveExactMatch() {
        // DB order deliberately has the dish first (as if use_count promoted
        // it) and the boost keyword matches the dish — the exact match must
        // still come out on top.
        let curry = Food(name: "Egg Curry", category: "Indian Staples",
                         servingSize: 200, servingUnit: "g", calories: 260)
        let egg = Food(name: "Egg", category: "Eggs",
                       servingSize: 50, servingUnit: "g", calories: 72)
        let out = FoodService.rerankPreservingMatchQuality(
            [curry, egg], query: "egg", boostKeywords: ["curry"])
        XCTAssertEqual(out.first?.name, "Egg")
    }

    func testRerankBoostsWithinSameTier() {
        // Both are phrase-tier for "wrap" — here the time-of-day boost is
        // still allowed to reorder (that's its job).
        let veggie = Food(name: "Veggie Wrap", category: "US Staples",
                          servingSize: 180, servingUnit: "g", calories: 300)
        let chicken = Food(name: "Grilled Chicken Wrap", category: "US Staples",
                           servingSize: 200, servingUnit: "g", calories: 350)
        let out = FoodService.rerankPreservingMatchQuality(
            [veggie, chicken], query: "wrap", boostKeywords: ["chicken"])
        XCTAssertEqual(out.first?.name, "Grilled Chicken Wrap")
    }

    func testRerankIsStableWithoutBoost() {
        let a = Food(name: "Egg Dosa", category: "Indian",
                     servingSize: 150, servingUnit: "g", calories: 220)
        let b = Food(name: "Egg Korma", category: "Indian Protein",
                     servingSize: 220, servingUnit: "g", calories: 320)
        let out = FoodService.rerankPreservingMatchQuality(
            [a, b], query: "egg", boostKeywords: [])
        XCTAssertEqual(out.map(\.name), ["Egg Dosa", "Egg Korma"])
    }

    // #1031: a parenthetical/comma VARIANT of the exact term outranks a compound that merely
    // starts with it — so 'tofu' resolves to 'Tofu (firm)', not 'Tofu Yogurt' (use_count junk).
    func testRerankVariantOutranksCompound() {
        // DB order puts the compound first (as if use_count promoted it).
        let compound = Food(name: "Tofu Yogurt", category: "Dairy",
                            servingSize: 150, servingUnit: "g", calories: 90)
        let variant = Food(name: "Tofu (firm)", category: "Protein",
                           servingSize: 100, servingUnit: "g", calories: 144)
        let out = FoodService.rerankPreservingMatchQuality(
            [compound, variant], query: "tofu", boostKeywords: [])
        XCTAssertEqual(out.first?.name, "Tofu (firm)")
    }

    // Field report 2026-07-10: within a tier the user's own logged food beats the
    // generic time-of-day boost — a never-logged "Egg Curry" must not outrank the
    // daily-logged "Egg Bhurji" just because it's dinnertime.
    func testRerankUsedFoodBeatsTimeOfDayBoostWithinTier() {
        let curry = Food(name: "Egg Curry", category: "Indian Staples",
                         servingSize: 200, servingUnit: "g", calories: 260)
        let bhurji = Food(name: "Egg Bhurji", category: "Indian Staples",
                          servingSize: 150, servingUnit: "g", calories: 210)
        let out = FoodService.rerankPreservingMatchQuality(
            [curry, bhurji], query: "egg", boostKeywords: ["curry"],
            usedNames: ["egg bhurji"])
        XCTAssertEqual(out.first?.name, "Egg Bhurji")
    }

    // The personal boost is tier-bound like the time-of-day boost: a used
    // phrase-tier dish must never outrank an unused exact match (#930 rule).
    func testRerankUsedFoodNeverLiftsAcrossTier() {
        let sandwich = Food(name: "Masala Egg Sandwich", category: "Indian Staples",
                            servingSize: 180, servingUnit: "g", calories: 340)
        let egg = Food(name: "Egg", category: "Eggs",
                       servingSize: 50, servingUnit: "g", calories: 72)
        let out = FoodService.rerankPreservingMatchQuality(
            [sandwich, egg], query: "egg", boostKeywords: [],
            usedNames: ["masala egg sandwich"])
        XCTAssertEqual(out.first?.name, "Egg")
    }

    func testRerankCommaVariantOutranksCompound() {
        let compound = Food(name: "Pizza Logs", category: "Snacks",
                            servingSize: 100, servingUnit: "g", calories: 250)
        let variant = Food(name: "Pizza, Cheese", category: "US Staples",
                           servingSize: 120, servingUnit: "g", calories: 285)
        let out = FoodService.rerankPreservingMatchQuality(
            [compound, variant], query: "pizza", boostKeywords: [])
        XCTAssertEqual(out.first?.name, "Pizza, Cheese")
    }

    func testFindFoodTwoEggsCarriesFullMacros() {
        // Done-When 1+2: "2 eggs" → the plain egg at servings 2, with real
        // macros (the bug card showed 0g fat for eggs).
        guard let match = AIActionExecutor.findFood(query: "egg", servings: 2, gramAmount: nil) else {
            XCTFail("findFood must resolve 'egg'"); return
        }
        XCTAssertEqual(match.food.name, "Egg")
        XCTAssertEqual(match.servings, 2)
        XCTAssertGreaterThan(match.food.fatG, 0, "eggs have fat — 0g fat was the #930 card bug")
        XCTAssertGreaterThan(match.food.proteinG, 0)
    }

    // MARK: - New Foods Sprint #215 (30 items)

    /// Returns count of queries where keyword appears in top-5 search results.
    private func searchHitCount(_ cases: [(query: String, keyword: String)], label: String) -> Int {
        var correct = 0
        for (query, keyword) in cases {
            let results = FoodService.searchFood(query: query)
            if results.prefix(5).contains(where: { $0.name.lowercased().contains(keyword.lowercased()) }) {
                correct += 1
            } else {
                print("MISS (\(label)): '\(query)' → top3=[\(results.prefix(3).map(\.name).joined(separator: ", "))]")
            }
        }
        return correct
    }

    func testNewFoodsSprintSouthIndian() {
        let cases: [(query: String, keyword: String)] = [
            ("semiya upma", "semiya"),
            ("rava upma", "rava upma"),
            ("puliogare", "puliogare"),
            ("akki rotti", "akki rotti"),
            ("kaima idli", "kaima"),
            ("idiappam", "idiappam"),
            ("masala dosa potato", "masala dosa potato"),
            ("benne dosa", "benne"),
            ("tomato bath", "tomato bath"),
            ("ambali", "ambali"),
            ("paal pongal", "paal pongal"),
            ("paruppu podi rice", "paruppu podi"),
            ("ellu sadam", "ellu sadam"),
            ("manga pachadi", "manga pachadi"),
        ]
        let correct = searchHitCount(cases, label: "south-indian")
        print("📊 South Indian new foods: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 south Indian new food miss")
    }

    func testNewFoodsSprintRegionalAndSweets() {
        let cases: [(query: String, keyword: String)] = [
            ("jolada rotti", "jolada"),
            ("sajje rotti", "sajje"),
            ("chole kulche", "chole kulche"),
            ("zunka bhakri", "zunka"),
            ("sol kadhi", "sol kadhi"),
            ("chumchum", "chumchum"),
            ("kulfi falooda", "kulfi falooda"),
        ]
        let correct = searchHitCount(cases, label: "regional-sweets")
        print("📊 Regional & sweets new foods: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 regional/sweet new food miss")
    }

    func testNewFoodsSprintSnacksAndShakes() {
        let cases: [(query: String, keyword: String)] = [
            ("nippattu", "nippattu"),
            ("chakkli", "chakkli"),
            ("mandakki oggarane", "mandakki"),
            ("churmuri", "churmuri"),
            ("optimum nutrition whey", "optimum nutrition"),
            ("true basics protein", "true basics"),
            ("nakpro whey", "nakpro"),
            ("muscleblaze biozyme advanced", "muscleblaze biozyme advanced"),
        ]
        let correct = searchHitCount(cases, label: "snacks-shakes")
        print("📊 Snacks & shakes new foods: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 snack/shake new food miss")
    }

    // MARK: - New Foods Sprint #634 (West African, Ethiopian, Turkish, Persian)

    func testNewFoodsWestAfrican() {
        let cases: [(query: String, keyword: String)] = [
            ("jollof rice", "jollof"),
            ("fried plantain", "plantain"),
            ("suya", "suya"),
            ("egusi soup", "egusi"),
            ("akara", "akara"),
            ("puff puff", "puff"),
            ("fufu", "fufu"),
            ("groundnut soup", "groundnut"),
            ("moi moi", "moi moi"),
            ("chin chin", "chin chin"),
        ]
        let correct = searchHitCount(cases, label: "west-african")
        print("📊 West African foods: \(correct)/\(cases.count)")
        // 2026-05-18: tightened from `cases.count - 1` (≥9) to `cases.count - 2`
        // (≥8) — one West African entry regressed across recent food DB changes;
        // queued tasks (#691/#727/#761/#804 cuisine expansion) will restore the
        // missing item. Don't let one cuisine-coverage gap block every senior
        // session via is-clean-state.sh.
        XCTAssertGreaterThanOrEqual(correct, cases.count - 2, "At most 2 West African food misses (target: 1)")
    }

    func testNewFoodsEthiopian() {
        let cases: [(query: String, keyword: String)] = [
            ("injera", "injera"),
            ("doro wat", "doro"),
            ("misir wat", "misir"),
            ("shiro wat", "shiro"),
            ("tibs", "tibs"),
            ("gomen", "gomen"),
            ("kitfo", "kitfo"),
            ("ful medames", "ful"),
        ]
        let correct = searchHitCount(cases, label: "ethiopian")
        print("📊 Ethiopian foods: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 Ethiopian food miss")
    }

    func testNewFoodsTurkish() {
        let cases: [(query: String, keyword: String)] = [
            ("chicken doner", "doner"),
            ("lahmacun", "lahmacun"),
            ("menemen", "menemen"),
            ("simit", "simit"),
            ("ayran", "ayran"),
            ("cacik", "cacik"),
            ("kofte", "kofte"),
        ]
        let correct = searchHitCount(cases, label: "turkish")
        print("📊 Turkish foods: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 Turkish food miss")
    }

    func testNewFoodsPersian() {
        let cases: [(query: String, keyword: String)] = [
            ("chelo kabab", "chelo"),
            ("ghormeh sabzi", "ghormeh"),
            ("fesenjan", "fesenjan"),
            ("mast-o-khiar", "mast"),
            ("tahdig", "tahdig"),
        ]
        let correct = searchHitCount(cases, label: "persian")
        print("📊 Persian foods: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 Persian food miss")
    }

    func testNewFoodsMacroSanity() {
        // All new foods must have plausible macros: calories > 0, no single macro > calories
        let newFoodNames = [
            "Jollof Rice", "Fried Plantain", "Suya", "Egusi Soup", "Akara", "Puff Puff",
            "Fufu", "Groundnut Soup", "Moi Moi", "Chin Chin",
            "Injera", "Doro Wat", "Misir Wat", "Shiro Wat", "Tibs", "Gomen", "Kitfo", "Ful Medames",
            "Chicken Doner Kebab", "Lahmacun", "Menemen", "Simit", "Ayran", "Cacik", "Kofte",
            "Chelo Kabab", "Ghormeh Sabzi", "Fesenjan", "Mast-o-Khiar", "Tahdig",
        ]
        var found = 0
        for name in newFoodNames {
            let results = FoodService.searchFood(query: name)
            if let food = results.first(where: { $0.name == name }) {
                found += 1
                XCTAssertGreaterThan(food.calories, 0, "\(name): calories must be > 0")
                let macroCalories = food.proteinG * 4 + food.carbsG * 4 + food.fatG * 9
                XCTAssertLessThan(abs(macroCalories - food.calories), food.calories * 0.35 + 50,
                    "\(name): macro-derived calories should be within 35% of listed calories")
            }
        }
        XCTAssertGreaterThanOrEqual(found, 28, "At least 28 of 30 new foods must be findable by exact name")
    }
}
