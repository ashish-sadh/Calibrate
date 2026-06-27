import XCTest
@testable import DriftCore

/// Deterministic ToolRanker routing tests (no LLM, ~30 cases, <100ms).
/// Focus: implicit food logging (no "log" keyword) and nutrition-query negatives.
/// All cases must pass at 100% — failures indicate a ToolRanker regression.
///
/// LLM-backed intent routing (~300 cases, 5min) lives in
/// `DriftLLMEvalMacOS/IntentRoutingEval.swift` — that file calls real Gemma 4
/// to validate prompt + model behavior, not the deterministic ranker.
final class IntentRoutingEvalTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            if ToolRegistry.shared.allTools().isEmpty { ToolRegistration.registerAll() }
        }
    }

    // MARK: - Implicit food logging (positive cases)

    @MainActor
    func testImplicitFoodLogging_commonPhrases() {
        let cases: [(String, String)] = [
            ("had a banana",                        "log_food"),
            ("ate oatmeal this morning",            "log_food"),
            ("finished my chicken breast",          "log_food"),
            ("just had coffee",                     "log_food"),
            ("grabbed a protein bar",               "log_food"),
            ("drank a glass of milk",               "log_food"),
            ("had some almonds",                    "log_food"),
            ("just finished a bowl of dal",         "log_food"),
            ("morning chai",                        "log_food"),
            ("protein shake post workout",          "log_food"),
        ]
        runPositiveCases(cases)
    }

    @MainActor
    func testImplicitFoodLogging_indianFoods() {
        let cases: [(String, String)] = [
            ("rice and dal for dinner",             "log_food"),
            ("two rotis with sabzi",                "log_food"),
            ("had idli for breakfast",              "log_food"),
            ("ate paneer tikka",                    "log_food"),
            ("chapati and rajma",                   "log_food"),
            ("had biryani for lunch",               "log_food"),
            ("drank lassi",                         "log_food"),
        ]
        runPositiveCases(cases)
    }

    @MainActor
    func testImplicitFoodLogging_quantities() {
        let cases: [(String, String)] = [
            ("200g paneer",                         "log_food"),
            ("3 eggs for breakfast",                "log_food"),
            ("handful of cashews",                  "log_food"),
            ("bowl of yogurt",                      "log_food"),
            ("ate some mixed nuts",                 "log_food"),
            ("apple and peanut butter",             "log_food"),
        ]
        runPositiveCases(cases)
    }

    // MARK: - Nutrition queries (negative cases — must NOT route to log_food)

    @MainActor
    func testNutritionQueryNegatives() {
        let cases: [(String, String)] = [
            ("how many calories in a banana",       "food_info"),
            ("is rice healthy",                     "food_info"),
            ("what should I eat for dinner",        "food_info"),
            ("protein in chicken breast",           "food_info"),
            ("how much fat in almonds",             "food_info"),
            ("macros in an egg",                    "food_info"),
        ]
        for (query, expected) in cases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .food)
            XCTAssertEqual(tools.first?.name, expected,
                "'\(query)' → want \(expected), got \(tools.first?.name ?? "nil")")
        }
    }

    // MARK: - Cardio activity routing (P0 #896)

    /// run/jog/cycle/swim phrasings must route to `log_activity`, not `log_food`.
    /// Regression: "log a 30 minute run" used to open a food search because the
    /// `log_activity` triggers only had inflected forms ("running"/"cycling") and
    /// lost to `log_food`'s "log" trigger. Cases run on `.food` (the hardest screen
    /// for log_activity), so passing here means it wins on every screen.
    @MainActor
    func testCardioActivityRouting() {
        let cases: [(String, String)] = [
            ("log a 30 minute run",          "log_activity"),
            ("went for a 5k run",            "log_activity"),
            ("i ran for 20 minutes",         "log_activity"),
            ("did a 30 min cycle",           "log_activity"),
            ("log a 20 minute jog",          "log_activity"),
            ("went jogging this morning",    "log_activity"),
            ("did a 1 mile swim",            "log_activity"),
            ("log 45 minutes of cycling",    "log_activity"),
            // Regression: real food logs must stay food.
            ("log 2 rotis",                  "log_food"),
            ("2 eggs and toast",             "log_food"),
        ]
        runPositiveCases(cases)
    }

    // MARK: - Water logging routing (#901)

    /// English water phrasings must route to `log_water`, not `log_food`.
    /// Regression: "log 500ml water" opened a food search for "water" (volume
    /// dropped) because `log_water` had NO ToolRanker profile and was never
    /// scored — log_food's "log"/"drank" triggers won. Hinglish "paani piya"
    /// already worked via the agent; it is now deterministic too. Same class as
    /// #896. Cases run on `.food` (the hardest screen for log_water, where
    /// log_food gets a screen boost), so passing here means it wins everywhere.
    @MainActor
    func testWaterLoggingRouting() {
        let cases: [(String, String)] = [
            ("log 500ml water",          "log_water"),
            ("log 250ml water",          "log_water"),
            ("i drank a glass of water", "log_water"),
            ("had 2 glasses of water",   "log_water"),
            ("drank 750ml of water",     "log_water"),
            // Hinglish path stays correct (Indian-first).
            ("paani piya 1 liter",       "log_water"),
            // Regression: compound beverages carry calories → stay food.
            ("had coconut water",        "log_food"),
            ("drank a glass of milk",    "log_food"),
            // Regression: plain food logs unaffected.
            ("log 2 rotis",              "log_food"),
            ("2 eggs and toast",         "log_food"),
        ]
        runPositiveCases(cases)
    }

    /// Volume must be parsed into amount+unit and never dropped (#901 Done-When 2).
    /// Asserts the round-trip through `extractParamsForTool` + `HydrationService.parseMl`.
    @MainActor
    func testWaterVolumeExtraction() {
        guard let tool = ToolRegistry.shared.tool(named: "log_water") else {
            return XCTFail("log_water tool not registered")
        }
        let cases: [(query: String, ml: Double)] = [
            ("log 500ml water",          500),
            ("log 250ml water",          250),
            ("i drank a glass of water", 250),   // 1 glass = 250ml
            ("had 2 glasses of water",   500),   // 2 × 250ml
            ("paani piya 1 liter",       1000),  // 1 L = 1000ml
        ]
        for c in cases {
            let params = ToolRanker.extractParamsForTool(tool, from: c.query)
            guard let amount = Double(params["amount"] ?? "") else {
                XCTFail("'\(c.query)' → no amount extracted (params: \(params))")
                continue
            }
            let unit = params["unit"] ?? "ml"
            guard let ml = HydrationService.parseMl(amount: amount, unit: unit) else {
                XCTFail("'\(c.query)' → parseMl returned nil (amount=\(amount), unit=\(unit))")
                continue
            }
            XCTAssertEqual(ml, c.ml, accuracy: 0.01,
                "'\(c.query)' → want \(c.ml)ml, got \(ml) (amount=\(amount), unit=\(unit))")
        }
    }

    /// Named regression for the exact #901 bug: English volume-unit water
    /// ("log 500ml water") must route to `log_water` (not `log_food`) AND keep
    /// the volume. One self-contained test asserting both halves — routing +
    /// volume preservation — so the headline failure can't silently come back.
    @MainActor
    func testEnglishVolumeWater_RoutesToLogWater() {
        guard let tool = ToolRegistry.shared.tool(named: "log_water") else {
            return XCTFail("log_water tool not registered")
        }
        let cases: [(query: String, ml: Double)] = [
            ("log 500ml water",       500),
            ("log 250ml water",       250),
            ("drank 750ml of water",  750),
        ]
        for c in cases {
            // Half 1: routes to log_water, not log_food.
            let top = ToolRanker.rank(query: c.query, screen: .food).first?.name
            XCTAssertEqual(top, "log_water",
                "'\(c.query)' → want log_water, got \(top ?? "nil")")
            // Half 2: the volume survives (not dropped into a "water" food search).
            let params = ToolRanker.extractParamsForTool(tool, from: c.query)
            guard let amount = Double(params["amount"] ?? ""),
                  let ml = HydrationService.parseMl(amount: amount, unit: params["unit"] ?? "ml") else {
                XCTFail("'\(c.query)' → volume dropped (params: \(params))")
                continue
            }
            XCTAssertEqual(ml, c.ml, accuracy: 0.01,
                "'\(c.query)' → want \(c.ml)ml, got \(ml) (params: \(params))")
        }
    }

    // MARK: - Helper

    @MainActor
    private func runPositiveCases(_ cases: [(String, String)]) {
        for (query, expected) in cases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .food)
            XCTAssertEqual(tools.first?.name, expected,
                "'\(query)' → want \(expected), got \(tools.first?.name ?? "nil")")
        }
    }
}
