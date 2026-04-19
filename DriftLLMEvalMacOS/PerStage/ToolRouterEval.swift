import XCTest
import Foundation

/// Per-stage LLM eval: tool-level disambiguation in isolation.
/// Tests the hardest same-domain splits: log_food vs food_info,
/// mark_supplement vs supplements, log_weight vs weight_info.
/// A regression here means the router is confusing sibling tools —
/// the domain is right but the exact call is wrong.
/// Requires Gemma model at ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf
final class ToolRouterEval: XCTestCase {

    override class func setUp() {
        super.setUp()
        PerStageEvalSupport.loadModel()
    }

    // MARK: - log_food vs food_info

    func testRouter_logFoodVsFoodInfo_logSide() async {
        // User ate/had something → must be log_food
        let cases: [(String, String)] = [
            ("had biryani for lunch",             "log_food"),
            ("ate oatmeal this morning",          "log_food"),
            ("log 2 eggs",                        "log_food"),
            ("just had a protein shake",          "log_food"),
            ("grabbed a coffee",                  "log_food"),
            ("drank a glass of milk",             "log_food"),
            ("finished my chicken breast",        "log_food"),
        ]
        await runCases(cases, name: "log_food_side")
    }

    func testRouter_logFoodVsFoodInfo_infoSide() async {
        // Query about nutrition / status → must be food_info
        let cases: [(String, String)] = [
            ("calories left",                     "food_info"),
            ("calories in samosa",                "food_info"),
            ("how much protein today",            "food_info"),
            ("daily summary",                     "food_info"),
            ("how am I doing",                    "food_info"),
            ("what is my carb intake",            "food_info"),
        ]
        await runCases(cases, name: "food_info_side")
    }

    // MARK: - mark_supplement vs supplements

    func testRouter_markVsStatus_markSide() async {
        // User took/had a supplement → mark_supplement
        let cases: [(String, String)] = [
            ("took vitamin d",                    "mark_supplement"),
            ("had my fish oil today",             "mark_supplement"),
            ("took creatine",                     "mark_supplement"),
            ("took magnesium before bed",         "mark_supplement"),
            ("just had my omega 3",               "mark_supplement"),
        ]
        await runCases(cases, name: "mark_supplement_side")
    }

    func testRouter_markVsStatus_statusSide() async {
        // User asking about supplement history → supplements()
        let cases: [(String, String)] = [
            ("did I take my vitamins",            "supplements"),
            ("supplement status",                 "supplements"),
            ("what vitamins am I missing",        "supplements"),
            ("have I taken anything today",       "supplements"),
        ]
        await runCases(cases, name: "supplements_status_side")
    }

    // MARK: - log_weight vs weight_info

    func testRouter_logWeightVsWeightInfo_logSide() async {
        // User reporting their weight → log_weight
        let cases: [(String, String)] = [
            ("I weigh 75 kg",                     "log_weight"),
            ("my weight is 68 kg",                "log_weight"),
            ("just weighed in at 80 kg",          "log_weight"),
            ("I am 162 pounds",                   "log_weight"),
        ]
        await runCases(cases, name: "log_weight_side")
    }

    func testRouter_logWeightVsWeightInfo_infoSide() async {
        // User asking about weight data → weight_info
        let cases: [(String, String)] = [
            ("what is my weight trend",           "weight_info"),
            ("am I on track for my goal",         "weight_info"),
            ("how much have I lost this week",    "weight_info"),
            ("weight history this month",         "weight_info"),
        ]
        await runCases(cases, name: "weight_info_side")
    }

    // MARK: - Protein shake: food not supplement (regression)

    func testRouter_proteinShakeIsFood() async {
        let cases: [(String, String)] = [
            ("had a protein shake",               "log_food"),
            ("drank a whey shake after lifting",  "log_food"),
            ("finished my post-workout shake",    "log_food"),
        ]
        for (query, expected) in cases {
            guard let resp = await PerStageEvalSupport.classify(query),
                  let tool = PerStageEvalSupport.extractTool(resp) else { continue }
            XCTAssertEqual(tool, expected,
                "'\(query)' → '\(tool)' (must be log_food not mark_supplement)")
            XCTAssertNotEqual(tool, "mark_supplement",
                "protein shake misrouted to mark_supplement")
        }
        print("📊 ToolRouterEval/protein_shake_regression: \(cases.count) cases checked")
    }

    // MARK: - Summary

    func testPrintRouterSummary() async {
        let cases: [(String, String)] = [
            ("log 2 eggs",                        "log_food"),
            ("calories left",                     "food_info"),
            ("took vitamin d",                    "mark_supplement"),
            ("did I take my vitamins",            "supplements"),
            ("I weigh 75 kg",                     "log_weight"),
            ("what is my weight trend",           "weight_info"),
            ("had a protein shake",               "log_food"),
            ("how much protein today",            "food_info"),
        ]
        var passed = 0
        for (query, expected) in cases {
            let ok = await assertRoutesSingleStage(query, to: expected)
            if ok { passed += 1 }
        }
        let pct = Int(Double(passed) / Double(cases.count) * 100)
        print("📊 ToolRouterEval: \(passed)/\(cases.count) (\(pct)%)")
        XCTAssertGreaterThanOrEqual(passed, cases.count * 9 / 10,
            "ToolRouter disambiguation below 90%")
    }

    // MARK: - Helper

    private func runCases(_ cases: [(String, String)], name: String) async {
        var passed = 0
        for (query, expected) in cases {
            let ok = await assertRoutesSingleStage(query, to: expected)
            if ok { passed += 1 }
        }
        print("📊 ToolRouterEval/\(name): \(passed)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(passed, cases.count * 9 / 10,
            "ToolRouter/\(name) below 90%")
    }
}
