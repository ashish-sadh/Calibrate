import XCTest
import DriftCore
import Foundation

/// Per-tool reliability eval — 10 queries for each of the top-5 tools, totaling 50 queries.
/// Each query asserts that Gemma selects the correct tool AND extracts the correct args.
///
/// Why per-tool: aggregate pass rate hides regressions in a single tool. Per-tool numbers
/// tell us exactly where the router is weak and which tool needs prompt tuning.
///
/// Gate: every tool must hit ≥80% after tuning.
///
/// Requires Gemma model at ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf.
/// Run: xcodebuild test -scheme DriftLLMEvalMacOS -only-testing:'DriftLLMEvalMacOS/PerToolReliabilityEval'
final class PerToolReliabilityEval: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try LLMEvalGate.requireLLM()  // report as skipped, never false-green
    }


    override class func setUp() {
        super.setUp()
        PerStageEvalSupport.loadModel()
    }

    /// Emit per-tool + overall summary once all methods in this class have run.
    override class func tearDown() {
        let s = scoreboard.snapshot()
        print("\n📊 PerToolReliabilityEval — overall: \(s.overallPassed)/\(s.overallTotal) (\(s.overallPct)%)")
        for (tool, score) in s.perTool.sorted(by: { $0.key < $1.key }) {
            print("   \(tool): \(score.passed)/\(score.total) (\(score.pct)%)")
        }
        super.tearDown()
    }

    // MARK: - Expectation

    /// A single gold-set case: input query + expected tool + expected param subset (all must match).
    struct Case {
        let query: String
        let expectedTool: String
        let expectedParams: [String: String]
    }

    // MARK: - Per-tool test methods
    //
    // Each method runs 10 queries in its own xctest process. We intentionally
    // do NOT run them all in one process: the ggml-metal backend accumulates
    // residency-set state across ~10 inferences and the next inference dies
    // silently. Run them one-per-invocation with scripts/per-tool-reliability.sh.

    func testReliability_logFood() async         { await runAndReport(logFoodCases,        tool: "log_food") }
    func testReliability_editMeal() async        { await runAndReport(editMealCases,       tool: "edit_meal") }
    func testReliability_logWeight() async       { await runAndReport(logWeightCases,      tool: "log_weight") }
    func testReliability_markSupplement() async  { await runAndReport(markSupplementCases, tool: "mark_supplement") }
    func testReliability_foodInfo() async        { await runAndReport(foodInfoCases,       tool: "food_info") }
    func testReliability_supplementInsight() async  { await runAndReport(supplementInsightCases,  tool: "supplement_insight") }
    func testReliability_foodTimingInsight() async  { await runAndReport(foodTimingInsightCases,  tool: "food_timing_insight") }

    // MARK: - Gold sets (10 cases per tool)

    private let logFoodCases: [Case] = [
        Case(query: "had biryani",                          expectedTool: "log_food", expectedParams: ["name": "biryani"]),
        Case(query: "ate 2 eggs this morning",              expectedTool: "log_food", expectedParams: ["name": "egg"]),
        Case(query: "just had a protein shake",             expectedTool: "log_food", expectedParams: ["name": "protein shake"]),
        Case(query: "grabbed a coffee",                     expectedTool: "log_food", expectedParams: ["name": "coffee"]),
        Case(query: "drank a glass of milk",                expectedTool: "log_food", expectedParams: ["name": "milk"]),
        Case(query: "log 100g of rice",                     expectedTool: "log_food", expectedParams: ["name": "rice"]),
        Case(query: "ate oatmeal for breakfast",            expectedTool: "log_food", expectedParams: ["name": "oatmeal"]),
        Case(query: "finished my chicken breast",           expectedTool: "log_food", expectedParams: ["name": "chicken breast"]),
        Case(query: "chipotle bowl 800 cal 40p 90c 20f",    expectedTool: "log_food", expectedParams: ["name": "chipotle bowl", "calories": "800"]),
        Case(query: "I had 2 to 3 banans",                  expectedTool: "log_food", expectedParams: ["name": "banana"]),
    ]

    private let editMealCases: [Case] = [
        Case(query: "remove rice from lunch",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "lunch", "action": "remove", "target_food": "rice"]),
        Case(query: "delete pasta from dinner",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "dinner", "action": "remove", "target_food": "pasta"]),
        Case(query: "update oatmeal in breakfast to 200g",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "breakfast", "action": "update_quantity", "target_food": "oatmeal", "new_value": "200g"]),
        Case(query: "change my lunch rice to 150g",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "lunch", "target_food": "rice", "new_value": "150g"]),
        Case(query: "replace rice with quinoa in lunch",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "lunch", "action": "replace", "target_food": "rice", "new_value": "quinoa"]),
        Case(query: "swap beef for lentils in lunch",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "lunch", "action": "replace", "target_food": "beef", "new_value": "lentils"]),
        Case(query: "take out the salad from dinner",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "dinner", "action": "remove", "target_food": "salad"]),
        Case(query: "update lunch pasta to 250g",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "lunch", "target_food": "pasta", "new_value": "250g"]),
        Case(query: "remove chicken from breakfast",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "breakfast", "action": "remove", "target_food": "chicken"]),
        Case(query: "change breakfast yogurt to 300g",
             expectedTool: "edit_meal",
             expectedParams: ["meal_period": "breakfast", "target_food": "yogurt", "new_value": "300g"]),
    ]

    private let logWeightCases: [Case] = [
        Case(query: "I weigh 75 kg",                 expectedTool: "log_weight", expectedParams: ["value": "75", "unit": "kg"]),
        Case(query: "just weighed in at 80 kg",      expectedTool: "log_weight", expectedParams: ["value": "80", "unit": "kg"]),
        Case(query: "my weight is 68 kg",            expectedTool: "log_weight", expectedParams: ["value": "68", "unit": "kg"]),
        Case(query: "I am 162 pounds",               expectedTool: "log_weight", expectedParams: ["value": "162"]),
        Case(query: "weighed 72.5 today",            expectedTool: "log_weight", expectedParams: ["value": "72.5"]),
        Case(query: "scale says 165 lbs",            expectedTool: "log_weight", expectedParams: ["value": "165"]),
        Case(query: "I'm 82 kilos this morning",     expectedTool: "log_weight", expectedParams: ["value": "82"]),
        Case(query: "log weight 70",                 expectedTool: "log_weight", expectedParams: ["value": "70"]),
        Case(query: "weighed in at 155",             expectedTool: "log_weight", expectedParams: ["value": "155"]),
        Case(query: "my current weight is 76 kg",    expectedTool: "log_weight", expectedParams: ["value": "76", "unit": "kg"]),
    ]

    // mark_supplement is the current runtime tool; add_supplement is only for adding to the tracked list.
    private let markSupplementCases: [Case] = [
        Case(query: "took vitamin d",              expectedTool: "mark_supplement", expectedParams: ["name": "vitamin d"]),
        Case(query: "had my fish oil today",       expectedTool: "mark_supplement", expectedParams: ["name": "fish oil"]),
        Case(query: "took creatine",               expectedTool: "mark_supplement", expectedParams: ["name": "creatine"]),
        Case(query: "took magnesium before bed",   expectedTool: "mark_supplement", expectedParams: ["name": "magnesium"]),
        Case(query: "just had my omega 3",         expectedTool: "mark_supplement", expectedParams: ["name": "omega 3"]),
        Case(query: "took my multivitamin",        expectedTool: "mark_supplement", expectedParams: ["name": "multivitamin"]),
        Case(query: "had zinc this morning",       expectedTool: "mark_supplement", expectedParams: ["name": "zinc"]),
        Case(query: "took vitamin c",              expectedTool: "mark_supplement", expectedParams: ["name": "vitamin c"]),
        Case(query: "took my b12 today",           expectedTool: "mark_supplement", expectedParams: ["name": "b12"]),
        Case(query: "had ashwagandha",             expectedTool: "mark_supplement", expectedParams: ["name": "ashwagandha"]),
    ]

    // food_info is the runtime tool for any "query nutrition / status" intent.
    private let foodInfoCases: [Case] = [
        Case(query: "calories left",            expectedTool: "food_info", expectedParams: ["query": "calories left"]),
        Case(query: "calories in samosa",       expectedTool: "food_info", expectedParams: ["query": "calories in samosa"]),
        Case(query: "how much protein today",   expectedTool: "food_info", expectedParams: [:]),
        Case(query: "daily summary",            expectedTool: "food_info", expectedParams: ["query": "daily summary"]),
        Case(query: "weekly summary",           expectedTool: "food_info", expectedParams: ["query": "weekly summary"]),
        Case(query: "how am I doing",           expectedTool: "food_info", expectedParams: [:]),
        Case(query: "carb intake today",        expectedTool: "food_info", expectedParams: [:]),
        Case(query: "fat intake this week",     expectedTool: "food_info", expectedParams: [:]),
        Case(query: "calories in paneer tikka", expectedTool: "food_info", expectedParams: [:]),
        Case(query: "what about protein?",      expectedTool: "food_info", expectedParams: [:]),
    ]

    private let supplementInsightCases: [Case] = [
        Case(query: "how are my supplements affecting my recovery", expectedTool: "supplement_insight", expectedParams: [:]),
        Case(query: "how consistent am I with creatine",            expectedTool: "supplement_insight", expectedParams: ["supplement": "creatine"]),
        Case(query: "what's my vitamin D streak",                   expectedTool: "supplement_insight", expectedParams: ["supplement": "vitamin D"]),
        Case(query: "did I miss any omega-3 this week",             expectedTool: "supplement_insight", expectedParams: [:]),
        Case(query: "show my supplement adherence",                 expectedTool: "supplement_insight", expectedParams: [:]),
        Case(query: "how often do I take magnesium",                expectedTool: "supplement_insight", expectedParams: ["supplement": "magnesium"]),
        Case(query: "my supplement consistency last month",         expectedTool: "supplement_insight", expectedParams: [:]),
        Case(query: "which supplements am I missing most",          expectedTool: "supplement_insight", expectedParams: [:]),
        Case(query: "creatine adherence past 30 days",              expectedTool: "supplement_insight", expectedParams: ["supplement": "creatine"]),
        Case(query: "have I been taking my supplements regularly",  expectedTool: "supplement_insight", expectedParams: [:]),
    ]

    private let foodTimingInsightCases: [Case] = [
        Case(query: "when do I usually eat",            expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "do I eat late at night",           expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "what's my eating window",          expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "what time is my first meal",       expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "does eating late affect my sleep", expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "analyze my meal timing",           expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "am I eating too late",             expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "how consistent is my meal schedule", expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "when do I have my biggest meal",   expectedTool: "food_timing_insight", expectedParams: [:]),
        Case(query: "what's my average dinner time",    expectedTool: "food_timing_insight", expectedParams: [:]),
    ]

    // MARK: - Scoring

    private nonisolated(unsafe) static var scoreboard = Scoreboard()

    private final class Scoreboard: @unchecked Sendable {
        private var perTool: [String: (passed: Int, total: Int)] = [:]
        private let queue = DispatchQueue(label: "per-tool-scoreboard")

        func record(tool: String, passed: Bool) {
            queue.sync {
                var current = perTool[tool] ?? (0, 0)
                current.total += 1
                if passed { current.passed += 1 }
                perTool[tool] = current
            }
        }

        func snapshot() -> Snapshot {
            queue.sync {
                let overallPassed = perTool.values.reduce(0) { $0 + $1.passed }
                let overallTotal = perTool.values.reduce(0) { $0 + $1.total }
                return Snapshot(
                    perTool: perTool.mapValues { ToolScore(passed: $0.passed, total: $0.total) },
                    overallPassed: overallPassed,
                    overallTotal: overallTotal
                )
            }
        }

        struct Snapshot {
            let perTool: [String: ToolScore]
            let overallPassed: Int
            let overallTotal: Int
            var overallPct: Int {
                overallTotal == 0 ? 0 : Int(Double(overallPassed) / Double(overallTotal) * 100)
            }
        }
        struct ToolScore {
            let passed: Int
            let total: Int
            var pct: Int { total == 0 ? 0 : Int(Double(passed) / Double(total) * 100) }
        }
    }

    // MARK: - Runner

    private func runAndReport(_ cases: [Case], tool: String) async {
        var passed = 0
        var failures: [String] = []
        for c in cases {
            guard let response = await PerStageEvalSupport.classify(c.query),
                  let data = jsonData(from: response) else {
                failures.append("'\(c.query)' → no parseable JSON")
                Self.scoreboard.record(tool: tool, passed: false)
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let actualTool = json["tool"] as? String else {
                failures.append("'\(c.query)' → no tool field")
                Self.scoreboard.record(tool: tool, passed: false)
                continue
            }
            let toolOK = actualTool == c.expectedTool
            let paramsOK = c.expectedParams.allSatisfy { key, expected in
                guard let actual = json[key] else { return false }
                return String(describing: actual).lowercased().contains(expected.lowercased())
            }
            let ok = toolOK && paramsOK
            Self.scoreboard.record(tool: tool, passed: ok)
            if ok {
                passed += 1
            } else {
                let actualDesc = json.map { "\($0)=\($1)" }.joined(separator: ", ")
                failures.append("'\(c.query)' → \(actualDesc) (wanted \(c.expectedTool) \(c.expectedParams))")
            }
        }
        let pct = Int(Double(passed) / Double(cases.count) * 100)
        print("📊 PerToolReliabilityEval/\(tool): \(passed)/\(cases.count) (\(pct)%)")
        for f in failures { print("   ❌ \(f)") }
        XCTAssertGreaterThanOrEqual(
            passed, Int(ceil(Double(cases.count) * 0.8)),
            "\(tool) below 80% (\(passed)/\(cases.count))"
        )
    }

    private func jsonData(from response: String) -> Data? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}") else { return nil }
        return String(response[start...end]).data(using: .utf8)
    }
}
