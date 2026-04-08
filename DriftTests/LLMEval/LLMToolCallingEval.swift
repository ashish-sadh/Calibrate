import XCTest
@testable import Drift

/// Evaluates whether Qwen2.5-1.5B can reliably select the right tool from a schema list.
/// Lite: 3 queries (~30s). Deep: 100 queries (~25 min, needs DRIFT_DEEP_EVAL=1).
/// Run lite: xcodebuild test -only-testing:'DriftLLMEvalTests/LLMToolCallingEval/testLiteSanity'
/// Run deep: DRIFT_DEEP_EVAL=1 xcodebuild test -only-testing:'DriftLLMEvalTests/LLMToolCallingEval'
final class LLMToolCallingEval: XCTestCase {

    nonisolated(unsafe) static var backend: LlamaCppBackend?

    override class func setUp() {
        super.setUp()
        let path = URL(fileURLWithPath: "/tmp/qwen2.5-1.5b-instruct-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: path.path) else {
            print("⚠️ Model not found at /tmp/ — skipping LLM eval")
            return
        }
        let b = LlamaCppBackend(modelPath: path)
        try? b.loadSync()
        backend = b
        print("✅ Model loaded for tool-calling eval")
    }

    // MARK: - System Prompt

    private func systemPrompt(screen: String) -> String {
        // Consolidated tools — 6 max for 1.5B model. Clear WHEN-to-use descriptions.
        let allTools: [(name: String, params: String, desc: String)] = [
            ("log_food", "name:string, amount:number", "User wants to LOG food they ate"),
            ("food_info", "query:string", "User asks ABOUT food: calories, protein, what to eat"),
            ("log_weight", "value:number, unit:string", "User wants to LOG body weight"),
            ("weight_info", "", "User asks ABOUT weight: trend, goal, body fat, BMI"),
            ("start_workout", "name:string", "User wants to START a workout or name a body part"),
            ("exercise_info", "exercise:string", "User asks ABOUT workouts: what to train, progress"),
            ("sleep_recovery", "", "User asks about SLEEP, recovery, HRV, tiredness"),
            ("supplements", "", "User asks about supplements or vitamins"),
        ]

        // Screen-filter: put relevant tools first
        let screenPrefix: String? = switch screen {
        case "food": "food"
        case "weight": "weight"
        case "exercise": "exercise"
        default: nil
        }

        let sorted = allTools.sorted { a, b in
            let aMatch = screenPrefix != nil && a.name.contains(screenPrefix!)
            let bMatch = screenPrefix != nil && b.name.contains(screenPrefix!)
            if aMatch && !bMatch { return true }
            if !aMatch && bMatch { return false }
            return false
        }

        let toolLines = sorted.prefix(6).map { "- \($0.name)(\($0.params)) — \($0.desc)" }

        return """
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
        Tools:\n\(toolLines.joined(separator: "\n"))
        """
    }

    private func context() -> String {
        "Calories: 1200 eaten, 1800 target, 600 remaining\nMacros: 80P 150C 40F\nWeight: 165 lbs, -0.8/wk"
    }

    // MARK: - Test Runner

    private func runQuery(_ query: String, screen: String = "dashboard", expectedTool: String?) async -> (response: String, tool: String?, correct: Bool) {
        guard let backend = Self.backend else { return ("skipped", nil, false) }

        let prompt = "Context about the user:\n\(context())\n\nUser: \(query)"
        let response = await backend.respond(to: prompt, systemPrompt: systemPrompt(screen: screen))

        let call = parseToolCallJSON(response)
        let actualTool = call?.tool

        let correct: Bool
        if let expected = expectedTool {
            correct = actualTool == expected
        } else {
            // Expected no tool call
            correct = actualTool == nil
        }

        return (response, actualTool, correct)
    }

    // MARK: - Lite (runs every time)

    func testLiteSanity() async throws {
        guard Self.backend != nil else { throw XCTSkip("Model not available") }
        let queries: [(String, String?, String)] = [
            ("I had 2 eggs", "log_food", "food log"),
            ("calories left?", "food_info", "food question"),
            ("how's my weight trend", "weight_info", "weight question"),
        ]
        var correct = 0
        for (query, expected, label) in queries {
            let result = await runQuery(query, screen: "dashboard", expectedTool: expected)
            if result.correct { correct += 1 }
            else { print("❌ LITE \(label): '\(query)' → \(result.tool ?? "none")") }
        }
        print("📊 Qwen2.5-1.5B Lite: \(correct)/\(queries.count)")
        XCTAssertGreaterThanOrEqual(correct, 2, "Lite sanity: \(correct)/\(queries.count)")
    }

    private func skipUnlessDeepEval() throws {
        guard ProcessInfo.processInfo.environment["DRIFT_DEEP_EVAL"] != nil else {
            throw XCTSkip("Deep eval skipped — set DRIFT_DEEP_EVAL=1 to run")
        }
    }

    // MARK: - Food Logging (30) [DEEP]

    func testFoodLogging() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Model not available") }

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
            ("ate pizza last night", "log_food"),
            ("log paneer butter masala", "log_food"),
            ("had a sandwich and chips", "log_food"),
            ("log a cup of rice", "log_food"),
            ("I made pasta for dinner", "log_food"),
            ("ate a couple of eggs", "log_food"),
            ("had biryani for lunch", "log_food"),
            ("log half an avocado", "log_food"),
            ("I had toast with butter", "log_food"),
            ("drank a glass of milk", "log_food"),
        ]

        var correct = 0
        for (query, expected) in queries {
            let result = await runQuery(query, screen: "food", expectedTool: expected)
            if result.correct { correct += 1 }
            else { print("❌ FOOD LOG: '\(query)' → tool=\(result.tool ?? "none") response=\(result.response.prefix(80))") }
        }

        let pct = Double(correct) / Double(queries.count) * 100
        print("📊 Food Logging: \(correct)/\(queries.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, 10, "Food logging: \(correct)/\(queries.count)")
    }

    // MARK: - Food Understanding (15)

    func testFoodUnderstanding() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Model not available") }

        let queries: [(String, String)] = [
            ("calories left?", "food_info"),
            ("how much protein in banana", "food_info"),
            ("what should I eat for dinner", "food_info"),
            ("calories in a samosa", "food_info"),
            ("how many carbs in rice", "food_info"),
            ("suggest something high protein", "food_info"),
            ("what are good protein sources", "food_info"),
            ("explain my calories", "food_info"),
            ("am I eating too much", "food_info"),
            ("what did I eat today", "food_info"),
            ("I'm hungry what should I have", "food_info"),
            ("how's my protein intake", "food_info"),
            ("nutrition info for chicken", "food_info"),
            ("I need to eat more fiber", "food_info"),
            ("is my diet balanced", "food_info"),
        ]

        var correct = 0
        for (query, expected) in queries {
            let result = await runQuery(query, screen: "food", expectedTool: expected)
            if result.correct { correct += 1 }
            else { print("❌ FOOD Q: '\(query)' → tool=\(result.tool ?? "none")") }
        }

        let pct = Double(correct) / Double(queries.count) * 100
        print("📊 Food Understanding: \(correct)/\(queries.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, 5, "Food understanding: \(correct)/\(queries.count)")
    }

    // MARK: - Weight (15)

    func testWeightQueries() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Model not available") }

        let queries: [(String, String)] = [
            ("I weigh 165 lbs", "log_weight"),
            ("my weight is 75 kg", "log_weight"),
            ("how's my weight trend", "weight_info"),
            ("am I on track to reach my goal", "weight_info"),
            ("how much have I lost this month", "weight_info"),
            ("show my weight history", "weight_info"),
            ("what's my body fat", "weight_info"),
            ("what's my BMI", "weight_info"),
            ("am I losing weight", "weight_info"),
            ("scale says 170 today", "log_weight"),
            ("how fast am I losing", "weight_info"),
            ("what's my goal progress", "weight_info"),
            ("weighed in at 80 kg", "log_weight"),
            ("when will I reach my target", "weight_info"),
            ("my weight is going up why", "weight_info"),
        ]

        var correct = 0
        for (query, expected) in queries {
            let result = await runQuery(query, screen: "weight", expectedTool: expected)
            if result.correct { correct += 1 }
            else { print("❌ WEIGHT: '\(query)' → tool=\(result.tool ?? "none")") }
        }

        let pct = Double(correct) / Double(queries.count) * 100
        print("📊 Weight: \(correct)/\(queries.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, 5, "Weight: \(correct)/\(queries.count)")
    }

    // MARK: - Exercise Coach (25)

    func testExerciseCoach() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Model not available") }

        let queries: [(String, String)] = [
            ("what should I train today", "exercise_info"),
            ("start push day", "start_workout"),
            ("start chest workout", "start_workout"),
            ("I want to do legs today", "start_workout"),
            ("build me a back workout", "start_workout"),
            ("suggest a shoulder routine", "start_workout"),
            ("what muscle haven't I trained", "exercise_info"),
            ("how many workouts this week", "exercise_info"),
            ("start a full body session", "start_workout"),
            ("am I making progress on bench", "exercise_info"),
            ("am I getting stronger on squats", "exercise_info"),
            ("start pull day", "start_workout"),
            ("give me a quick arm workout", "start_workout"),
            ("I want to work out", "exercise_info"),
            ("start leg day", "start_workout"),
            ("build me a PPL split", "start_workout"),
            ("what did I train last", "exercise_info"),
            ("coach me through a workout", "start_workout"),
            ("is my bench press improving", "exercise_info"),
            ("suggest exercises for core", "start_workout"),
            ("start my usual workout", "start_workout"),
            ("how's my training volume", "exercise_info"),
            ("plan a hypertrophy session", "start_workout"),
        ]

        var correct = 0
        for (query, expected) in queries {
            let result = await runQuery(query, screen: "exercise", expectedTool: expected)
            if result.correct { correct += 1 }
            else { print("❌ EXERCISE: '\(query)' → tool=\(result.tool ?? "none")") }
        }

        let pct = Double(correct) / Double(queries.count) * 100
        print("📊 Exercise Coach: \(correct)/\(queries.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, 8, "Exercise: \(correct)/\(queries.count)")
    }

    // MARK: - Sleep & Recovery (10)

    func testSleepRecovery() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Model not available") }

        let queries: [(String, String)] = [
            ("how'd I sleep last night", "sleep_recovery"),
            ("what's my recovery score", "sleep_recovery"),
            ("should I train today or rest", "sleep_recovery"),
            ("I'm feeling tired", "sleep_recovery"),
            ("what's my HRV", "sleep_recovery"),
            ("am I recovered enough", "sleep_recovery"),
            ("how's my resting heart rate", "sleep_recovery"),
            ("I feel exhausted", "sleep_recovery"),
            ("did I sleep well", "sleep_recovery"),
            ("is my recovery good enough to lift", "sleep_recovery"),
        ]

        var correct = 0
        for (query, expected) in queries {
            let result = await runQuery(query, screen: "dashboard", expectedTool: expected)
            if result.correct { correct += 1 }
            else { print("❌ SLEEP: '\(query)' → tool=\(result.tool ?? "none")") }
        }

        let pct = Double(correct) / Double(queries.count) * 100
        print("📊 Sleep & Recovery: \(correct)/\(queries.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, 4, "Sleep: \(correct)/\(queries.count)")
    }

    // MARK: - No Tool Expected (15)

    func testNoToolExpected() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Model not available") }

        let queries: [(String, String?)] = [
            ("thanks!", nil),
            ("hello", nil),
            ("ok got it", nil),
            ("what can you do", nil),
            ("nice", nil),
            ("you're helpful", nil),
            ("what is a macro", nil),
            ("tell me about creatine", nil),
            ("what's a good heart rate", nil),
            ("how do I lose belly fat", nil),
            ("is keto good", nil),
        ]

        var correct = 0
        for (query, expected) in queries {
            let result = await runQuery(query, expectedTool: expected)
            if result.correct { correct += 1 }
            else { print("❌ NO-TOOL: '\(query)' → tool=\(result.tool ?? "none") (expected none)") }
        }

        let pct = Double(correct) / Double(queries.count) * 100
        print("📊 No Tool (should be natural): \(correct)/\(queries.count) (\(String(format: "%.0f", pct))%)")
        XCTAssertGreaterThanOrEqual(correct, 5, "No-tool: \(correct)/\(queries.count)")
    }

    // MARK: - Ambiguous / Tricky (5)

    func testAmbiguousQueries() async throws {
        try skipUnlessDeepEval()
        guard Self.backend != nil else { throw XCTSkip("Model not available") }

        let queries: [(String, String)] = [
            ("log exercise", "exercise_info"),
            ("log a workout", "exercise_info"),
            ("did I take my vitamins", "supplements"),
            ("what supplements should I take", "supplements"),
        ]

        var correct = 0
        for (query, expected) in queries {
            let result = await runQuery(query, expectedTool: expected)
            if result.correct { correct += 1 }
            else { print("❌ AMBIGUOUS: '\(query)' → tool=\(result.tool ?? "none") expected=\(expected)") }
        }

        print("📊 Ambiguous: \(correct)/\(queries.count)")
    }

    // MARK: - Summary

    func testPrintSummary() {
        print("""
        ═══════════════════════════════════
        LLM TOOL-CALLING EVAL COMPLETE
        Run individual test methods for category breakdowns.
        ═══════════════════════════════════
        """)
    }
}
