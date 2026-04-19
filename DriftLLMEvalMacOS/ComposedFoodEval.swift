import XCTest
import Foundation

/// LLM eval for composed-food queries — "coffee with milk", "oatmeal with honey".
/// Verifies the intent classifier routes additive food phrases to log_food
/// and that the response text reflects both food components.
///
/// Requires: ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf
/// Run:      xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' -only-testing:'DriftLLMEvalMacOS/ComposedFoodEval'
final class ComposedFoodEval: XCTestCase {

    nonisolated(unsafe) static var gemmaBackend: LlamaCppBackend?
    static let gemmaPath = URL.homeDirectory.appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")

    override class func setUp() {
        super.setUp()
        guard FileManager.default.fileExists(atPath: gemmaPath.path) else {
            fatalError("❌ Gemma 4 model not found at \(gemmaPath.path). Run: bash scripts/download-models.sh")
        }
        let b = LlamaCppBackend(modelPath: gemmaPath, threads: 6)
        try? b.loadSync()
        guard b.isLoaded else { fatalError("❌ Gemma 4 failed to load") }
        gemmaBackend = b
        print("✅ Gemma 4 ready for ComposedFoodEval")
    }

    // MARK: - Helpers

    private func classify(_ message: String) async -> String? {
        guard let backend = Self.gemmaBackend else { return nil }
        return await backend.respond(to: message, systemPrompt: IntentRoutingEval.systemPrompt)
    }

    private func extractTool(_ response: String) -> String? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              let data = String(response[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String else { return nil }
        return tool
    }

    private func extractFoodName(_ response: String) -> String? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              let data = String(response[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = json["name"] as? String else { return nil }
        return name.lowercased()
    }

    /// Assert query routes to log_food; optionally verify base food appears in tool name.
    private func assertLogsFood(_ query: String,
                                 baseMustContain: String? = nil,
                                 file: StaticString = #filePath,
                                 line: UInt = #line) async {
        guard let response = await classify(query) else {
            XCTFail("No response for '\(query)'", file: file, line: line); return
        }
        let tool = extractTool(response)
        XCTAssertEqual(tool, "log_food",
            "'\(query)' → '\(tool ?? "text")' (expected log_food)\nResponse: \(response)",
            file: file, line: line)
        if let base = baseMustContain {
            let name = extractFoodName(response) ?? response.lowercased()
            XCTAssertTrue(name.contains(base),
                "'\(query)' response name '\(name)' should contain '\(base)'\nResponse: \(response)",
                file: file, line: line)
        }
    }

    // MARK: - "with" connector (5 cases)

    func testCoffeeWithMilk_routesToLogFood() async {
        await assertLogsFood("log coffee with milk", baseMustContain: "coffee")
    }

    func testOatmealWithHoney_routesToLogFood() async {
        await assertLogsFood("had oatmeal with honey", baseMustContain: "oatmeal")
    }

    func testToastWithButter_routesToLogFood() async {
        await assertLogsFood("ate toast with butter", baseMustContain: "toast")
    }

    func testRiceWithDal_routesToLogFood() async {
        await assertLogsFood("log rice with dal", baseMustContain: "rice")
    }

    func testChickenWithVegetables_routesToLogFood() async {
        await assertLogsFood("had chicken with vegetables", baseMustContain: "chicken")
    }

    // MARK: - "plus" and "alongside" connectors (3 cases)

    func testProteinShakePlusBanana_routesToLogFood() async {
        await assertLogsFood("log protein shake plus banana", baseMustContain: "protein")
    }

    func testSandwichAlongsideSoup_routesToLogFood() async {
        await assertLogsFood("had sandwich alongside soup", baseMustContain: "sandwich")
    }

    func testSaladPlusDressing_routesToLogFood() async {
        await assertLogsFood("ate salad plus dressing", baseMustContain: "salad")
    }

    // MARK: - "served with" (2 cases)

    func testDalServedWithRoti_routesToLogFood() async {
        await assertLogsFood("had dal served with roti", baseMustContain: "dal")
    }

    func testChickenServedWithRice_routesToLogFood() async {
        await assertLogsFood("log chicken served with rice", baseMustContain: "chicken")
    }

    // MARK: - Quantified additives (2 cases)

    func testOatmealWith2TbspHoney_routesToLogFood() async {
        await assertLogsFood("log oatmeal with 2 tbsp honey", baseMustContain: "oatmeal")
    }

    func testCoffeeWith100mlMilk_routesToLogFood() async {
        await assertLogsFood("log coffee with 100ml milk", baseMustContain: "coffee")
    }

    // MARK: - Multi-additive (2 cases)

    func testOatmealWithMilkAndHoney_routesToLogFood() async {
        await assertLogsFood("log oatmeal with milk and honey", baseMustContain: "oatmeal")
    }

    func testRiceWithDalAndVegetables_routesToLogFood() async {
        await assertLogsFood("had rice with dal and vegetables", baseMustContain: "rice")
    }

    // MARK: - Should NOT misroute as food_info (1 case)

    func testWithModifier_notFoodInfo() async {
        guard let response = await classify("how many calories in oatmeal with honey") else {
            XCTFail("No response"); return
        }
        let tool = extractTool(response)
        XCTAssertNotEqual(tool, "log_food",
            "Calorie query should route to food_info, not log_food\nResponse: \(response)")
    }

    // MARK: - Score summary

    func testScoreSummary() async {
        let cases: [(String, String)] = [
            ("log coffee with milk", "coffee"),
            ("had oatmeal with honey", "oatmeal"),
            ("ate toast with butter", "toast"),
            ("log rice with dal", "rice"),
            ("had chicken with vegetables", "chicken"),
            ("log protein shake plus banana", "protein"),
            ("had sandwich alongside soup", "sandwich"),
            ("had dal served with roti", "dal"),
            ("log chicken served with rice", "chicken"),
            ("log oatmeal with 2 tbsp honey", "oatmeal"),
            ("log coffee with 100ml milk", "coffee"),
            ("log oatmeal with milk and honey", "oatmeal"),
            ("had rice with dal and vegetables", "rice"),
            ("ate salad plus dressing", "salad"),
        ]
        var passed = 0
        for (query, base) in cases {
            guard let response = await classify(query) else { continue }
            let tool = extractTool(response)
            let name = extractFoodName(response) ?? ""
            if tool == "log_food" && name.contains(base) { passed += 1 }
        }
        let score = Double(passed) / Double(cases.count) * 100
        print("📊 ComposedFoodEval: \(passed)/\(cases.count) = \(String(format: "%.0f", score))%")
        XCTAssertGreaterThanOrEqual(score, 80, "Composed food routing score \(String(format: "%.0f", score))% below 80% threshold")
    }
}
