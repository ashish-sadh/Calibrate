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
