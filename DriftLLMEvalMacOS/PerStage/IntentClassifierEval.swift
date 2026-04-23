import XCTest
import Foundation

/// Per-stage LLM eval: IntentClassifier in isolation.
/// Tests the Gemma model on pre-normalized, clean inputs — removes normalization noise
/// so regressions here mean the classifier stage degraded, not the normalizer.
/// Requires Gemma model at ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf
final class IntentClassifierEval: XCTestCase {

    override class func setUp() {
        super.setUp()
        PerStageEvalSupport.loadModel()
    }

    // MARK: - Food logging (log_food)

    func testClassifier_foodLogging() async {
        let cases: [(String, String)] = [
            ("log 2 eggs",                   "log_food"),
            ("had biryani for lunch",        "log_food"),
            ("ate oatmeal this morning",     "log_food"),
            ("had a protein shake",          "log_food"),
            ("drank a glass of milk",        "log_food"),
            // #277: bare "log <food>" — root cause of #271 'log pizza' misroute
            ("log pizza",                    "log_food"),
            ("log a sandwich",               "log_food"),
        ]
        await runCases(cases, stage: "food_logging")
    }

    // MARK: - Food info queries (food_info)

    func testClassifier_foodInfo() async {
        let cases: [(String, String)] = [
            ("calories left",                "food_info"),
            ("calories in samosa",           "food_info"),
            ("how am I doing today",         "food_info"),
            ("daily summary",                "food_info"),
            ("how much protein today",       "food_info"),
        ]
        await runCases(cases, stage: "food_info")
    }

    // MARK: - Weight (log_weight / weight_info)

    func testClassifier_weight() async {
        let cases: [(String, String)] = [
            ("I weigh 75 kg",                "log_weight"),
            ("my weight is 68 kg",           "log_weight"),
            ("what is my weight trend",      "weight_info"),
            ("am I on track for my goal",    "weight_info"),
        ]
        await runCases(cases, stage: "weight")
    }

    // MARK: - Exercise

    func testClassifier_exercise() async {
        let cases: [(String, String)] = [
            ("start push day",               "start_workout"),
            ("did yoga for 30 minutes",      "log_activity"),
            ("how much did I bench",         "exercise_info"),
        ]
        await runCases(cases, stage: "exercise")
    }

    // MARK: - Health domains

    func testClassifier_healthDomains() async {
        let cases: [(String, String)] = [
            ("how did I sleep",              "sleep_recovery"),
            ("my hrv today",                 "sleep_recovery"),
            ("any glucose spikes",           "glucose"),
            ("show my biomarkers",           "biomarkers"),
            ("what is my body fat",          "body_comp"),
        ]
        await runCases(cases, stage: "health_domains")
    }

    // MARK: - Supplements

    func testClassifier_supplements() async {
        let cases: [(String, String)] = [
            ("took vitamin d",               "mark_supplement"),
            ("had my fish oil today",        "mark_supplement"),
            ("did I take my vitamins",       "supplements"),
        ]
        await runCases(cases, stage: "supplements")
    }

    // MARK: - Goal, edit, delete, navigate

    func testClassifier_actions() async {
        let cases: [(String, String)] = [
            ("set my goal to 160 lbs",       "set_goal"),
            ("delete last entry",            "delete_food"),
            ("remove rice from lunch",       "edit_meal"),
            ("go to food tab",               "navigate_to"),
            ("open exercise tab",            "navigate_to"),
        ]
        await runCases(cases, stage: "actions")
    }

    // MARK: - Micronutrient & date queries (top telemetry failure categories — cycle 4949)

    func testClassifier_micronutrientQueries() async {
        let cases: [(String, String)] = [
            ("how much fiber did I eat today",   "food_info"),
            ("how much sodium today",            "food_info"),
            ("what's my sugar intake",           "food_info"),
            ("how much protein today",           "food_info"),
            ("did I get enough fiber this week", "food_info"),
        ]
        await runCases(cases, stage: "micronutrient_queries")
    }

    func testClassifier_historicalDateQueries() async {
        let cases: [(String, String)] = [
            ("how many calories did I eat last Tuesday", "food_info"),
            ("what did I log two days ago",              "food_info"),
            ("calories on Saturday",                     "food_info"),
            ("what did I eat last week Monday",          "food_info"),
        ]
        await runCases(cases, stage: "historical_date_queries")
    }

    func testClassifier_informalCorrections() async {
        // "instead" triggers recent-entries injection; model should route to edit_meal
        let cases: [(String, String)] = [
            ("No, I had salmon instead of chicken", "edit_meal"),
            ("actually it was 2 eggs not 3",        "edit_meal"),
        ]
        await runCases(cases, stage: "informal_corrections")
    }

    // MARK: - Summary

    func testPrintClassifierSummary() async {
        let cases: [(String, String)] = [
            ("log 2 eggs",             "log_food"),
            ("calories left",          "food_info"),
            ("how did I sleep",        "sleep_recovery"),
            ("took creatine",          "mark_supplement"),
            ("start push day",         "start_workout"),
            ("I weigh 75 kg",          "log_weight"),
            ("what is my weight trend","weight_info"),
            ("how much did I bench",   "exercise_info"),
        ]
        var passed = 0
        for (query, expected) in cases {
            let ok = await assertRoutesSingleStage(query, to: expected)
            if ok { passed += 1 }
        }
        let pct = Int(Double(passed) / Double(cases.count) * 100)
        print("📊 IntentClassifierEval: \(passed)/\(cases.count) (\(pct)%)")
        XCTAssertGreaterThanOrEqual(passed, cases.count * 9 / 10,
            "IntentClassifier stage below 90% — check prompt or model")
    }

    // MARK: - Helper

    private func runCases(_ cases: [(String, String)], stage: String) async {
        var passed = 0
        for (query, expected) in cases {
            let ok = await assertRoutesSingleStage(query, to: expected)
            if ok { passed += 1 }
        }
        print("📊 IntentClassifierEval/\(stage): \(passed)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(passed, cases.count * 9 / 10,
            "IntentClassifier/\(stage) below 90%")
    }
}
