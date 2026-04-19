import XCTest
import Foundation

/// Measures "ask vs guess" calibration for the intent classifier.
/// When a query has no object to act on (bare verbs), the classifier should emit
/// text (a clarifying question) rather than a speculative tool call.
///
/// Requires: ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf
/// Run:      xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' -only-testing:'DriftLLMEvalMacOS/AmbiguityEval'
final class AmbiguityEval: XCTestCase {

    nonisolated(unsafe) static var gemmaBackend: LlamaCppBackend?
    static let gemmaPath = URL.homeDirectory.appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")

    override class func setUp() {
        super.setUp()
        guard FileManager.default.fileExists(atPath: gemmaPath.path) else {
            fatalError("❌ Gemma 4 model not found at \(gemmaPath.path). Run: bash scripts/download-models.sh")
        }
        let b = LlamaCppBackend(modelPath: gemmaPath, threads: 6)
        try? b.loadSync()
        if b.isLoaded { gemmaBackend = b } else { fatalError("❌ Gemma 4 failed to load") }
    }

    // MARK: - Helpers

    private func classify(_ message: String) async -> String? {
        guard let backend = Self.gemmaBackend else { return nil }
        return await backend.respond(to: message, systemPrompt: IntentRoutingEval.systemPrompt)
    }

    /// True when the response is a clarifying text (no JSON tool call).
    private func isClarifyText(_ response: String) -> Bool {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // If the response has a valid JSON tool call anywhere, it's a guess, not an ask.
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}"),
           let data = String(trimmed[start...end]).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           json["tool"] is String {
            return false
        }
        return true
    }

    private func assertAsks(_ query: String, file: StaticString = #filePath, line: UInt = #line) async {
        guard let response = await classify(query) else {
            XCTFail("No response for '\(query)'", file: file, line: line); return
        }
        XCTAssertTrue(isClarifyText(response),
            "'\(query)' should ask, not guess. Got: \(response)",
            file: file, line: line)
    }

    // MARK: - Bare Verbs (no object — must ask)

    /// Single-word verbs carry no payload; guessing a tool here is always wrong.
    func testBareVerbs_ask() async {
        await assertAsks("log")
        await assertAsks("track")
        await assertAsks("add")
        await assertAsks("note")
        await assertAsks("start")
    }

    // MARK: - Incomplete Questions (ambiguous scope — must ask)

    func testIncompleteQuestions_ask() async {
        await assertAsks("how much")
        await assertAsks("what about me")
        await assertAsks("tell me")
        await assertAsks("can you help")
        await assertAsks("what should I do")
    }

    // MARK: - Meal Prompts With No Food Named (must ask)

    /// Matches existing "log lunch" behavior — meal name but no food.
    func testMealWithoutFood_ask() async {
        await assertAsks("log lunch")
        await assertAsks("log dinner")
        await assertAsks("add to breakfast")
        await assertAsks("lunch time")
        await assertAsks("had something for dinner")
    }

    // MARK: - Regression: Concrete Queries Must NOT Ask

    /// Ask-vs-guess calibration must not hurt well-specified queries. If these regress,
    /// the classifier is over-asking — tune clarify examples down.
    func testConcreteQueries_doNotAsk() async {
        // These all have a specific object — must route, not ask.
        for query in ["log 2 eggs", "I had biryani", "I weigh 75 kg", "show my biomarkers", "took creatine"] {
            guard let response = await classify(query) else {
                XCTFail("No response for '\(query)'"); continue
            }
            XCTAssertFalse(isClarifyText(response),
                "'\(query)' is concrete — must route to a tool, not ask. Got: \(response)")
        }
    }
}
