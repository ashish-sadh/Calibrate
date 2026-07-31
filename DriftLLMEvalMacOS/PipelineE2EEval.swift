import XCTest
import DriftCore
import Foundation

/// End-to-end pipeline simulation with real Gemma 4 LLM.
///
/// Simulates how queries flow on the iPhone:
///   InputNormalizer → IntentClassifier (LLM) → MockToolExecutor → PresentationLLM
///
/// Tool execution is mocked with realistic canned data — the LLM sees the same
/// kind of data it sees on device, so presentation quality is real.
/// Multi-turn: history is accumulated and fed back, just like AIChatView does.
///
/// Run: xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'
final class PipelineE2EEval: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try LLMEvalGate.requireLLM()  // report as skipped, never false-green
    }


    // MARK: - Shared Backend

    nonisolated(unsafe) static var gemma: LlamaCppBackend?

    override class func setUp() {
        super.setUp()
        guard LLMEvalGate.enabled else { return }  // Tier-3 gate: default run must not load the model
        let path = URL.homeDirectory.appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: path.path) else {
            fatalError("❌ Model missing. Run: bash scripts/download-models.sh")
        }
        let b = LlamaCppBackend(modelPath: path, threads: 6)
        try? b.loadSync()
        guard b.isLoaded else { fatalError("❌ Gemma 4 failed to load") }
        gemma = b
        print("✅ Gemma 4 ready for E2E eval")
    }

    // MARK: - Mock Tool Data

    /// Canned tool responses — realistic data the LLM will present to the user.
    private static func mockToolResult(tool: String, params: [String: String]) -> String? {
        switch tool {
        case "food_info":
            let q = params["query"] ?? ""
            if q.contains("calori") && (q.contains("samosa") || q.contains("in ")) {
                return "Samosa (1 piece, ~50g): 130 cal, 4g protein, 17g carbs, 6g fat"
            }
            if q.contains("weekly") { return "This week: Mon 1820cal, Tue 2100cal, Wed 1650cal, Thu 1900cal. Avg 1868 cal/day. Goal: 2000 cal." }
            if q.contains("daily") || q.contains("summary") { return "Today: Breakfast 450 cal, Lunch 620 cal. Total 1070/2000 cal. Protein: 68/150g. 930 cal remaining." }
            if q.contains("calories left") { return "930 calories remaining today. You've had 1070/2000 cal. Protein: 68/150g." }
            if q.contains("protein") { return "Today's protein: 68g of 150g goal (45%). Best sources: chicken 35g, eggs 18g, paneer 15g." }
            if q.contains("carbs") { return "Carbs today: 120g of 200g goal (60%). From: rice 45g, roti 30g, fruit 25g." }
            return "Food info: \(q). 1070 cal logged today of 2000 goal."
        case "log_food":
            let name = params["name"] ?? params["query"] ?? "food"
            let servings = params["amount"] ?? params["servings"] ?? "1"
            return "Logged: \(name) (\(servings) serving). ~250 cal, 12g protein."
        case "weight_info":
            let q = params["query"] ?? ""
            if q.contains("goal") || q.contains("track") || q.contains("progress") {
                return "Current: 78.2kg. Goal: 72kg. Lost 1.8kg in 3 weeks. At this rate: ~10 weeks to goal. On track ✓"
            }
            return "Weight trend: 78.2kg today, down 0.3kg/week over last month. Goal: 72kg."
        case "sleep_recovery":
            return "Last night: 7h 20m. Deep sleep: 1h 45m. REM: 2h 10m. Score: 84/100. Feeling recovered."
        case "exercise_info":
            let q = params["query"] ?? ""
            if q.contains("recovery") { return "Muscle recovery: 87% ready. Last session: Push Day 2 days ago. Chest/shoulders well-recovered." }
            return "Recent workouts: Push Day (2d ago), Leg Day (4d ago), Pull Day (6d ago). Weekly volume on track."
        case "mark_supplement":
            let name = params["name"] ?? "supplement"
            return "Marked \(name) as taken today."
        case "log_weight":
            let val = params["value"] ?? "?"; let unit = params["unit"] ?? "kg"
            return "Weight logged: \(val) \(unit). Previous: 78.5 \(unit)."
        case "start_workout":
            return "Starting Push Day. 8 exercises loaded: Bench Press, OHP, Incline DB, Lateral Raise, Tricep Pushdown, Cable Fly, Chest Dip, Face Pull."
        case "log_activity":
            let name = params["name"] ?? "activity"; let dur = params["duration"] ?? "30"
            return "Logged: \(name) for \(dur) minutes. Estimated ~180 cal burned."
        case "body_comp":
            return "Body comp: 78.2kg, ~18% body fat, ~64.1kg lean mass. Trending: losing fat, maintaining muscle."
        default:
            return nil
        }
    }

    // MARK: - Pipeline Runner

    struct TurnResult {
        let query: String
        let normalizedQuery: String
        let tool: String?
        let toolParams: [String: String]
        let toolData: String?
        let finalResponse: String
    }

    private func runPipeline(
        message: String,
        history: String = ""
    ) async -> TurnResult {
        guard let gemma = Self.gemma else {
            return TurnResult(query: message, normalizedQuery: message, tool: nil, toolParams: [:], toolData: nil, finalResponse: "ERROR: no backend")
        }

        // Stage 1: Normalize
        let normalized = InputNormalizer.normalize(message)

        // Stage 2: Intent Classification (real LLM)
        // Uses same system prompt as IntentClassifier.systemPrompt — keep in sync
        let userMsg = history.isEmpty ? normalized : "Chat:\n\(String(history.prefix(400)))\n\nUser: \(normalized)"
        let classifyResponse = await gemma.respond(to: userMsg, systemPrompt: IntentRoutingEval.systemPrompt) ?? ""

        // Parse tool + params from LLM JSON
        var tool: String? = nil
        var params: [String: String] = [:]
        if let start = classifyResponse.firstIndex(of: "{"),
           let end = classifyResponse.lastIndex(of: "}"),
           let data = String(classifyResponse[start...end]).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let t = json["tool"] as? String {
            tool = t.replacingOccurrences(of: "()", with: "")
            for (k, v) in json where k != "tool" {
                if let s = v as? String { params[k] = s }
                else if let n = v as? Int { params[k] = "\(n)" }
                else if let n = v as? Double { params[k] = "\(n)" }
            }
        }

        // Stage 3: Mock tool execution
        let toolData = tool.flatMap { Self.mockToolResult(tool: $0, params: params) }

        // Stage 4: Presentation (real LLM formats the tool result)
        var finalResponse = classifyResponse
        if let data = toolData, let t = tool {
            let presentPrompt = """
            Health app assistant. Give a short, natural 1-2 sentence response using this data.
            Be direct and helpful. Use the numbers. Don't say "Based on your data".
            Tool: \(t)
            Data: \(data)
            Query: \(normalized)
            """
            let presented = await gemma.respond(to: normalized, systemPrompt: presentPrompt) ?? data
            finalResponse = presented
        }

        return TurnResult(
            query: message,
            normalizedQuery: normalized,
            tool: tool,
            toolParams: params,
            toolData: toolData,
            finalResponse: finalResponse
        )
    }

    // MARK: - Single-Turn Tests

    func testFoodLogging_logsFood() async {
        let result = await runPipeline(message: "log 2 eggs")
        XCTAssertEqual(result.tool, "log_food", "Should route to log_food. Got: \(result.tool ?? "nil")")
        let name = result.toolParams["name"] ?? result.toolParams["query"] ?? ""
        XCTAssertTrue(name.lowercased().contains("egg"), "Should extract 'egg'. Got: '\(name)'")
        // #930: the count must survive extraction — "2 eggs" logging 1 serving
        // of the wrong thing was half the bug.
        let servings = result.toolParams["amount"] ?? result.toolParams["servings"] ?? ""
        XCTAssertTrue(servings.contains("2"), "Should extract servings=2. Got: '\(servings)'")
        print("✅ log 2 eggs → \(result.tool ?? "nil") name=\(name) servings=\(servings) response=\(result.finalResponse)")
    }

    func testFoodInfo_caloriesInFood() async {
        let result = await runPipeline(message: "calories in samosa")
        XCTAssertEqual(result.tool, "food_info", "Should be food_info not log_food. Got: \(result.tool ?? "nil")")
        XCTAssertTrue(result.finalResponse.contains("cal") || result.finalResponse.contains("130"),
            "Response should mention calories. Got: \(result.finalResponse)")
        print("✅ calories in samosa → \(result.tool ?? "nil") response=\(result.finalResponse)")
    }

    func testFoodInfo_dailySummary() async {
        let result = await runPipeline(message: "how am I doing today")
        XCTAssertEqual(result.tool, "food_info", "Daily status should route to food_info. Got: \(result.tool ?? "nil")")
        XCTAssertTrue(result.finalResponse.lowercased().contains("cal"),
            "Should mention calories. Got: \(result.finalResponse)")
        print("✅ daily summary response=\(result.finalResponse)")
    }

    func testWeightInfo_goalProgress() async {
        let result = await runPipeline(message: "am I on track for my goal")
        XCTAssertEqual(result.tool, "weight_info", "Goal progress should be weight_info. Got: \(result.tool ?? "nil")")
        XCTAssertTrue(result.finalResponse.lowercased().contains("goal") || result.finalResponse.lowercased().contains("kg"),
            "Response should mention goal or weight. Got: \(result.finalResponse)")
        print("✅ goal progress response=\(result.finalResponse)")
    }

    func testSleepRecovery() async {
        let result = await runPipeline(message: "how did I sleep last night")
        XCTAssertEqual(result.tool, "sleep_recovery", "Should route to sleep_recovery. Got: \(result.tool ?? "nil")")
        XCTAssertTrue(result.finalResponse.lowercased().contains("sleep") || result.finalResponse.lowercased().contains("h"),
            "Response should mention sleep. Got: \(result.finalResponse)")
        print("✅ sleep query response=\(result.finalResponse)")
    }

    func testMessyVoiceInput() async {
        let result = await runPipeline(message: "um like I had two eggs and uh some toast")
        XCTAssertEqual(result.tool, "log_food", "Messy voice input should still log food. Got: \(result.tool ?? "nil")")
        let name = result.toolParams["name"] ?? ""
        XCTAssertFalse(name.isEmpty, "Should extract food name from messy input")
        print("✅ messy voice → \(result.tool ?? "nil") name=\(name) normalized='\(result.normalizedQuery)'")
    }

    // MARK: - Multi-Turn Tests

    func testMultiTurn_logLunchFlow() async {
        // Turn 1: vague meal intent → LLM asks what you had
        let t1 = await runPipeline(message: "log lunch")
        XCTAssertNil(t1.tool, "Vague 'log lunch' should ask a follow-up, not log immediately. Got tool: \(t1.tool ?? "nil")")
        XCTAssertFalse(t1.finalResponse.isEmpty, "Should ask what they had")
        print("Turn 1: '\(t1.query)' → response: \(t1.finalResponse)")

        // Build history: assistant asked "What did you have for lunch?"
        let h1 = "Assistant: \(t1.finalResponse)"

        // Turn 2: user answers with food → should log it
        let t2 = await runPipeline(message: "rice and dal", history: h1)
        XCTAssertEqual(t2.tool, "log_food", "After follow-up, food answer should log. Got: \(t2.tool ?? "nil")")
        let name = t2.toolParams["name"] ?? ""
        XCTAssertTrue(name.lowercased().contains("rice") || name.lowercased().contains("dal"),
            "Should extract rice/dal. Got: '\(name)'")
        print("Turn 2: 'rice and dal' after ask → tool=\(t2.tool ?? "nil") name=\(name)")
    }

    func testMultiTurn_continuedFood() async {
        // Turn 1: log eggs
        let t1 = await runPipeline(message: "log 2 eggs for breakfast")
        XCTAssertEqual(t1.tool, "log_food")

        let h1 = "User: log 2 eggs for breakfast\nAssistant: Logged 2 eggs."

        // Turn 2: add more to same meal
        let t2 = await runPipeline(message: "also add toast", history: h1)
        XCTAssertEqual(t2.tool, "log_food", "Follow-up food addition should route to log_food. Got: \(t2.tool ?? "nil")")
        let name = t2.toolParams["name"] ?? ""
        XCTAssertTrue(name.lowercased().contains("toast"), "Should extract toast. Got: '\(name)'")
        print("✅ Multi-turn food addition: '\(name)' → \(t2.tool ?? "nil")")
    }

    func testMultiTurn_topicSwitch() async {
        // Start with food context, then switch to sleep
        let history = "User: log 2 eggs\nAssistant: Logged 2 eggs for breakfast."

        let result = await runPipeline(message: "how was my sleep", history: history)
        XCTAssertEqual(result.tool, "sleep_recovery",
            "Topic switch to sleep should route correctly. Got: \(result.tool ?? "nil")")
        print("✅ Topic switch from food → sleep: \(result.tool ?? "nil")")
    }

    // MARK: - Print Summary

    func testPrintE2ESummary() async {
        let scenarios: [(String, String)] = [
            ("log 2 eggs", "log_food"),
            ("calories in samosa", "food_info"),
            ("weekly summary", "food_info"),
            ("am I on track for my goal", "weight_info"),
            ("how was my sleep", "sleep_recovery"),
            ("did I take creatine today", "mark_supplement"),
            ("start push day", "start_workout"),
            ("I did yoga for 30 minutes", "log_activity"),
            ("um had like biryani for lunch", "log_food"),
            ("how much protein today", "food_info"),
        ]

        var correct = 0
        print("\n📊 E2E Pipeline Summary:")
        for (query, expected) in scenarios {
            let result = await runPipeline(message: query)
            let got = result.tool ?? "text"
            let pass = got == expected
            if pass { correct += 1 }
            print("  \(pass ? "✅" : "❌") '\(query)' → \(got) (expected \(expected))")
        }
        print("  Score: \(correct)/\(scenarios.count)\n")
        // Soft assertion — don't fail the build, just report
        XCTAssertGreaterThanOrEqual(correct, scenarios.count - 2, "E2E routing: need ≥\(scenarios.count - 2)/\(scenarios.count)")
    }
}
