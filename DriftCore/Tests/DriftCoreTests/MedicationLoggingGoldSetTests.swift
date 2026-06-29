import XCTest
@testable import DriftCore

/// Tier-0 gold set for medication logging — deterministic, no LLM, no network, <5s.
/// Covers: ToolRanker log_medication routing, JSON parse for dose/unit params,
/// false-positive prevention (food/supplement queries must not route here).
///
/// Run: cd DriftCore && swift test --filter MedicationLoggingGoldSetTests
final class MedicationLoggingGoldSetTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            if ToolRegistry.shared.allTools().isEmpty {
                ToolRegistration.registerAll()
            }
        }
    }

    // MARK: - ToolRanker: log_medication routing

    @MainActor func testToolRanker_GLP1Variants() {
        let cases = [
            "took my ozempic",
            "log ozempic 0.5mg",
            "injected semaglutide",
            "took my glp1 shot",
            "log glp-1",
            "took wegovy",
            "injected mounjaro",
            "took tirzepatide 5mg",
        ]
        var correct = 0
        for query in cases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .food)
            if tools.first?.name == "log_medication" { correct += 1 }
            else { print("MISS (GLP-1): '\(query)' → \(tools.first?.name ?? "nil")") }
        }
        print("📊 GLP-1 routing: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count - 1, "At most 1 GLP-1 routing miss")
    }

    @MainActor func testToolRanker_OralMedications() {
        let cases = [
            "took metformin 500mg",
            "log my metformin",
            "took my morning meds metformin",
            "log medication semaglutide",
            "took insulin 10 units",
        ]
        var correct = 0
        for query in cases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .food)
            if tools.first?.name == "log_medication" { correct += 1 }
            else { print("MISS (oral med): '\(query)' → \(tools.first?.name ?? "nil")") }
        }
        print("📊 Oral medication routing: \(correct)/\(cases.count)")
        XCTAssertEqual(correct, cases.count, "All oral medication phrasings must route to log_medication")
    }

    // MARK: - JSON parameter parsing

    func testParseResponse_MedicationWithDoseAndUnit() {
        let json = #"{"tool":"log_medication","name":"ozempic","dose":0.5,"unit":"mg","confidence":"high"}"#
        let intent = IntentClassifier.parseResponse(json)
        XCTAssertEqual(intent?.tool, "log_medication")
        XCTAssertEqual(intent?.params["name"], "ozempic")
        XCTAssertEqual(intent?.params["dose"], "0.5")
        XCTAssertEqual(intent?.params["unit"], "mg")
    }

    func testParseResponse_MetforminWholeDose() {
        let json = #"{"tool":"log_medication","name":"metformin","dose":500,"unit":"mg","confidence":"high"}"#
        let intent = IntentClassifier.parseResponse(json)
        XCTAssertEqual(intent?.tool, "log_medication")
        XCTAssertEqual(intent?.params["name"], "metformin")
        XCTAssertEqual(intent?.params["dose"], "500")
    }

    func testParseResponse_NoDose_NameOnly() {
        let json = #"{"tool":"log_medication","name":"ozempic","confidence":"medium"}"#
        let intent = IntentClassifier.parseResponse(json)
        XCTAssertEqual(intent?.tool, "log_medication")
        XCTAssertEqual(intent?.params["name"], "ozempic")
        XCTAssertNil(intent?.params["dose"], "Absent dose key must not be fabricated")
    }

    func testParseResponse_InsulinUnits() {
        let json = #"{"tool":"log_medication","name":"insulin","dose":10,"unit":"units","confidence":"high"}"#
        let intent = IntentClassifier.parseResponse(json)
        XCTAssertEqual(intent?.tool, "log_medication")
        XCTAssertEqual(intent?.params["unit"], "units")
    }

    func testParseResponse_Semaglutide_Mcg() {
        let json = #"{"tool":"log_medication","name":"semaglutide","dose":500,"unit":"mcg","confidence":"high"}"#
        let intent = IntentClassifier.parseResponse(json)
        XCTAssertEqual(intent?.params["unit"], "mcg")
    }

    // MARK: - False-positive prevention

    @MainActor func testFoodQueriesDoNotRouteTo_log_medication() {
        let nonMedQueries = [
            "log 2 eggs",
            "ate chicken breast",
            "had biryani for lunch",
            "log protein shake",
        ]
        for query in nonMedQueries {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .food)
            XCTAssertNotEqual(tools.first?.name, "log_medication",
                "Food query '\(query)' must not route to log_medication")
        }
    }

    @MainActor func testSupplementQueriesDoNotRouteTo_log_medication() {
        let suppQueries = [
            "took creatine",
            "took vitamin d",
            "had fish oil",
        ]
        for query in suppQueries {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .supplements)
            XCTAssertNotEqual(tools.first?.name, "log_medication",
                "Supplement query '\(query)' must not route to log_medication")
        }
    }

    /// Bare "meds" with no drug name is ambiguous and must stay mark_supplement —
    /// only "meds" + a recognized drug name escalates to log_medication. Guards the
    /// ("meds", 3.5) trigger from over-firing on drug-name-less phrasings. #193
    @MainActor func testBareMedsWithoutDrugNameStaysSupplement() {
        let tools = ToolRanker.rank(query: "took my meds", screen: .food)
        XCTAssertNotEqual(tools.first?.name, "log_medication",
            "Bare 'took my meds' (no drug name) must not route to log_medication")
    }

    // MARK: - IntentThresholds: medication proceeds at any confidence with complete params

    func testMedication_LowConfidence_CompleteParams_Proceeds() {
        let decision = IntentThresholds.shouldClarify(
            tool: "log_medication", confidence: "low", hasCompleteParams: true)
        XCTAssertEqual(decision, .proceed,
            "log_medication with name known must proceed even at low confidence")
    }

    func testMedication_LowConfidence_IncompleteParams_Clarifies() {
        let decision = IntentThresholds.shouldClarify(
            tool: "log_medication", confidence: "low", hasCompleteParams: false)
        XCTAssertEqual(decision, .clarify,
            "log_medication without name at low confidence should clarify")
    }

    // MARK: - Summary

    @MainActor func testMedicationLoggingGoldSetSummary() {
        let allCases = [
            ("took my ozempic", "log_medication"),
            ("log ozempic 0.5mg", "log_medication"),
            ("injected semaglutide", "log_medication"),
            ("took my glp1 shot", "log_medication"),
            ("log glp-1", "log_medication"),
            ("took metformin 500mg", "log_medication"),
            ("log medication semaglutide", "log_medication"),
            ("took insulin 10 units", "log_medication"),
        ]
        var correct = 0
        for (query, expectedTool) in allCases {
            let tools = ToolRanker.rank(query: query.lowercased(), screen: .food)
            if tools.first?.name == expectedTool { correct += 1 }
            else { print("MISS: '\(query)' → \(tools.first?.name ?? "nil")") }
        }
        let pct = Int(Double(correct) / Double(allCases.count) * 100)
        print("📊 Medication gold set: \(correct)/\(allCases.count) (\(pct)%)")
        XCTAssertGreaterThanOrEqual(correct, allCases.count - 1,
            "Medication gold set must have ≤1 routing miss")
    }
}
