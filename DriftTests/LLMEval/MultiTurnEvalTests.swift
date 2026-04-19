import XCTest
@testable import Drift

/// Multi-turn regression suite: 5 conversation chains × 5 turns each = 25 sequential cases.
/// Each scenario feeds turns to the model sequentially with accumulated history, verifying
/// tool routing is consistent as context builds.
///
/// Requires Gemma 4 model. Run:
///   pkill -9 -f xcodebuild; sleep 2
///   xcodebuild test -project Drift.xcodeproj -scheme Drift \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///     -only-testing:'DriftLLMEvalTests/MultiTurnEvalTests' 2>&1 | grep -E "📊|❌|✔"
@MainActor
final class MultiTurnEvalTests: XCTestCase {

    nonisolated(unsafe) static var backend: LlamaCppBackend?

    override class func setUp() {
        super.setUp()
        let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? "/tmp"
        let path = URL(fileURLWithPath: homeDir)
            .appendingPathComponent("drift-state/models/gemma-4-e2b-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: path.path) else {
            print("⚠️ Gemma 4 not found — skipping multi-turn eval")
            return
        }
        let b = LlamaCppBackend(modelPath: path, threads: 4)
        try? b.loadSync()
        if b.isLoaded { backend = b; print("✅ Gemma 4 loaded for multi-turn eval") }
        else { print("⚠️ Gemma 4 failed to load") }
    }

    // MARK: - System Prompt

    private func systemPrompt() -> String {
        """
        You help track food, weight, and workouts. \
        LOGGING (user ate/did something) → call log tool. \
        QUESTION (user asks about data) → call info tool. \
        CHAT (greeting, thanks, done) → respond naturally, no tool. \
        Never give health advice. Never invent numbers. \
        History is provided as context — use it to resolve pronouns. \
        Tools:
        - log_food(name:string, amount:number) — user wants to LOG food
        - food_info(query:string) — user asks ABOUT food/calories/macros
        - log_weight(value:number, unit:string) — user wants to LOG weight
        - weight_info() — user asks ABOUT weight/trend/goal
        - start_workout(name:string) — user wants to START a workout
        - exercise_info(exercise:string) — user asks ABOUT workouts/what to train
        - sleep_recovery() — user asks about sleep/HRV/recovery
        - supplements() — user asks about supplement status
        """
    }

    private func userContext() -> String {
        "User data: 1400 cal eaten, 2000 target, 600 remaining. Weight 175 lbs. Last workout: Push Day yesterday."
    }

    // MARK: - Runner

    struct Turn {
        let query: String
        let expectedTool: String? // nil = text/chat response
    }

    @MainActor
    private func runScenario(_ name: String, turns: [Turn], minCorrect: Int = 4) async {
        guard let backend = Self.backend else { return }
        var history = ""
        var correct = 0

        for (i, turn) in turns.enumerated() {
            let historySection = history.isEmpty ? "" : "Conversation so far:\n\(history)\n\n"
            let prompt = "\(userContext())\n\n\(historySection)User: \(turn.query)"
            let response = await backend.respond(to: prompt, systemPrompt: systemPrompt())
            let call = parseToolCallJSON(response)

            let passed: Bool
            if let expected = turn.expectedTool {
                passed = call?.tool == expected
            } else {
                passed = call == nil
            }

            if passed {
                correct += 1
            } else {
                let got = call?.tool ?? "text"
                let want = turn.expectedTool ?? "text"
                print("❌ [\(name)] T\(i + 1) '\(turn.query)' → \(got) (want \(want))")
            }

            // Accumulate history for next turn
            let assistantText = call.map { "[\($0.tool)]" } ?? String(response.prefix(80))
            history += "User: \(turn.query)\nAssistant: \(assistantText)\n"
        }

        print("📊 [\(name)]: \(correct)/\(turns.count)")
        XCTAssertGreaterThanOrEqual(correct, minCorrect,
            "[\(name)] multi-turn accuracy: \(correct)/\(turns.count) (need \(minCorrect))")
    }

    // MARK: - Scenario A: Food logging chain

    func testScenarioA_FoodChain() async throws {
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        await runScenario("A:food-chain", turns: [
            Turn(query: "I had chicken and rice for lunch",    expectedTool: "log_food"),
            Turn(query: "how much protein was that?",         expectedTool: "food_info"),
            Turn(query: "calories left today?",               expectedTool: "food_info"),
            Turn(query: "suggest something for dinner",       expectedTool: "food_info"),
            Turn(query: "log it",                             expectedTool: "log_food"),
        ])
    }

    // MARK: - Scenario B: Nutrition lookup then log

    func testScenarioB_NutritionThenLog() async throws {
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        await runScenario("B:nutrition-log", turns: [
            Turn(query: "what's in an avocado?",              expectedTool: "food_info"),
            Turn(query: "log half an avocado",                expectedTool: "log_food"),
            Turn(query: "how are my macros so far?",          expectedTool: "food_info"),
            Turn(query: "what should I eat to hit protein?",  expectedTool: "food_info"),
            Turn(query: "log 200g chicken breast",            expectedTool: "log_food"),
        ])
    }

    // MARK: - Scenario C: Weight tracking chain

    func testScenarioC_WeightChain() async throws {
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        await runScenario("C:weight-chain", turns: [
            Turn(query: "I weigh 174 lbs today",              expectedTool: "log_weight"),
            Turn(query: "how's my weight trend?",             expectedTool: "weight_info"),
            Turn(query: "am I losing weight?",                expectedTool: "weight_info"),
            Turn(query: "what's my goal?",                    expectedTool: "weight_info"),
            Turn(query: "how long to hit 165?",               expectedTool: "weight_info"),
        ])
    }

    // MARK: - Scenario D: Sleep and recovery chain

    func testScenarioD_SleepChain() async throws {
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        await runScenario("D:sleep-chain", turns: [
            Turn(query: "how did I sleep last night?",        expectedTool: "sleep_recovery"),
            Turn(query: "what's my HRV?",                     expectedTool: "sleep_recovery"),
            Turn(query: "am I recovered enough to train?",    expectedTool: "sleep_recovery"),
            Turn(query: "what workout should I do?",          expectedTool: "exercise_info"),
            Turn(query: "start that workout",                 expectedTool: "start_workout"),
        ])
    }

    // MARK: - Scenario E: Supplements chain

    func testScenarioE_SupplementsChain() async throws {
        guard Self.backend != nil else { throw XCTSkip("Gemma 4 not available") }
        await runScenario("E:supplements-chain", turns: [
            Turn(query: "did I take all my supplements?",     expectedTool: "supplements"),
            Turn(query: "what do I still need to take?",      expectedTool: "supplements"),
            Turn(query: "mark creatine as taken",             expectedTool: "supplements"),
            Turn(query: "what's left now?",                   expectedTool: "supplements"),
            Turn(query: "thanks",                             expectedTool: nil),
        ])
    }
}
