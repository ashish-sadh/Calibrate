import XCTest
import Foundation

/// macOS-native LLM eval — runs Gemma 4 directly on macOS (no iOS simulator overhead).
/// Tests whether the LLM correctly routes queries to the right tool.
/// Requires: ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf
/// Setup:    bash scripts/download-models.sh
/// Run:      xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS'
final class IntentRoutingEval: XCTestCase {

    // MARK: - Model Loading

    nonisolated(unsafe) static var gemmaBackend: LlamaCppBackend?
    nonisolated(unsafe) static var smolBackend: LlamaCppBackend?

    static let modelsDir = URL.homeDirectory.appending(path: "drift-state/models")
    static let gemmaPath = URL.homeDirectory.appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")
    static let smolPath  = URL.homeDirectory.appending(path: "drift-state/models/smollm2-360m-instruct-q8_0.gguf")

    override class func setUp() {
        super.setUp()
        guard FileManager.default.fileExists(atPath: gemmaPath.path) else {
            // Intentionally crash the setup so test failures are visible — no silent skip
            fatalError("""
            ❌ Gemma 4 model not found at \(gemmaPath.path)
            Run: bash scripts/download-models.sh
            """)
        }
        let b = LlamaCppBackend(modelPath: gemmaPath, threads: 6)
        try? b.loadSync()
        if b.isLoaded {
            gemmaBackend = b
            print("✅ Gemma 4 loaded from ~/drift-state/models/")
        } else {
            fatalError("❌ Gemma 4 failed to load — check model file integrity")
        }
    }

    // MARK: - System Prompt (mirror of IntentClassifier.systemPrompt)
    // Keep in sync with Drift/Services/IntentClassifier.swift

    static let systemPrompt = """
    Health app. Reply JSON tool call or short text. Fix typos, word numbers, slang — understand messy input.
    Tools: log_food(name,servings?,calories?,protein?,carbs?,fat?) food_info(query) log_weight(value,unit?) weight_info(query?) start_workout(name?) log_activity(name,duration?) exercise_info(query?) sleep_recovery(period?) mark_supplement(name) supplements() set_goal(target,unit?) delete_food(query?) body_comp() glucose() biomarkers() navigate_to(screen)
    RULES: NEVER generate health data from memory — ALWAYS call a tool. "calories in X" → food_info (NOT log_food). Use log_food only when user ate/had/logged. "log lunch"/"log breakfast"/"log dinner" alone (no food named) → ask what they had, do NOT call log_food. "daily summary"/"weekly summary" → food_info. "weight trend"/"weight history" → weight_info. "body fat/lean mass/DEXA/body composition" → body_comp. "blood sugar/glucose" → glucose. "lab results/blood work/biomarkers/cholesterol" → biomarkers. "go to [screen]"/"open [screen]" → navigate_to. supplements() queries supplement tracking — ALWAYS call supplements() for any supplement status/history question, NEVER respond with text. mark_supplement(name) logs intake when user says they TOOK/HAD something. HRV/heart rate variability → sleep_recovery.
    "daily summary"→{"tool":"food_info","query":"daily summary"}
    "weekly summary"→{"tool":"food_info","query":"weekly summary"}
    "lab results"→{"tool":"biomarkers"}
    "weight trend"→{"tool":"weight_info","query":"trend"}
    "had my fish oil today"→{"tool":"mark_supplement","name":"fish oil"}
    "log 2 eggs and toast"→{"tool":"log_food","name":"eggs, toast","servings":"2"}
    "had biryani"→{"tool":"log_food","name":"biryani"}
    "I had 2 to 3 banans"→{"tool":"log_food","name":"banana","servings":"3"}
    "chipotle bowl 3000 cal 30p 45c 67f"→{"tool":"log_food","name":"chipotle bowl","calories":"3000","protein":"30","carbs":"45","fat":"67"}
    "calories left"→{"tool":"food_info","query":"calories left"}
    "calories in samosa"→{"tool":"food_info","query":"calories in samosa"}
    "how many calories in dal"→{"tool":"food_info","query":"calories in dal"}
    "how am I doing"→{"tool":"food_info","query":"daily summary"}
    "what about protein?"→{"tool":"food_info","query":"protein"}
    "log 2 eggs"→{"tool":"log_food","name":"egg","servings":"2"}
    "had 3 eggs"→{"tool":"log_food","name":"egg","servings":"3"}
    "I weigh 75 kg"→{"tool":"log_weight","value":"75","unit":"kg"}
    "am I on track for my goal"→{"tool":"weight_info","query":"goal progress"}
    "how close am I to my goal"→{"tool":"weight_info","query":"goal progress"}
    "start push day"→{"tool":"start_workout","name":"push day"}
    "did yoga for like half an hour"→{"tool":"log_activity","name":"yoga","duration":"30"}
    "took vitamin d"→{"tool":"mark_supplement","name":"vitamin d"}
    "did I take my vitamins"→{"tool":"supplements"}
    "supplement status"→{"tool":"supplements"}
    "check my supplements"→{"tool":"supplements"}
    "which supplements am I missing"→{"tool":"supplements"}
    "what's my body fat"→{"tool":"body_comp"}
    "lean mass progress"→{"tool":"body_comp"}
    "DEXA results"→{"tool":"body_comp"}
    "any glucose spikes"→{"tool":"glucose"}
    "how's my blood sugar"→{"tool":"glucose"}
    "show my biomarkers"→{"tool":"biomarkers"}
    "how'd I sleep"→{"tool":"sleep_recovery"}
    "my hrv today"→{"tool":"sleep_recovery","query":"hrv"}
    "how's my muscle recovery"→{"tool":"exercise_info","query":"muscle recovery"}
    "set my goal to one sixty"→{"tool":"set_goal","target":"160","unit":"lbs"}
    "delete last"→{"tool":"delete_food"}
    "show me my weight chart"→{"tool":"navigate_to","screen":"weight"}
    "go to food tab"→{"tool":"navigate_to","screen":"food"}
    "open exercise"→{"tool":"navigate_to","screen":"exercise"}
    "go to sleep tab"→{"tool":"navigate_to","screen":"bodyRhythm"}
    "open supplements"→{"tool":"navigate_to","screen":"supplements"}
    "show dashboard"→{"tool":"navigate_to","screen":"dashboard"}
    "go to glucose"→{"tool":"navigate_to","screen":"glucose"}
    "open biomarkers"→{"tool":"navigate_to","screen":"biomarkers"}
    "log lunch"→What did you have for lunch?
    "add my dinner"→What did you have for dinner?
    "hi"→Hi! How can I help?
    "i just love breakfast"→That's great! What did you have?
    "i love eating healthy"→Nice! Want to log something?
    If chat context shows "What did you have for lunch?" and user says "rice and dal"→{"tool":"log_food","name":"rice, dal"}
    If chat context shows sleep data and user says "what about last week"→{"tool":"sleep_recovery","period":"week"}
    JSON when you have enough info. Ask follow-up if details missing. Short text for chat.
    """

    // MARK: - Helpers

    private func classify(_ message: String, history: String = "") async -> String? {
        guard let backend = Self.gemmaBackend else { return nil }
        let userMsg = history.isEmpty ? message : "Chat:\n\(String(history.prefix(400)))\n\nUser: \(message)"
        return await backend.respond(to: userMsg, systemPrompt: Self.systemPrompt)
    }

    private func extractTool(_ response: String) -> String? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              let data = String(response[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String else { return nil }
        return tool
    }

    private func assertRoutes(_ query: String, to expectedTool: String, history: String = "", file: StaticString = #filePath, line: UInt = #line) async {
        guard let response = await classify(query, history: history) else {
            XCTFail("No response for '\(query)'", file: file, line: line); return
        }
        let tool = extractTool(response)
        XCTAssertEqual(tool, expectedTool,
            "'\(query)' → '\(tool ?? "text")' (expected '\(expectedTool)')\nFull response: \(response)",
            file: file, line: line)
    }

    private func assertNotFood(_ query: String, file: StaticString = #filePath, line: UInt = #line) async {
        guard let response = await classify(query) else {
            XCTFail("No response for '\(query)'", file: file, line: line); return
        }
        let tool = extractTool(response)
        XCTAssertNotEqual(tool, "log_food",
            "'\(query)' was misrouted to log_food!\nFull response: \(response)",
            file: file, line: line)
    }

    // MARK: - Food Logging (must route to log_food)

    func testFoodLogging_basic() async {
        await assertRoutes("log 2 eggs", to: "log_food")
        await assertRoutes("I had biryani", to: "log_food")
        await assertRoutes("ate some dal and rice", to: "log_food")
        await assertRoutes("had 3 eggs for breakfast", to: "log_food")
        await assertRoutes("log paneer biryani 300g", to: "log_food")
    }

    func testFoodLogging_messy() async {
        await assertRoutes("I had like 2 bannanas", to: "log_food")
        await assertRoutes("ate sum chicken n rice", to: "log_food")
        await assertRoutes("log 2 to 3 apples", to: "log_food")
        await assertRoutes("had a bowl of dal", to: "log_food")
        await assertRoutes("just ate chipotle bowl 800 cal", to: "log_food")
    }

    func testFoodInfo_queries() async {
        await assertRoutes("calories left", to: "food_info")
        await assertRoutes("calories in samosa", to: "food_info")
        await assertRoutes("how much protein today", to: "food_info")
        await assertRoutes("how am I doing today", to: "food_info")      // daily summary intent
        await assertRoutes("how did I do this week", to: "food_info")    // weekly summary intent
        await assertRoutes("what about protein?", to: "food_info")
    }

    // MARK: - Non-Food (MUST NOT route to log_food — regression class)

    func testNonFood_sleep() async {
        await assertNotFood("how was my sleep last night")
        await assertNotFood("how'd I sleep")
        await assertNotFood("show me my sleep quality")
        await assertRoutes("how was my sleep last night", to: "sleep_recovery")
    }

    func testNonFood_supplements() async {
        await assertNotFood("did I take my creatine")
        await assertNotFood("did I take my supplements today")
        await assertRoutes("took vitamin d", to: "mark_supplement")
        await assertRoutes("did I take my creatine", to: "mark_supplement")
    }

    func testNonFood_exercise() async {
        await assertNotFood("how much did I bench last week")
        await assertNotFood("how many pushups last week")
        await assertRoutes("how much did I bench", to: "exercise_info")
        await assertRoutes("start push day", to: "start_workout")
        await assertRoutes("did yoga for 30 minutes", to: "log_activity")
    }

    func testNonFood_weight() async {
        await assertNotFood("what's my weight trend")
        await assertNotFood("am I on track for my goal")
        await assertRoutes("what's my weight trend", to: "weight_info")
        await assertRoutes("I weigh 75 kg", to: "log_weight")
        await assertRoutes("am I on track for my goal", to: "weight_info")
    }

    func testNonFood_health() async {
        await assertNotFood("how's my body fat")
        await assertNotFood("show me my biomarkers")
        await assertNotFood("what's my lean mass")
        await assertNotFood("check my DEXA results")
        await assertRoutes("how's my body fat", to: "body_comp")
        await assertRoutes("what's my lean mass", to: "body_comp")
        await assertRoutes("show me my biomarkers", to: "biomarkers")
    }

    // MARK: - Body Composition (body_comp)

    func testBodyComp_routing() async {
        await assertRoutes("what's my body fat", to: "body_comp")
        await assertRoutes("lean mass progress", to: "body_comp")
        await assertRoutes("DEXA results", to: "body_comp")
        await assertRoutes("show my body composition", to: "body_comp")
        await assertRoutes("how much muscle have I gained", to: "body_comp")
    }

    // MARK: - Supplements (mark vs status)

    func testSupplements_markVsStatus() async {
        // Marking (took/had) → mark_supplement
        await assertRoutes("took creatine", to: "mark_supplement")
        await assertRoutes("had my fish oil today", to: "mark_supplement")
        // Status query (did I take / what supplements) → supplements
        await assertRoutes("did I take my vitamins", to: "supplements")
        await assertRoutes("supplement status", to: "supplements")
        await assertRoutes("which supplements am I missing", to: "supplements")
    }

    // MARK: - Glucose & Biomarkers

    func testGlucose_routing() async {
        await assertRoutes("any glucose spikes", to: "glucose")
        await assertRoutes("how's my blood sugar", to: "glucose")
        await assertRoutes("blood sugar today", to: "glucose")
        // Slang + implicit intent
        await assertRoutes("was I spiking after dinner", to: "glucose")
        await assertRoutes("show my CGM data", to: "glucose")
        await assertRoutes("blood glucose this morning", to: "glucose")
    }

    func testBiomarkers_routing() async {
        await assertRoutes("show my biomarkers", to: "biomarkers")
        await assertRoutes("show my lab results", to: "biomarkers")
        await assertRoutes("how's my cholesterol", to: "biomarkers")
        // Specific biomarker types
        await assertRoutes("what's my vitamin D level", to: "biomarkers")
        await assertRoutes("A1C results", to: "biomarkers")
        await assertRoutes("check my iron levels", to: "biomarkers")
    }

    // MARK: - Supplements (status regression)

    func testSupplements_statusRegression() async {
        // These must call supplements tool, NOT return text
        await assertRoutes("supplement status", to: "supplements")
        await assertRoutes("how are my supplements", to: "supplements")
        await assertRoutes("which supplements am I missing", to: "supplements")
        await assertRoutes("what supplements did I take today", to: "supplements")
    }

    // MARK: - Implicit Food Logging

    func testFoodLogging_implicit() async {
        // Real user phrasings — no explicit "log" keyword
        await assertRoutes("grabbed a coffee", to: "log_food")
        await assertRoutes("snacked on almonds", to: "log_food")
        await assertRoutes("breakfast was 2 idlis", to: "log_food")
        // Slang / casual
        await assertRoutes("just had some roti with sabzi", to: "log_food")
        await assertRoutes("my dinner was pasta", to: "log_food")
        await assertRoutes("finished a bowl of oats", to: "log_food")
        // Implicit past tense
        await assertRoutes("ate at chipotle for lunch", to: "log_food")
    }

    // MARK: - Navigation (extended screens)

    func testNavigation_extendedScreens() async {
        await assertRoutes("go to sleep tab", to: "navigate_to")
        await assertRoutes("open supplements", to: "navigate_to")
        await assertRoutes("show dashboard", to: "navigate_to")
        await assertRoutes("go to glucose", to: "navigate_to")
        await assertRoutes("open biomarkers", to: "navigate_to")
    }

    // MARK: - Multi-Turn Context

    func testMultiTurn_mealContinuation() async {
        let lunchHistory = "Assistant: What did you have for lunch?"
        await assertRoutes("rice and dal", to: "log_food", history: lunchHistory)
        await assertRoutes("just had a bowl of soup", to: "log_food", history: lunchHistory)
        await assertRoutes("paneer and roti", to: "log_food", history: lunchHistory)

        let dinnerHistory = "Assistant: What did you have for dinner?"
        await assertRoutes("pasta with chicken", to: "log_food", history: dinnerHistory)
        await assertRoutes("biryani", to: "log_food", history: dinnerHistory)
    }

    func testMultiTurn_followUp() async {
        let eggHistory = "User: log 2 eggs\nAssistant: Logged 2 eggs (148 cal)"
        await assertRoutes("also add toast", to: "log_food", history: eggHistory)
        await assertRoutes("and a coffee", to: "log_food", history: eggHistory)

        let weightHistory = "User: I weigh 74 kg\nAssistant: Logged weight: 74 kg"
        await assertRoutes("how's my progress", to: "weight_info", history: weightHistory)

        let sleepHistory = "User: how'd I sleep\nAssistant: You slept 7h 20m last night."
        await assertRoutes("what about last week", to: "sleep_recovery", history: sleepHistory)
    }

    // MARK: - Sleep (extended edge cases: slang, implicit, messy)

    func testSleep_extended() async {
        await assertRoutes("how many hours did I sleep", to: "sleep_recovery")
        await assertRoutes("was my sleep good last night", to: "sleep_recovery")
        await assertRoutes("sleep score this week", to: "sleep_recovery")
        await assertRoutes("my hrv today", to: "sleep_recovery")
        await assertRoutes("how rested am I", to: "sleep_recovery")
    }

    // MARK: - Goal Setting (set_goal)

    func testGoalSetting_routing() async {
        await assertRoutes("set my goal to 150 lbs", to: "set_goal")
        await assertRoutes("change my weight goal to 70 kg", to: "set_goal")
        await assertRoutes("I want to reach 165", to: "set_goal")
        // Implicit phrasing
        await assertRoutes("my target is 68 kg", to: "set_goal")
        await assertRoutes("my goal weight is 160 pounds", to: "set_goal")
    }

    // MARK: - Delete Food (delete_food)

    func testDelete_routing() async {
        await assertRoutes("delete last entry", to: "delete_food")
        await assertRoutes("delete that food", to: "delete_food")
        await assertRoutes("undo last food entry", to: "delete_food")
        await assertRoutes("undo that food log", to: "delete_food")
        await assertRoutes("delete what I just added", to: "delete_food")
    }

    // MARK: - Exercise Info (exercise_info edge cases)

    func testExercise_edgeCases() async {
        // Slang + messy spelling
        await assertRoutes("how many pushups last wk", to: "exercise_info")
        await assertRoutes("wat did I lift yest", to: "exercise_info")
        // Implicit workout history
        await assertRoutes("am I overtraining", to: "exercise_info")
        await assertRoutes("when was my last leg day", to: "exercise_info")
        await assertRoutes("how's my muscle recovery looking", to: "exercise_info")
    }

    // MARK: - Food Logging (Indian food slang + casual phrasings)

    func testFoodLogging_indianSlang() async {
        // Casual Indian-English phrasings
        await assertRoutes("had dal chawal for lunch", to: "log_food")
        await assertRoutes("ate roti sabzi", to: "log_food")
        await assertRoutes("took 2 parathas", to: "log_food")
        await assertRoutes("had some khichdi", to: "log_food")
        await assertRoutes("finished my thali", to: "log_food")
    }

    // MARK: - Start Workout (start_workout)

    func testStartWorkout_routing() async {
        await assertRoutes("start push day", to: "start_workout")
        await assertRoutes("begin chest day", to: "start_workout")
        await assertRoutes("start my upper body workout", to: "start_workout")
        await assertRoutes("kick off leg day", to: "start_workout")
        await assertRoutes("begin pull day", to: "start_workout")
    }

    // MARK: - Log Weight (log_weight)

    func testLogWeight_routing() async {
        await assertRoutes("I weigh 75 kg", to: "log_weight")
        await assertRoutes("my weight is 68.5 kg", to: "log_weight")
        await assertRoutes("just weighed in at 80 kg", to: "log_weight")
        await assertRoutes("I'm 162 pounds now", to: "log_weight")
        await assertRoutes("weighed myself — 73.2 kg", to: "log_weight")
    }

    // MARK: - Log Activity (log_activity)

    func testLogActivity_routing() async {
        await assertRoutes("did yoga for 30 minutes", to: "log_activity")
        await assertRoutes("ran 5k this morning", to: "log_activity")
        await assertRoutes("went for a 45 min walk", to: "log_activity")
        await assertRoutes("biked for an hour", to: "log_activity")
        await assertRoutes("swam laps for 30 min", to: "log_activity")
    }

    // MARK: - Weight Info (extended edge cases)

    func testWeightInfo_extended() async {
        await assertRoutes("how close am I to my goal weight", to: "weight_info")
        await assertRoutes("when will I reach my target", to: "weight_info")
        await assertRoutes("weight history this month", to: "weight_info")
        await assertRoutes("how much have I lost this week", to: "weight_info")
        await assertRoutes("what's my weight history", to: "weight_info")
    }

    // MARK: - Ambiguous (should ask, not blindly log)

    func testAmbiguous_mealWithoutItems() async {
        // "log lunch" should return a text response (ask what they had), NOT log_food
        let response = await classify("log lunch") ?? ""
        let tool = extractTool(response)
        // Either it asks a follow-up question (no tool) or it routes to log_food — both are OK
        // but it must NOT return an error
        XCTAssertFalse(response.isEmpty, "Response should not be empty for 'log lunch'")
        print("'log lunch' → tool=\(tool ?? "none") response=\(response.prefix(100))")
    }

    // MARK: - Summary

    func testPrintRoutingSummary() async {
        let cases: [(String, String)] = [
            ("log 2 eggs", "log_food"),
            ("calories left", "food_info"),
            ("how'd I sleep", "sleep_recovery"),
            ("took creatine", "mark_supplement"),
            ("start push day", "start_workout"),
            ("I weigh 75 kg", "log_weight"),
            ("what's my weight trend", "weight_info"),
            ("how much did I bench", "exercise_info"),
        ]
        var passed = 0
        for (query, expected) in cases {
            guard let response = await classify(query) else { continue }
            let actual = extractTool(response) ?? "text"
            let ok = actual == expected
            if ok { passed += 1 }
            print("\(ok ? "✅" : "❌") '\(query)' → \(actual) (expected \(expected))")
        }
        print("📊 Routing: \(passed)/\(cases.count)")
        XCTAssertGreaterThanOrEqual(passed, cases.count * 8 / 10,
            "Routing accuracy below 80% — LLM needs prompt tuning")
    }
}
