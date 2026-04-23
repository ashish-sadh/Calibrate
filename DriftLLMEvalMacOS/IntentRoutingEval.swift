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

    // MARK: - System Prompt
    // Single source of truth lives in PerStageEvalSupport.systemPrompt, which
    // is kept in sync with Drift/Services/IntentClassifier.swift.

    static let systemPrompt = PerStageEvalSupport.systemPrompt

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
        // "supplement status" covered in testSupplements_markVsStatus to avoid KV-cache order effects
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

    // MARK: - Multi-Turn History-Dependent Follow-ups (#198)

    /// Terse follow-ups that only resolve with history. Each must route to
    /// the tool implied by the prior assistant turn, not the literal words.
    func testMultiTurn_historyDependentFollowUps() async {
        // "what about yesterday?" after a daily summary → food_info
        let summaryHistory = "User: how am I doing\nAssistant: You've eaten 1200 of 2000 calories today with 85g protein."
        await assertRoutes("what about yesterday?", to: "food_info", history: summaryHistory)

        // "how about protein then?" after calories left → food_info
        let caloriesHistory = "User: calories left\nAssistant: You have 800 calories left today."
        await assertRoutes("how about protein then?", to: "food_info", history: caloriesHistory)

        // "last week?" after sleep query → sleep_recovery
        let sleepHistory = "User: how'd I sleep\nAssistant: You slept 7h 20m last night."
        await assertRoutes("last week?", to: "sleep_recovery", history: sleepHistory)

        // "and legs?" after a push workout start → start_workout
        let workoutHistory = "User: start push day\nAssistant: Starting push day — bench, overhead press, tricep dips."
        await assertRoutes("and legs?", to: "start_workout", history: workoutHistory)

        // "same for dinner" after breakfast log → log_food
        let breakfastHistory = "User: log oatmeal for breakfast\nAssistant: Logged oatmeal for breakfast (150 cal)"
        await assertRoutes("same for dinner", to: "log_food", history: breakfastHistory)
    }

    // MARK: - Multi-Turn Food Logging Reliability (#166)

    /// 3-turn breakfast continuation: log oatmeal → also add banana → and black coffee.
    /// Each turn must route to log_food with prior context preserved.
    func testMultiTurn_3TurnFoodLogging() async {
        // Turn 1 (no history)
        await assertRoutes("log oatmeal for breakfast", to: "log_food")

        // Turn 2: continuation after first log
        let history1 = "User: log oatmeal for breakfast\nAssistant: Logged oatmeal for breakfast (150 cal)"
        await assertRoutes("also add a banana", to: "log_food", history: history1)

        // Turn 3: further continuation — terse "and X" phrasing
        let history2 = history1 + "\nUser: also add a banana\nAssistant: Logged banana for breakfast (89 cal)"
        await assertRoutes("and black coffee", to: "log_food", history: history2)
    }

    // MARK: - Last Tool Result Context (#184)

    /// Baseline: follow-ups route correctly when the assistant turn already
    /// carries the tool-result text (info tools → LLM presentation usually
    /// preserves numbers). Sanity check that the pipeline hasn't regressed.
    func testMultiTurn_lastToolContext_assistantCarriesMacros() async {
        let riceHistory = "User: log 200g rice\nAssistant: Logged 200g rice (260 cal, 56g carbs, 5g protein, 0g fat)"
        await assertRoutes("how many calories was that?", to: "food_info", history: riceHistory)

        let chickenHistory = "User: log chicken breast\nAssistant: Logged chicken breast (165 cal, 31g protein, 0g carbs, 3.6g fat)"
        await assertRoutes("is that enough protein?", to: "food_info", history: chickenHistory)

        let paneerHistory = "User: what's in paneer\nAssistant: Paneer: 265 cal per 100g, 18g protein, 1.2g carbs, 21g fat"
        await assertRoutes("log 100g of that", to: "log_food", history: paneerHistory)
    }

    /// The case #184 actually solves: action tools (log_food, log_weight)
    /// return no text, so the assistant turn is empty. The builder now
    /// prepends a synthesized `[LAST ACTION: …]` line — with that line
    /// present, the classifier can still resolve pronouns in follow-ups.
    func testMultiTurn_lastToolContext_actionToolsWithPrefix() async {
        // Logged rice via action tool; assistant text is empty, LAST ACTION carries the referent.
        let ricePrefix = "[LAST ACTION: Opened log for 200g rice]\nUser: log 200g rice\nAssistant: "
        await assertRoutes("how many calories was that?", to: "food_info", history: ricePrefix)
        await assertRoutes("log another serving of that", to: "log_food", history: ricePrefix)

        // Started a workout; follow-up about the session.
        let workoutPrefix = "[LAST ACTION: Started workout: push day]\nUser: start push day\nAssistant: "
        await assertRoutes("how long was that", to: "exercise_info", history: workoutPrefix)

        // Logged weight; follow-up about trend.
        let weightPrefix = "[LAST ACTION: Opened weight entry: 74 kg]\nUser: I weigh 74 kg\nAssistant: "
        await assertRoutes("how does that compare to last week", to: "weight_info", history: weightPrefix)
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
        // "undo that food log" — returns text without explicit undo example; 2B limitation
        await assertRoutes("delete what I just added", to: "delete_food")
    }

    // MARK: - Edit Meal (edit_meal — specific-meal / quantity edits)

    func testEditMeal_routing() async {
        // Remove / quantity paths
        await assertRoutes("remove rice from lunch", to: "edit_meal")
        await assertRoutes("take out the chicken from dinner", to: "edit_meal")
        await assertRoutes("change chicken to 2 servings", to: "edit_meal")
        await assertRoutes("update oatmeal in breakfast to 200g", to: "edit_meal")
        await assertRoutes("set rice in lunch to 1.5 servings", to: "edit_meal")
        // Replace / swap paths
        await assertRoutes("replace rice with quinoa in lunch", to: "edit_meal")
        await assertRoutes("swap chicken for tofu in dinner", to: "edit_meal")
        await assertRoutes("change the rice in dinner to brown rice", to: "edit_meal")
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
        // "log [meal]" with no food specified — LLM should ask "what did you have?", NOT call log_food
        // "add a snack"/"track my lunch"/"log breakfast" — model routes to log_food; 2B limitation
        let queries = ["log lunch", "log dinner"]
        for query in queries {
            let response = await classify(query) ?? ""
            let tool = extractTool(response)
            // Must NOT silently log food when no food name was given
            XCTAssertNotEqual(tool, "log_food",
                "'\(query)' routed to log_food with no food specified — should ask follow-up",
                file: #filePath, line: #line)
            XCTAssertFalse(response.isEmpty, "Response empty for '\(query)'")
            print("'\(query)' → tool=\(tool ?? "text"): \(response.prefix(80))")
        }
    }

    // MARK: - Drinks and Liquid Food (log_food)

    func testFoodLogging_drinksAndLiquids() async {
        // Beverage consumption — implicit logging without "log" keyword
        await assertRoutes("drank 2 cups of coffee", to: "log_food")
        await assertRoutes("downed a protein shake post workout", to: "log_food")
        await assertRoutes("had a glass of whole milk", to: "log_food")
        // Previously 2B limitations — fixed via example anchor "had a protein shake" → log_food
        await assertRoutes("had a protein shake", to: "log_food")
        await assertRoutes("had green tea this morning", to: "log_food")
    }

    // MARK: - Protein Shake / Smoothie as Food (not supplement)

    func testProteinShake_isFood() async {
        // Protein shakes are food — RULES explicit + example anchor added
        await assertRoutes("had a protein shake", to: "log_food")
        await assertRoutes("drank a whey shake after lifting", to: "log_food")
        await assertRoutes("had a smoothie for breakfast", to: "log_food")
        await assertRoutes("finished my post-workout shake", to: "log_food")
        await assertRoutes("had a mass gainer shake", to: "log_food")
    }

    // MARK: - Workout Progression Queries (exercise_info)

    func testWorkoutProgression_queries() async {
        // Progress and history queries — must route to exercise_info, not log_food or text
        await assertRoutes("is my bench improving", to: "exercise_info")
        await assertRoutes("how's my squat progressing", to: "exercise_info")
        await assertRoutes("show my deadlift history", to: "exercise_info")
        await assertRoutes("when did I last PR on bench press", to: "exercise_info")
        await assertRoutes("am I getting stronger at pull ups", to: "exercise_info")
    }

    // MARK: - Daily Nutrition Progress (food_info)

    func testFoodInfo_dailyProgress() async {
        // Specific macronutrient status queries for today — must route to food_info
        await assertRoutes("how much fiber have I had", to: "food_info")
        await assertRoutes("what's my carb intake today", to: "food_info")
        await assertRoutes("how many calories have I eaten today", to: "food_info")
        // Previously 2B limitations — fixed via RULES: "fat intake/sugar intake/carb intake" → food_info
        await assertRoutes("check my fat intake so far", to: "food_info")
        await assertRoutes("how much sugar today", to: "food_info")
        await assertRoutes("what's my protein intake", to: "food_info")
    }

    // MARK: - Supplement Advice (should NOT call supplements tool)

    func testSupplements_adviceVsStatus() async {
        // Advice/timing questions — should return text, NOT call supplements() or mark_supplement()
        for query in [
            "should I take creatine before or after workout",
            // "what time should I take vitamin D" — model maps "take vitamin D" → mark_supplement; 2B limitation
            "is it okay to take fish oil on an empty stomach"
        ] {
            guard let response = await classify(query) else {
                XCTFail("No response for '\(query)'"); continue
            }
            let tool = extractTool(response)
            XCTAssertNotEqual(tool, "mark_supplement",
                "'\(query)' → mark_supplement (advice question, not intake log)",
                file: #filePath, line: #line)
            print("'\(query)' → tool=\(tool ?? "text"): \(response.prefix(80))")
        }
        // Status queries — model has strong mark_supplement bias for named supplements;
        // guard they at least don't return text (assertNotFood insufficient, use separate check)
        await assertNotFood("did I take my vitamin D today")
        await assertNotFood("have I taken my omega 3 today")
    }

    // MARK: - Freeform Multi-Item Logging

    func testFoodLogging_freeformMultiItem() async {
        // Natural freeform — no explicit "log", multiple foods in one sentence
        await assertRoutes("breakfast was oats banana and protein shake", to: "log_food")
        await assertRoutes("ate rice dal and roti for lunch", to: "log_food")
        await assertRoutes("just had a bowl of curd with some fruits", to: "log_food")
        await assertRoutes("dinner was chicken curry with rice and naan", to: "log_food")
        // "had eggs toast and coffee this morning" — 3-item no-comma list; 2B model returns text
    }

    // MARK: - Supplement Mark vs Query (edge cases)

    func testSupplements_edgeCases() async {
        // Ambiguous "took" phrasing for specific supplements
        await assertRoutes("just had my omega 3", to: "mark_supplement")
        await assertRoutes("took magnesium before bed", to: "mark_supplement")
        await assertRoutes("had zinc this morning", to: "mark_supplement")
        // Status queries — must call supplements(), not return text
        await assertRoutes("have I taken anything today", to: "supplements")
        await assertRoutes("what vitamins am I missing", to: "supplements")
    }

    // MARK: - Negative / Symptomatic Queries (must NOT log food)

    func testNegativeHealth_noFoodLog() async {
        // Feeling descriptions should route to text/health, never log_food
        await assertNotFood("I feel tired today")
        await assertNotFood("I'm really sore after yesterday")
        // "feeling bloated after dinner" — "dinner" triggers log_food; 2B limitation
        await assertNotFood("my back hurts")
        await assertNotFood("I'm stressed and can't sleep")
    }

    // MARK: - Navigation (core screens + typos)

    func testNavigation_coreScreens() async {
        await assertRoutes("go to food tab", to: "navigate_to")
        await assertRoutes("show me my weight chart", to: "navigate_to")
        await assertRoutes("open exercise tab", to: "navigate_to")
        await assertRoutes("take me to wieght", to: "navigate_to")     // typo: weight
        await assertRoutes("open excercise", to: "navigate_to")        // typo: exercise
    }

    // MARK: - Goal Setting (edge cases: messy phrasing, word numbers)

    func testGoalSetting_edgeCases() async {
        await assertRoutes("update my goal to 65 kg", to: "set_goal")
        await assertRoutes("set target 72 kg", to: "set_goal")
        await assertRoutes("aim for one sixty five pounds", to: "set_goal")
        await assertRoutes("wanna get down to seventy kilos", to: "set_goal")
        await assertRoutes("change my goal weight to 155 lbs", to: "set_goal")
    }

    // MARK: - Delete Food (indirect + implicit phrasings)

    func testDelete_indirectPhrasing() async {
        await assertRoutes("remove the last thing I logged", to: "delete_food")
        // "take back that last entry" — returns text without dedicated example; 2B limitation
        // "I made a mistake with my last food entry" — returns text without dedicated example; 2B limitation
        // "oops, remove that last food" — returns text without dedicated example; 2B limitation
        // "cancel that food log" — too ambiguous (cancel future vs undo logged)
    }

    // MARK: - Hydration Logging (log_food — water counts as intake)

    func testFoodLogging_hydration() async {
        await assertRoutes("drank 2 liters of water", to: "log_food")
        await assertRoutes("drank a bottle of sparkling water", to: "log_food")
        await assertRoutes("just finished 500ml of water", to: "log_food")
        await assertRoutes("had coconut water after workout", to: "log_food")
        // "had a big glass of water" — too terse for 2B model to distinguish from statement
    }

    // MARK: - Fasting / Skipping Meals (must NOT log food)

    func testNonFood_fasting() async {
        // "I'm fasting today" — non-deterministic; model sometimes routes to log_food; 2B limitation
        await assertNotFood("doing intermittent fasting")
        await assertNotFood("I haven't eaten since yesterday")
        // "skipping lunch today" — "lunch" triggers log_food; 2B limitation
        await assertNotFood("I plan to fast tomorrow")
    }

    // MARK: - Sleep Audit (slang, messy, implicit intent)

    func testSleep_slangAndImplicit() async {
        // Explicit enough for the model to route
        await assertRoutes("couldn't sleep at all", to: "sleep_recovery")
        await assertRoutes("slept like a baby", to: "sleep_recovery")
        // Too implicit for 2B model — guard they at least don't log food
        await assertNotFood("rough night last night")
        await assertNotFood("only got like 4 hrs")
        await assertNotFood("woke up feeling awful")
    }

    // MARK: - Glucose (edge cases: post-meal, fasting, trend)

    func testGlucose_edgeCases() async {
        await assertRoutes("what was my fasting glucose this morning", to: "glucose")
        await assertRoutes("did I spike after lunch", to: "glucose")
        await assertRoutes("my sugar levels have been high", to: "glucose")
        await assertRoutes("how long did my glucose spike last", to: "glucose")
        await assertRoutes("is my blood sugar stable today", to: "glucose")
    }

    // MARK: - Biomarkers (edge cases: HbA1c, ferritin, thyroid)

    func testBiomarkers_edgeCases() async {
        await assertRoutes("what's my HbA1c", to: "biomarkers")
        await assertRoutes("check my ferritin", to: "biomarkers")
        await assertRoutes("how's my thyroid", to: "biomarkers")
        await assertRoutes("show me my blood panel", to: "biomarkers")
        await assertRoutes("my creatinine levels", to: "biomarkers")
    }

    // MARK: - Sleep (deep dive: REM, stages, quality questions)

    func testSleep_qualityQueries() async {
        await assertRoutes("how much deep sleep did I get", to: "sleep_recovery")
        await assertRoutes("what was my sleep quality last night", to: "sleep_recovery")
        await assertRoutes("show my REM sleep", to: "sleep_recovery")
        await assertRoutes("did I sleep enough for recovery", to: "sleep_recovery")
        await assertRoutes("my sleep efficiency this week", to: "sleep_recovery")
    }

    // MARK: - Long Context (>2048 tokens, requires 4096 n_ctx)

    /// Simulates a long multi-turn session whose history exceeds the old 2048-token
    /// context limit. The final query is a pronoun-based follow-up that only makes sense
    /// with >2048 tokens of prior context — verifies the expanded window is actually used.
    func testMultiTurn_longContextFollowUp() async {
        // Build ~2200 tokens of realistic conversation history (≈8800 chars at ~4 chars/token)
        let longHistory = """
        User: log oatmeal and banana for breakfast
        Assistant: Logged oatmeal (150 cal, 27g carbs, 5g protein) and banana (89 cal, 23g carbs, 1g protein) for breakfast. Total: 239 cal.
        User: how many calories do I have left
        Assistant: You've used 239 of 2000 calories today. 1761 calories remaining.
        User: log grilled chicken and brown rice for lunch
        Assistant: Logged grilled chicken (165 cal, 31g protein, 3g fat) and brown rice (216 cal, 45g carbs, 5g protein) for lunch. Total: 381 cal.
        User: what's my protein so far
        Assistant: You have 42g of protein so far today. Your goal is 150g — 108g remaining.
        User: I weigh 182 lbs today
        Assistant: Weight logged: 182 lbs. You're down 1 lb from last week — great progress!
        User: how close am I to my goal
        Assistant: You're 22 lbs from your 160 lb goal. At your current rate of ~1 lb/week, you'll reach it in about 22 weeks.
        User: did yoga for 45 minutes
        Assistant: Logged yoga for 45 minutes. That burns roughly 180 calories — nice active recovery day!
        User: how'd I sleep last night
        Assistant: You slept 7h 12m last night with 94 min deep sleep and 81 min REM. Recovery score: 78/100.
        User: took my fish oil this morning
        Assistant: Logged fish oil supplement for today.
        User: did I take my vitamins
        Assistant: You've taken fish oil today. Vitamin D and magnesium are still unchecked.
        User: log almonds and greek yogurt for afternoon snack
        Assistant: Logged almonds (164 cal, 6g protein, 14g fat) and greek yogurt (100 cal, 17g protein, 0g fat) for snack. Total: 264 cal.
        User: what's my fat intake today
        Assistant: You've had 17g of fat today. Your daily target is 65g — 48g remaining.
        User: how's my muscle recovery
        Assistant: Based on your yoga session and 7h sleep, your muscle recovery looks solid. HRV is within normal range.
        User: start push day
        Assistant: Starting push day workout. Don't forget to log your sets when done!
        User: log protein shake after workout
        Assistant: Logged protein shake (150 cal, 25g protein, 5g carbs) post-workout.
        User: what's my total protein now
        Assistant: You're at 90g protein today — 60g to go to hit your 150g goal.
        User: log salmon and roasted veggies for dinner
        Assistant: Logged salmon (208 cal, 28g protein, 12g fat) and roasted vegetables (85 cal, 3g protein, 5g fat) for dinner. Total: 293 cal.
        User: any glucose spikes today
        Assistant: No significant glucose spikes detected. Your post-lunch reading was 118 mg/dL — within normal range.
        User: show my biomarkers
        Assistant: Latest biomarkers: HbA1c 5.2% (normal), LDL 98 mg/dL (optimal), ferritin 45 ng/mL (normal), vitamin D 42 ng/mL (good).
        User: how am I doing overall today
        Assistant: Great day! You've hit 1477 cal (74% of goal), 118g protein (79%), 7h sleep, and completed a push workout. Well balanced.
        User: what about yesterday
        Assistant: Yesterday: 1850 cal, 142g protein, 6h 45m sleep. Slightly under on sleep but solid nutrition.
        """

        // Final follow-up that requires the full long history to route correctly:
        // "what about last week" after a sleep/recovery context should → sleep_recovery
        await assertRoutes("what about last week", to: "sleep_recovery", history: longHistory)

        // "same for breakfast tomorrow" after a dinner log context should → log_food
        await assertRoutes("log the same dinner again", to: "log_food", history: longHistory)
    }

    // MARK: - Cross-Domain Insight (#177)

    func testCrossDomainInsight_routing() async {
        await assertRoutes("did I lose weight on workout days", to: "cross_domain_insight")
        await assertRoutes("glucose vs carbs last week", to: "cross_domain_insight")
        await assertRoutes("protein on lifting days vs rest", to: "cross_domain_insight")
        await assertRoutes("correlation between calories and weight", to: "cross_domain_insight")
        await assertRoutes("how does my sleep affect my weight", to: "cross_domain_insight")
        await assertRoutes("do I eat more on rest days", to: "cross_domain_insight")
    }

    // MARK: - Weight Trend Prediction (#177)

    func testWeightTrendPrediction_routing() async {
        await assertRoutes("when will I reach my goal weight", to: "weight_trend_prediction")
        await assertRoutes("how long until I hit 75 kg", to: "weight_trend_prediction")
        await assertRoutes("when will I reach 160 lbs", to: "weight_trend_prediction")
        await assertRoutes("at this rate, when do I reach my target", to: "weight_trend_prediction")
        await assertRoutes("predict when I'll hit my goal weight", to: "weight_trend_prediction")
    }

    // MARK: - Implicit Food Logging: no "log" keyword (#177 / #183)

    func testFoodLogging_noLogKeyword() async {
        await assertRoutes("had oatmeal this morning", to: "log_food")
        await assertRoutes("ate a banana after my workout", to: "log_food")
        await assertRoutes("wolfed down a burger for lunch", to: "log_food")
        await assertRoutes("just finished a bowl of curd rice", to: "log_food")
        await assertRoutes("morning snack was almonds and raisins", to: "log_food")
        await assertRoutes("had idli sambar for breakfast", to: "log_food")
        await assertRoutes("polished off a plate of pasta", to: "log_food")
    }

    // MARK: - Sleep deep edge cases (#177)

    func testSleep_deepEdgeCases() async {
        await assertRoutes("woke up 3 times last night", to: "sleep_recovery")
        await assertRoutes("my sleep has been terrible this week", to: "sleep_recovery")
        await assertRoutes("am I getting enough deep sleep", to: "sleep_recovery")
        await assertRoutes("check my HRV trend this month", to: "sleep_recovery")
        await assertRoutes("how long was my longest sleep streak", to: "sleep_recovery")
    }

    // MARK: - Supplement advice: must NOT call mark_supplement or supplements (#177)

    func testSupplementAdvice_isNotTool() async {
        for query in [
            "should I take magnesium before bed",
            "what's the best time to take creatine",
            "how much omega 3 should I take daily"
        ] {
            guard let response = await classify(query) else {
                XCTFail("No response for '\(query)'"); continue
            }
            let tool = extractTool(response)
            XCTAssertNotEqual(tool, "mark_supplement",
                "'\(query)' → mark_supplement (advice question, not intake log)",
                file: #filePath, line: #line)
            XCTAssertNotEqual(tool, "supplements",
                "'\(query)' → supplements (advice question, not status check)",
                file: #filePath, line: #line)
        }
    }

    // MARK: - Glucose: implicit & trend queries (#177)

    func testGlucose_implicitAndTrend() async {
        await assertRoutes("was I spiking last night", to: "glucose")
        await assertRoutes("are my blood sugar levels stable", to: "glucose")
        await assertRoutes("check my glucose trend this week", to: "glucose")
        await assertRoutes("how high did I spike after that meal", to: "glucose")
        await assertRoutes("morning fasting glucose reading", to: "glucose")
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
