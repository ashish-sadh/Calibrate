import XCTest
@testable import Drift

/// Tests the LLM-dependent parts of the unified pipeline:
/// Lite: normalization (Gemma rewrites messy → clean) + tool-call JSON generation
/// Deep: ambiguous queries, multi-turn, full AIToolAgent.run() end-to-end
///
/// Lite runs every time (~1-2 min). Deep needs DRIFT_DEEP_EVAL=1.
final class PipelineLLMEval: XCTestCase {

    // MARK: - Model Loading

    nonisolated(unsafe) static var gemmaBackend: LlamaCppBackend?
    nonisolated(unsafe) static var smolBackend: LlamaCppBackend?

    override class func setUp() {
        super.setUp()
        // Load Gemma for normalization + tool-call tests
        let gemmaPath = URL(fileURLWithPath: "/tmp/gemma-4-e2b-q4_k_m.gguf")
        if FileManager.default.fileExists(atPath: gemmaPath.path) {
            let b = LlamaCppBackend(modelPath: gemmaPath, threads: 4)
            try? b.loadSync()
            if b.isLoaded { gemmaBackend = b; print("✅ Gemma 4 loaded for pipeline eval") }
        }
        // Load SmolLM for tool-call tests
        let smolPath = URL(fileURLWithPath: "/tmp/smollm2-360m-instruct-q8_0.gguf")
        if FileManager.default.fileExists(atPath: smolPath.path) {
            let b = LlamaCppBackend(modelPath: smolPath, threads: 4)
            try? b.loadSync()
            if b.isLoaded { smolBackend = b; print("✅ SmolLM loaded for pipeline eval") }
        }
    }

    // MARK: - Normalization Prompt

    private func normalizePrompt() -> String {
        """
        Rewrite into a clear, short command. Fix spelling. Convert word numbers to digits. Resolve pronouns from chat context.
        If already clear, return as-is. Keep the user's intent.
        "I had 2 to 3 banans" → log 3 banana
        "how'd I sleep" → how is my sleep
        "took creatine and fish oil" → took creatine and fish oil
        "set my goal to one sixty" → set goal to 160 lbs
        "I did yoga for like half an hour" → i did yoga 30 min
        "what about protein?" → how is my protein
        "bannana" → banana
        """
    }

    // MARK: - Lite: Normalization (Gemma Only)

    func testLiteNormalization() async throws {
        guard let backend = Self.gemmaBackend else { throw XCTSkip("Gemma not available") }

        let cases: [(messy: String, shouldContain: String)] = [
            ("I had like 2 bannanas", "banana"),
            ("how'd I sleep last nite", "sleep"),
            ("set my goal to one sixty", "160"),
            ("I did yoga for like half an hour", "30"),
            ("wat should I eat", "eat"),
            ("took my creatine n fish oil", "creatine"),
        ]

        let sysPrompt = normalizePrompt()
        var correct = 0
        for (messy, expected) in cases {
            let response = await backend.respond(to: messy, systemPrompt: sysPrompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "").lowercased()
            if cleaned.contains(expected.lowercased()) {
                correct += 1
            } else {
                print("  ❌ NORMALIZE: '\(messy)' → '\(cleaned)' (expected to contain '\(expected)')")
            }
        }
        print("📊 Gemma Normalization: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, cases.count / 2, "Normalization: \(correct)/\(cases.count)")
    }

    // MARK: - Lite: Normalize → Rule Pick → Correct Tool

    @MainActor
    func testLiteNormalizeToRulePick() async throws {
        guard let backend = Self.gemmaBackend else { throw XCTSkip("Gemma not available") }

        let cases: [(messy: String, expectedTool: String, screen: AIScreen)] = [
            ("I just ate like 2 bannanas", "log_food", .food),
            ("how'd I sleep", "sleep_recovery", .bodyRhythm),
            ("took my creatine", "mark_supplement", .supplements),
        ]

        let sysPrompt = normalizePrompt()
        var correct = 0
        for (messy, expectedTool, screen) in cases {
            // Normalize
            let response = await backend.respond(to: messy, systemPrompt: sysPrompt)
            let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")

            // Try rule pick on normalized query
            let pick = ToolRanker.tryRulePick(query: cleaned.lowercased(), screen: screen)
                ?? ToolRanker.tryRulePick(query: messy.lowercased(), screen: screen)

            if pick?.tool == expectedTool {
                correct += 1
            } else {
                print("  ❌ NORM→RULE: '\(messy)' → '\(cleaned)' → \(pick?.tool ?? "nil") (expected \(expectedTool))")
            }
        }
        print("📊 Normalize→RulePick: \(correct)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(correct, 1, "At least 1 normalize→pick should work")
    }

    // MARK: - Lite: Tool-Call JSON Generation (Both Models)

    func testLiteGemmaToolCallJSON() async throws {
        guard let backend = Self.gemmaBackend else { throw XCTSkip("Gemma not available") }
        try await runToolCallTest(backend: backend, modelName: "Gemma4")
    }

    func testLiteSmolLMToolCallJSON() async throws {
        guard let backend = Self.smolBackend else { throw XCTSkip("SmolLM not available") }
        try await runToolCallTest(backend: backend, modelName: "SmolLM", minCorrect: 1)
    }

    private func runToolCallTest(backend: LlamaCppBackend, modelName: String, minCorrect: Int = 2) async {
        let sysPrompt = """
        You help track food, weight, and workouts. \
        LOGGING (user ate/did/weighed something) → output ONLY JSON: {"tool":"name","params":{"key":"value"}} \
        QUESTION (user asks about data) → output ONLY JSON: {"tool":"name","params":{}} \
        CHAT (greeting, thanks) → respond naturally, no tool. \
        Examples: \
        "I had 2 eggs" → {"tool":"log_food","params":{"name":"eggs","amount":"2"}} \
        "calories left" → {"tool":"food_info","params":{}} \
        "I weigh 165 lbs" → {"tool":"log_weight","params":{"value":"165","unit":"lbs"}} \
        "thanks" → You're welcome! (no tool) \
        Tools:
        - log_food(name:string, amount:number) — User wants to LOG food
        - food_info(query:string) — User asks ABOUT food
        - log_weight(value:number, unit:string) — User wants to LOG weight
        - weight_info() — User asks ABOUT weight
        - start_workout(name:string) — User wants to START a workout
        """
        let context = "Calories: 1200 eaten, 1800 target, 600 remaining"

        let queries: [(String, String?)] = [
            ("I had 2 eggs", "log_food"),
            ("calories left?", "food_info"),
            ("I weigh 165 lbs", "log_weight"),
            ("start chest workout", "start_workout"),
            ("thanks!", nil),
        ]

        var correct = 0
        for (query, expected) in queries {
            let prompt = "Context: \(context)\n\nUser: \(query)"
            let response = await backend.respond(to: prompt, systemPrompt: sysPrompt)
            let call = parseToolCallJSON(response)

            let match: Bool
            if let expected {
                match = call?.tool == expected
            } else {
                match = call == nil
            }

            if match {
                correct += 1
            } else {
                print("  ❌ [\(modelName)] JSON: '\(query)' → \(call?.tool ?? "none") (expected \(expected ?? "none"))")
            }
        }
        print("📊 \(modelName) Tool-Call JSON: \(correct)/\(queries.count)")
        XCTAssertGreaterThanOrEqual(correct, minCorrect, "\(modelName) JSON: \(correct)/\(queries.count)")
    }

    // MARK: - Deep: Ambiguous Queries (Need LLM Judgment)

    func testDeepAmbiguousQueries() async throws {
        guard ProcessInfo.processInfo.environment["DRIFT_DEEP_EVAL"] != nil else {
            throw XCTSkip("Set DRIFT_DEEP_EVAL=1 to run")
        }
        guard let backend = Self.gemmaBackend else { throw XCTSkip("Gemma not available") }

        let sysPrompt = """
        You help track food, weight, and workouts. \
        LOGGING → JSON tool call. QUESTION → JSON info tool. CHAT → text. \
        Tools: log_food(name,amount), food_info(query), log_weight(value,unit), \
        weight_info(), start_workout(name), exercise_info(exercise), sleep_recovery()
        """
        let context = "Calories: 1200/1800. Weight: 165 lbs, -0.8/wk."

        // These are intentionally ambiguous — tests LLM's judgment
        let queries: [(String, [String], String)] = [
            // query, acceptable tools, label
            ("chicken", ["log_food", "food_info"], "bare food word"),
            ("150", ["log_weight", "log_food"], "bare number"),
            ("I want to get stronger", ["exercise_info", "start_workout"], "vague fitness"),
            ("am I doing okay", ["food_info", "weight_info"], "vague progress"),
            ("what's creatine", [], "general knowledge (no tool expected)"),
            ("should I eat more or less", ["food_info"], "dietary advice"),
            ("I'm so tired", ["sleep_recovery"], "feeling state"),
            ("rest day?", ["sleep_recovery", "exercise_info"], "ambiguous rest"),
            ("how am I looking", ["weight_info", "body_comp"], "vague body"),
            ("protein", ["food_info"], "single word macro"),
        ]

        var correct = 0
        for (query, acceptable, label) in queries {
            let prompt = "Context: \(context)\n\nUser: \(query)"
            let response = await backend.respond(to: prompt, systemPrompt: sysPrompt)
            let call = parseToolCallJSON(response)

            let match: Bool
            if acceptable.isEmpty {
                match = call == nil // no tool expected
            } else {
                match = call != nil && acceptable.contains(call!.tool)
            }

            if match {
                correct += 1
            } else {
                print("  ❌ AMBIGUOUS '\(label)': '\(query)' → \(call?.tool ?? "none") (acceptable: \(acceptable))")
            }
        }
        print("📊 Gemma Ambiguous: \(correct)/\(queries.count)")
        XCTAssertGreaterThanOrEqual(correct, queries.count / 3, "Ambiguous: \(correct)/\(queries.count)")
    }

    // MARK: - Deep: Multi-Turn Context

    func testDeepMultiTurnContext() async throws {
        guard ProcessInfo.processInfo.environment["DRIFT_DEEP_EVAL"] != nil else {
            throw XCTSkip("Set DRIFT_DEEP_EVAL=1 to run")
        }
        guard let backend = Self.gemmaBackend else { throw XCTSkip("Gemma not available") }

        let sysPrompt = """
        You help track food, weight, and workouts. \
        LOGGING → JSON: {"tool":"name","params":{...}} \
        QUESTION → JSON info tool. CHAT → text. \
        Tools: log_food(name,amount), food_info(query), log_weight(value,unit), weight_info()
        """

        // Simulate multi-turn: history provides context for follow-up
        let conversations: [(history: String, query: String, expectedTool: String?, label: String)] = [
            (
                "Q: how many calories in a banana\nA: A banana has about 105 calories.",
                "log it",
                "log_food",
                "pronoun resolution after nutrition lookup"
            ),
            (
                "Q: I had chicken for lunch\nA: Found Chicken Breast (165 cal). Logged!",
                "and rice",
                "log_food",
                "follow-up food addition"
            ),
            (
                "Q: how's my weight\nA: You're at 165 lbs, down 0.8/week.",
                "thanks",
                nil,
                "thanks after data query (no tool)"
            ),
        ]

        var correct = 0
        for conv in conversations {
            let prompt = "Chat history:\n\(conv.history)\n\nUser: \(conv.query)"
            let response = await backend.respond(to: prompt, systemPrompt: sysPrompt)
            let call = parseToolCallJSON(response)

            let match: Bool
            if let expected = conv.expectedTool {
                match = call?.tool == expected
            } else {
                match = call == nil
            }

            if match {
                correct += 1
            } else {
                print("  ❌ MULTI-TURN '\(conv.label)': '\(conv.query)' → \(call?.tool ?? "none")")
            }
        }
        print("📊 Multi-Turn: \(correct)/\(conversations.count)")
    }

    // MARK: - Deep: Info Queries Without Data Context

    func testDeepInfoQueriesWithoutData() async throws {
        guard ProcessInfo.processInfo.environment["DRIFT_DEEP_EVAL"] != nil else {
            throw XCTSkip("Set DRIFT_DEEP_EVAL=1 to run")
        }
        guard let backend = Self.gemmaBackend else { throw XCTSkip("Gemma not available") }

        let sysPrompt = """
        You help track food, weight, and workouts. \
        QUESTION → output JSON: {"tool":"info_tool","params":{}} \
        Tools: food_info(query), weight_info(), exercise_info(exercise), sleep_recovery(), supplements()
        """

        // Info queries that should pick the right info tool
        let queries: [(String, String)] = [
            ("how many calories have I had", "food_info"),
            ("am I on track with my diet", "food_info"),
            ("what's my weight trend", "weight_info"),
            ("am I losing weight", "weight_info"),
            ("what did I train this week", "exercise_info"),
            ("how's my recovery", "sleep_recovery"),
            ("did I take my supplements", "supplements"),
            ("what's my protein intake today", "food_info"),
            ("when was my last workout", "exercise_info"),
            ("how many hours did I sleep", "sleep_recovery"),
        ]

        var correct = 0
        for (query, expected) in queries {
            let response = await backend.respond(to: "User: \(query)", systemPrompt: sysPrompt)
            let call = parseToolCallJSON(response)
            if call?.tool == expected {
                correct += 1
            } else {
                print("  ❌ INFO: '\(query)' → \(call?.tool ?? "none") (expected \(expected))")
            }
        }
        print("📊 Info Queries: \(correct)/\(queries.count)")
        XCTAssertGreaterThanOrEqual(correct, queries.count / 3, "Info: \(correct)/\(queries.count)")
    }
}
