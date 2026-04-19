import XCTest
import Foundation

/// Multi-turn LLM eval — asserts the classifier uses the injected Q/A history to
/// resolve references ("what about protein?"), continue meal flows, survive topic
/// switches, and accept corrections. Threads compressed turns via the same
/// "Chat:\n{history}\n\nUser: {msg}" layout that production uses.
///
/// Requires: ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf
/// Run:      xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' -only-testing:'DriftLLMEvalMacOS/MultiTurnContextEval'
final class MultiTurnContextEval: XCTestCase {

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

    /// Call the classifier the same way production does: system prompt +
    /// "Chat:\n{history}\n\nUser: {msg}" when history is present.
    private func classify(_ message: String, history: String) async -> String? {
        guard let backend = Self.gemmaBackend else { return nil }
        let userMsg = history.isEmpty
            ? message
            : "Chat:\n\(String(history.prefix(1600)))\n\nUser: \(message)"
        return await backend.respond(to: userMsg, systemPrompt: IntentRoutingEval.systemPrompt)
    }

    private func extractTool(_ response: String) -> String? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              let data = String(response[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String else { return nil }
        return tool
    }

    /// A single chain: prior Q/A context + current user message + expected tool.
    /// `expectedTool == nil` means the classifier should emit text (no tool call).
    struct Chain {
        let name: String
        let expectedTool: String?
        let history: String
        let user: String
    }

    private func run(_ chain: Chain, file: StaticString = #filePath, line: UInt = #line) async {
        guard let response = await classify(chain.user, history: chain.history) else {
            XCTFail("[\(chain.name)] no response", file: file, line: line); return
        }
        let tool = extractTool(response)
        if let expected = chain.expectedTool {
            XCTAssertEqual(tool, expected,
                "[\(chain.name)] user='\(chain.user)' expected \(expected) got \(tool ?? "text")\nHistory:\n\(chain.history)\nResponse: \(response)",
                file: file, line: line)
        } else {
            XCTAssertNil(tool,
                "[\(chain.name)] user='\(chain.user)' expected text (no tool) got \(tool ?? "text")\nResponse: \(response)",
                file: file, line: line)
        }
    }

    // MARK: - Reference Follow-ups (pronoun/topic inherited from history)

    func testReferenceFollowUps() async {
        let chains: [Chain] = [
            Chain(name: "what about protein", expectedTool: "food_info",
                  history: "Q: daily summary\nA: You've had 1800 calories, 90g protein today.",
                  user: "what about protein?"),
            Chain(name: "and last week", expectedTool: "sleep_recovery",
                  history: "Q: how'd I sleep last night\nA: 7.2 hours, 85 recovery.",
                  user: "and last week?"),
            Chain(name: "same for dinner", expectedTool: "log_food",
                  history: "Q: log 2 eggs for breakfast\nA: Logged 2 eggs for breakfast.",
                  user: "log the same for dinner"),
            Chain(name: "show me the chart", expectedTool: "navigate_to",
                  history: "Q: am I on track for my goal\nA: On track — lost 1.2 lbs this week.",
                  user: "show me the weight chart"),
            Chain(name: "more details", expectedTool: "biomarkers",
                  history: "Q: show my biomarkers\nA: Cholesterol high, Vitamin D low.",
                  user: "more details on cholesterol"),
        ]
        for c in chains { await run(c) }
    }

    // MARK: - Meal Continuation

    func testMealContinuation() async {
        let mealPrompt = "Q: log lunch\nA: What did you have for lunch?"
        let chains: [Chain] = [
            Chain(name: "rice and dal", expectedTool: "log_food", history: mealPrompt, user: "rice and dal"),
            Chain(name: "chicken biryani", expectedTool: "log_food", history: mealPrompt, user: "chicken biryani"),
            Chain(name: "also add toast", expectedTool: "log_food",
                  history: "Q: log 2 eggs for breakfast\nA: Logged 2 eggs.",
                  user: "also add toast"),
            Chain(name: "and some milk", expectedTool: "log_food",
                  history: "Q: had oatmeal\nA: Logged oatmeal.",
                  user: "and some milk"),
        ]
        for c in chains { await run(c) }
    }

    // MARK: - Topic Switch (history must NOT hijack the new intent)

    func testTopicSwitch() async {
        let chains: [Chain] = [
            Chain(name: "food→sleep", expectedTool: "sleep_recovery",
                  history: "Q: log 2 eggs\nA: Logged 2 eggs for breakfast.",
                  user: "how was my sleep last night"),
            Chain(name: "weight→glucose", expectedTool: "glucose",
                  history: "Q: I weigh 75 kg\nA: Logged weight.",
                  user: "any glucose spikes"),
            Chain(name: "sleep→food_info", expectedTool: "food_info",
                  history: "Q: how'd I sleep\nA: 7h, 85 recovery.",
                  user: "calories left today"),
            Chain(name: "supplements→exercise", expectedTool: "start_workout",
                  history: "Q: did I take creatine\nA: Yes, marked today.",
                  user: "start push day"),
            Chain(name: "biomarkers→body_comp", expectedTool: "body_comp",
                  history: "Q: show biomarkers\nA: All in range.",
                  user: "what's my body fat"),
        ]
        for c in chains { await run(c) }
    }

    // MARK: - Correction (user rejects last action, redirects)

    func testCorrections() async {
        let chains: [Chain] = [
            Chain(name: "not that food", expectedTool: "log_food",
                  history: "Q: log biryani\nA: Logged biryani for dinner.",
                  user: "no I meant paneer tikka"),
            Chain(name: "wrong weight unit", expectedTool: "log_weight",
                  history: "Q: I weigh 75 kg\nA: Logged 75 kg.",
                  user: "actually 75 lbs"),
            Chain(name: "remove last meal", expectedTool: "delete_food",
                  history: "Q: log 2 eggs\nA: Logged 2 eggs for breakfast.",
                  user: "delete that"),
        ]
        for c in chains { await run(c) }
    }

    // MARK: - Multi-Turn Ambiguity (bare verb after context still asks)

    func testBareVerbAfterContext_stillAsks() async {
        let chains: [Chain] = [
            Chain(name: "log alone after food", expectedTool: nil,
                  history: "Q: daily summary\nA: 1800 cal, 90g protein.",
                  user: "log"),
            Chain(name: "add alone after biomarkers", expectedTool: nil,
                  history: "Q: show my biomarkers\nA: Cholesterol high.",
                  user: "add"),
            Chain(name: "track alone", expectedTool: nil,
                  history: "Q: how'd I sleep\nA: 7h.",
                  user: "track"),
        ]
        for c in chains { await run(c) }
    }

    // MARK: - Summary

    /// Soft-scored overall accuracy across the multi-turn set. Intended to run
    /// manually when tuning the prompt — prints pass rate to the console.
    func testMultiTurnSummary() async {
        let allChains: [Chain] = [
            Chain(name: "what about protein", expectedTool: "food_info", history: "Q: daily summary\nA: 1800 cal.", user: "what about protein?"),
            Chain(name: "and last week (sleep)", expectedTool: "sleep_recovery", history: "Q: how'd I sleep\nA: 7h.", user: "and last week?"),
            Chain(name: "food→sleep switch", expectedTool: "sleep_recovery", history: "Q: log 2 eggs\nA: Logged.", user: "how was my sleep"),
            Chain(name: "meal continuation rice and dal", expectedTool: "log_food", history: "Q: log lunch\nA: What did you have for lunch?", user: "rice and dal"),
            Chain(name: "also add toast", expectedTool: "log_food", history: "Q: log 2 eggs\nA: Logged.", user: "also add toast"),
            Chain(name: "delete that", expectedTool: "delete_food", history: "Q: log biryani\nA: Logged.", user: "delete that"),
            Chain(name: "topic return to glucose", expectedTool: "glucose", history: "Q: how's my body fat\nA: 18%.", user: "any glucose spikes"),
            Chain(name: "bare verb after context", expectedTool: nil, history: "Q: daily summary\nA: 1800 cal.", user: "log"),
        ]
        var correct = 0
        print("\n📊 Multi-Turn Context Summary:")
        for c in allChains {
            guard let response = await classify(c.user, history: c.history) else {
                print("  ❌ [\(c.name)] no response"); continue
            }
            let tool = extractTool(response)
            let pass = tool == c.expectedTool
            if pass { correct += 1 }
            print("  \(pass ? "✅" : "❌") [\(c.name)] → \(tool ?? "text") (expected \(c.expectedTool ?? "text"))")
        }
        print("  Score: \(correct)/\(allChains.count)\n")
        // Soft floor: 6/8 — allows 2 miss-tolerance as the LLM is stochastic.
        XCTAssertGreaterThanOrEqual(correct, 6, "Multi-turn baseline: need ≥6/\(allChains.count)")
    }
}
