import XCTest
@testable import Drift

/// Evaluates Qwen3-1.7B tool-calling vs Qwen2.5-1.5B baseline.
/// Lite: 3 queries (~30s). Deep: 40 queries (~10 min, needs DRIFT_DEEP_EVAL=1).
final class LLMQwen3Eval: XCTestCase {

    nonisolated(unsafe) static var backend: LlamaCppBackend?

    override class func setUp() {
        super.setUp()
        let path = URL(fileURLWithPath: "/tmp/qwen3-1.7b-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: path.path) else {
            print("⚠️ Qwen3-1.7B not found at /tmp/ — skipping")
            return
        }
        let b = LlamaCppBackend(modelPath: path)
        try? b.loadSync()
        backend = b
        print("✅ Qwen3-1.7B loaded for eval")
    }

    private func systemPrompt() -> String {
        """
        You help track food, weight, and workouts. \
        LOGGING (user ate/did something) → call log tool. \
        QUESTION (user asks about data) → call info tool. \
        CHAT (greeting, thanks) → respond naturally, no tool. \
        Never give health advice. Never invent numbers. \
        Examples: \
        "I had 2 eggs" → {"tool":"log_food","params":{"name":"eggs","amount":"2"}} \
        "calories left" → {"tool":"food_info","params":{}} \
        "how's my weight" → {"tool":"weight_info","params":{}} \
        "start chest workout" → {"tool":"start_workout","params":{"name":"chest"}} \
        "what should I train" → {"tool":"exercise_info","params":{}} \
        "how'd I sleep" → {"tool":"sleep_recovery","params":{}} \
        "thanks" → You're welcome! (no tool) \
        Tools:
        - log_food(name:string, amount:number) — User wants to LOG food they ate
        - food_info(query:string) — User asks ABOUT food: calories, protein, what to eat
        - log_weight(value:number, unit:string) — User wants to LOG body weight
        - weight_info() — User asks ABOUT weight: trend, goal, body fat
        - start_workout(name:string) — User wants to START a workout
        - exercise_info(exercise:string) — User asks ABOUT workouts: what to train, progress
        """
    }

    private func context() -> String {
        "Calories: 1200 eaten, 1800 target, 600 remaining\nMacros: 80P 150C 40F\nWeight: 165 lbs, -0.8/wk"
    }

    private func run(_ query: String, expected: String?) async -> (tool: String?, correct: Bool) {
        guard let backend = Self.backend else { return (nil, false) }
        let prompt = "Context about the user:\n\(context())\n\nUser: \(query)"
        let response = await backend.respond(to: prompt, systemPrompt: systemPrompt())
        let call = parseToolCallJSON(response)
        let correct = expected == nil ? call == nil : call?.tool == expected
        return (call?.tool, correct)
    }

    // MARK: - Lite (runs every time)

    func testLiteSanity() async throws {
        guard Self.backend != nil else { throw XCTSkip("Qwen3 not available") }
        let queries: [(String, String?, String)] = [
            ("I had 2 eggs", "log_food", "food log"),
            ("calories left?", "food_info", "food question"),
            ("how's my weight trend", "weight_info", "weight question"),
        ]
        var correct = 0
        for (query, expected, label) in queries {
            let r = await run(query, expected: expected)
            if r.correct { correct += 1 }
            else { print("❌ LITE \(label): '\(query)' → \(r.tool ?? "none")") }
        }
        print("📊 Qwen3 Lite: \(correct)/\(queries.count)")
        XCTAssertGreaterThanOrEqual(correct, 2, "Lite sanity: \(correct)/\(queries.count)")
    }

    private func skipUnlessDeepEval() throws {
        guard ProcessInfo.processInfo.environment["DRIFT_DEEP_EVAL"] != nil else {
            throw XCTSkip("Deep eval skipped — set DRIFT_DEEP_EVAL=1 to run")
        }
    }

    // MARK: - Food Logging [DEEP]

    func testQwen3FoodLogging() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Qwen3 not available") }
        let queries: [(String, String)] = [
            ("I had 2 eggs", "log_food"),
            ("log chicken breast", "log_food"),
            ("ate a banana for lunch", "log_food"),
            ("had dal and rice", "log_food"),
            ("log a protein shake", "log_food"),
            ("I just had a samosa", "log_food"),
            ("ate 3 rotis for dinner", "log_food"),
            ("log oatmeal for breakfast", "log_food"),
            ("had a bowl of soup", "log_food"),
            ("I drank a coffee", "log_food"),
        ]
        var correct = 0
        for (q, exp) in queries {
            let r = await run(q, expected: exp)
            if r.correct { correct += 1 } else { print("❌ Q3 FOOD LOG: '\(q)' → \(r.tool ?? "none")") }
        }
        print("📊 Qwen3 Food Logging: \(correct)/\(queries.count) (\(correct * 100 / queries.count)%)")
    }

    // MARK: - Food Questions (where Qwen2.5 scored 40%)

    func testQwen3FoodQuestions() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Qwen3 not available") }
        let queries: [(String, String)] = [
            ("calories left?", "food_info"),
            ("how much protein in banana", "food_info"),
            ("what should I eat for dinner", "food_info"),
            ("calories in a samosa", "food_info"),
            ("suggest something high protein", "food_info"),
            ("explain my calories", "food_info"),
            ("am I eating too much", "food_info"),
            ("what did I eat today", "food_info"),
            ("I'm hungry what should I have", "food_info"),
            ("is my diet balanced", "food_info"),
        ]
        var correct = 0
        for (q, exp) in queries {
            let r = await run(q, expected: exp)
            if r.correct { correct += 1 } else { print("❌ Q3 FOOD Q: '\(q)' → \(r.tool ?? "none")") }
        }
        print("📊 Qwen3 Food Questions: \(correct)/\(queries.count) (\(correct * 100 / queries.count)%)")
    }

    // MARK: - Weight (where Qwen2.5 scored 20%)

    func testQwen3Weight() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Qwen3 not available") }
        let queries: [(String, String)] = [
            ("I weigh 165 lbs", "log_weight"),
            ("my weight is 75 kg", "log_weight"),
            ("how's my weight trend", "weight_info"),
            ("am I on track to reach my goal", "weight_info"),
            ("am I losing weight", "weight_info"),
            ("scale says 170 today", "log_weight"),
            ("what's my goal progress", "weight_info"),
            ("weighed in at 80 kg", "log_weight"),
            ("how fast am I losing", "weight_info"),
            ("what's my body fat", "weight_info"),
        ]
        var correct = 0
        for (q, exp) in queries {
            let r = await run(q, expected: exp)
            if r.correct { correct += 1 } else { print("❌ Q3 WEIGHT: '\(q)' → \(r.tool ?? "none")") }
        }
        print("📊 Qwen3 Weight: \(correct)/\(queries.count) (\(correct * 100 / queries.count)%)")
    }

    // MARK: - Exercise (where Qwen2.5 scored 13%)

    func testQwen3Exercise() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Qwen3 not available") }
        let queries: [(String, String)] = [
            ("what should I train today", "exercise_info"),
            ("start push day", "start_workout"),
            ("start chest workout", "start_workout"),
            ("I want to do legs today", "start_workout"),
            ("build me a back workout", "start_workout"),
            ("what muscle haven't I trained", "exercise_info"),
            ("am I making progress on bench", "exercise_info"),
            ("start pull day", "start_workout"),
            ("I want to work out", "exercise_info"),
            ("is my bench press improving", "exercise_info"),
        ]
        var correct = 0
        for (q, exp) in queries {
            let r = await run(q, expected: exp)
            if r.correct { correct += 1 } else { print("❌ Q3 EXERCISE: '\(q)' → \(r.tool ?? "none")") }
        }
        print("📊 Qwen3 Exercise: \(correct)/\(queries.count) (\(correct * 100 / queries.count)%)")
    }

    func testQwen3Summary() {
        print("═══ Qwen3-1.7B vs Qwen2.5-1.5B Baseline ═══")
        print("Baseline: Food Log 100%, Food Q 40%, Weight 20%, Exercise 13%")
    }
}
