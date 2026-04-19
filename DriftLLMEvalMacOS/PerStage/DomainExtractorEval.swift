import XCTest
import Foundation

/// Per-stage LLM eval: domain extraction in isolation.
/// Checks coarse domain routing — did the model land in the right family?
/// Groups tools into domains so a wrong-but-close result (log_food vs food_info)
/// doesn't fail here; only true cross-domain errors (food instead of sleep) surface.
/// Requires Gemma model at ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf
final class DomainExtractorEval: XCTestCase {

    override class func setUp() {
        super.setUp()
        PerStageEvalSupport.loadModel()
    }

    // MARK: - Domain families

    private static let foodTools: Set<String>       = ["log_food", "food_info", "edit_meal", "delete_food"]
    private static let weightTools: Set<String>     = ["log_weight", "weight_info", "set_goal"]
    private static let exerciseTools: Set<String>   = ["start_workout", "log_activity", "exercise_info"]
    private static let sleepTools: Set<String>      = ["sleep_recovery"]
    private static let supplementTools: Set<String> = ["mark_supplement", "supplements"]
    private static let glucoseTools: Set<String>    = ["glucose"]
    private static let biomarkerTools: Set<String>  = ["biomarkers"]
    private static let bodyCompTools: Set<String>   = ["body_comp"]

    // MARK: - Food domain

    func testDomain_food() async {
        let queries = [
            "log 2 eggs",
            "how many calories today",
            "ate biryani for lunch",
            "remove rice from dinner",
            "delete last food",
        ]
        await runDomain(queries, family: Self.foodTools, name: "food")
    }

    // MARK: - Weight domain

    func testDomain_weight() async {
        let queries = [
            "I weigh 74 kg",
            "what is my weight trend",
            "set my goal to 160",
            "how close am I to my goal",
            "weight history this month",
        ]
        await runDomain(queries, family: Self.weightTools, name: "weight")
    }

    // MARK: - Exercise domain

    func testDomain_exercise() async {
        let queries = [
            "start push day",
            "did yoga for 30 min",
            "how much did I bench last week",
            "ran 5k this morning",
            "am I overtraining",
        ]
        await runDomain(queries, family: Self.exerciseTools, name: "exercise")
    }

    // MARK: - Sleep domain

    func testDomain_sleep() async {
        let queries = [
            "how did I sleep last night",
            "my hrv today",
            "how much deep sleep did I get",
            "sleep quality this week",
            "show my REM sleep",
        ]
        await runDomain(queries, family: Self.sleepTools, name: "sleep")
    }

    // MARK: - Supplements domain

    func testDomain_supplements() async {
        let queries = [
            "took vitamin d",
            "had my fish oil today",
            "did I take my creatine",
            "supplement status",
        ]
        await runDomain(queries, family: Self.supplementTools, name: "supplements")
    }

    // MARK: - Glucose domain

    func testDomain_glucose() async {
        let queries = [
            "any glucose spikes today",
            "how is my blood sugar",
            "fasting glucose this morning",
            "did I spike after lunch",
        ]
        await runDomain(queries, family: Self.glucoseTools, name: "glucose")
    }

    // MARK: - Cross-domain non-food regressions

    func testDomain_nonFoodRegressions() async {
        // These must NOT land in food domain
        let sleepQuery = "how did I sleep"
        let glucoseQuery = "any glucose spikes"
        let biomarkerQuery = "show my biomarkers"

        if let r1 = await PerStageEvalSupport.classify(sleepQuery),
           let t1 = PerStageEvalSupport.extractTool(r1) {
            XCTAssertFalse(Self.foodTools.contains(t1),
                "'\(sleepQuery)' landed in food domain (\(t1)) — cross-domain misroute")
        }
        if let r2 = await PerStageEvalSupport.classify(glucoseQuery),
           let t2 = PerStageEvalSupport.extractTool(r2) {
            XCTAssertFalse(Self.foodTools.contains(t2),
                "'\(glucoseQuery)' landed in food domain (\(t2))")
        }
        if let r3 = await PerStageEvalSupport.classify(biomarkerQuery),
           let t3 = PerStageEvalSupport.extractTool(r3) {
            XCTAssertFalse(Self.foodTools.contains(t3),
                "'\(biomarkerQuery)' landed in food domain (\(t3))")
        }
        print("📊 DomainExtractorEval/cross-domain-regression: 3/3 checked")
    }

    // MARK: - Summary

    func testPrintDomainSummary() async {
        typealias DomainCase = (query: String, family: Set<String>, label: String)
        let cases: [DomainCase] = [
            ("log 2 eggs",          Self.foodTools,       "food"),
            ("how many calories",   Self.foodTools,       "food"),
            ("I weigh 74 kg",       Self.weightTools,     "weight"),
            ("start push day",      Self.exerciseTools,   "exercise"),
            ("how did I sleep",     Self.sleepTools,      "sleep"),
            ("took vitamin d",      Self.supplementTools, "supplements"),
            ("any glucose spikes",  Self.glucoseTools,    "glucose"),
            ("show my biomarkers",  Self.biomarkerTools,  "biomarkers"),
            ("what is my body fat", Self.bodyCompTools,   "body_comp"),
        ]
        var passed = 0
        for c in cases {
            guard let resp = await PerStageEvalSupport.classify(c.query),
                  let tool = PerStageEvalSupport.extractTool(resp) else { continue }
            let ok = c.family.contains(tool)
            if ok { passed += 1 }
            print("\(ok ? "✅" : "❌") domain('\(c.query)') → \(tool) (family: \(c.label))")
        }
        let pct = Int(Double(passed) / Double(cases.count) * 100)
        print("📊 DomainExtractorEval: \(passed)/\(cases.count) (\(pct)%)")
        XCTAssertGreaterThanOrEqual(passed, cases.count * 9 / 10,
            "Domain extraction below 90% — cross-domain misroutes detected")
    }

    // MARK: - Helper

    private func runDomain(_ queries: [String], family: Set<String>, name: String) async {
        var passed = 0
        for query in queries {
            guard let resp = await PerStageEvalSupport.classify(query),
                  let tool = PerStageEvalSupport.extractTool(resp) else { continue }
            let ok = family.contains(tool)
            if ok { passed += 1 }
            else { print("❌ [DomainExtractorEval/\(name)] '\(query)' → \(tool)") }
        }
        print("📊 DomainExtractorEval/\(name): \(passed)/\(queries.count)")
        XCTAssertGreaterThanOrEqual(passed, queries.count * 9 / 10,
            "Domain/\(name) below 90%")
    }
}
