import XCTest
import Foundation

// MARK: - Shared model loader + prompt for per-stage LLM evals

/// Shared Gemma backend, loaded once and reused across all per-stage LLM evals.
/// nonisolated(unsafe) mirrors the pattern used in IntentRoutingEval.
nonisolated(unsafe) var perStageGemmaBackend: LlamaCppBackend?

enum PerStageEvalSupport {

    static let modelPath = URL.homeDirectory
        .appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")

    /// Load the Gemma model into perStageGemmaBackend. Call from class setUp().
    /// Calls fatalError when the model file is missing so the failure is visible.
    static func loadModel() {
        guard perStageGemmaBackend == nil else { return }
        guard FileManager.default.fileExists(atPath: modelPath.path) else {
            fatalError("❌ Gemma model not found at \(modelPath.path)\nRun: bash scripts/download-models.sh")
        }
        let b = LlamaCppBackend(modelPath: modelPath, threads: 6)
        try? b.loadSync()
        guard b.isLoaded else {
            fatalError("❌ Gemma model failed to load — check model file integrity")
        }
        perStageGemmaBackend = b
        print("✅ [PerStageEval] Gemma loaded")
    }

    // MARK: - Shared system prompt (keep in sync with IntentClassifier.systemPrompt)

    // Kept byte-for-byte identical to IntentClassifier.systemPrompt in the main target.
    static let systemPrompt = """
    Health app. Reply JSON tool call or short text. Fix typos, word numbers, slang.
    Tools: log_food(name,servings?,calories?,protein?,carbs?,fat?) food_info(query) log_weight(value,unit?) weight_info(query?) start_workout(name?) log_activity(name,duration?) exercise_info(query?) sleep_recovery(period?) mark_supplement(name) supplements() set_goal(target,unit?) delete_food(entry_id?,name?) edit_meal(entry_id?,meal_period?,action,target_food?,new_value?) body_comp() glucose() biomarkers() navigate_to(screen) cross_domain_insight(metric_a,metric_b,window_days?) weight_trend_prediction()
    When <recent_entries> is shown and user refers to a row (by ordinal, calories, meal, or "the one I just logged"), pass its id as entry_id. Otherwise use name/target_food.
    Rules: never invent health data — call a tool. "calories in X"→food_info (not log_food). log_food when user ate/had OR said log/add/track/record with a named food. Bare "log lunch/breakfast/dinner" (no food)→ask what they had. "search/find X in my logs"→food_info, not log_food. summary/intake/macros→food_info. weight trend→weight_info. body fat/lean mass/DEXA→body_comp. blood sugar/glucose spike→glucose. lab results/biomarkers/cholesterol→biomarkers. HRV→sleep_recovery. "go to X"/"open X"→navigate_to. supplements() for any supplement status question (never text). mark_supplement when user took/had one.
    Ask vs guess: if user names a concrete food/supplement/exercise/weight/screen, act. Only ask when query has no object (bare "log", "track", "add") or two tools fit equally.
    "daily summary"→{"tool":"food_info","query":"daily summary"}
    "weekly summary"→{"tool":"food_info","query":"weekly summary"}
    "lab results"→{"tool":"biomarkers"}
    "weight trend"→{"tool":"weight_info","query":"trend"}
    "had my fish oil today"→{"tool":"mark_supplement","name":"fish oil"}
    "had biryani"→{"tool":"log_food","name":"biryani"}
    "I had 2 to 3 banans"→{"tool":"log_food","name":"banana","servings":"3"}
    "chipotle bowl 3000 cal 30p 45c 67f"→{"tool":"log_food","name":"chipotle bowl","calories":"3000","protein":"30","carbs":"45","fat":"67"}
    "calories left"→{"tool":"food_info","query":"calories left"}
    "calories in samosa"→{"tool":"food_info","query":"calories in samosa"}
    "how am I doing"→{"tool":"food_info","query":"daily summary"}
    "log 2 eggs"→{"tool":"log_food","name":"egg","servings":"2"}
    "search pizza in my logs"→{"tool":"food_info","query":"pizza"}
    "I weigh 75 kg"→{"tool":"log_weight","value":"75","unit":"kg"}
    "start push day"→{"tool":"start_workout","name":"push day"}
    "did yoga for like half an hour"→{"tool":"log_activity","name":"yoga","duration":"30"}
    "took vitamin d"→{"tool":"mark_supplement","name":"vitamin d"}
    "did I take my vitamins"→{"tool":"supplements"}
    "DEXA results"→{"tool":"body_comp"}
    "any glucose spikes"→{"tool":"glucose"}
    "how'd I sleep"→{"tool":"sleep_recovery"}
    "my hrv today"→{"tool":"sleep_recovery","query":"hrv"}
    "how's my muscle recovery"→{"tool":"exercise_info","query":"muscle recovery"}
    "set my goal to one sixty"→{"tool":"set_goal","target":"160","unit":"lbs"}
    "delete last"→{"tool":"delete_food"}
    "remove rice from lunch"→{"tool":"edit_meal","meal_period":"lunch","action":"remove","target_food":"rice"}
    "update oatmeal in breakfast to 200g"→{"tool":"edit_meal","meal_period":"breakfast","action":"update_quantity","target_food":"oatmeal","new_value":"200g"}
    "swap chicken for tofu in dinner"→{"tool":"edit_meal","meal_period":"dinner","action":"replace","target_food":"chicken","new_value":"tofu"}
    If <recent_entries> lists "42|lunch|rice|180cal|3m": "delete the rice I just logged"→{"tool":"delete_food","entry_id":"42"}
    If <recent_entries> shows two rows and user says "delete the first one"→use the id of the earlier row.
    If <recent_entries> has a 500cal row at id 7: "edit the 500 cal one to 2 servings"→{"tool":"edit_meal","entry_id":"7","action":"update_quantity","new_value":"2"}
    "when will I reach my goal weight"→{"tool":"weight_trend_prediction"}
    "how long until I hit 75kg"→{"tool":"weight_trend_prediction"}
    "did I lose weight on workout days"→{"tool":"cross_domain_insight","metric_a":"weight","metric_b":"workout_volume"}
    "glucose vs carbs last week"→{"tool":"cross_domain_insight","metric_a":"glucose_avg","metric_b":"carbs","window_days":"7"}
    "protein on lifting days vs rest"→{"tool":"cross_domain_insight","metric_a":"protein","metric_b":"workout_volume"}
    "show me my weight chart"→{"tool":"navigate_to","screen":"weight"}
    "go to sleep tab"→{"tool":"navigate_to","screen":"bodyRhythm"}
    "is it okay to take fish oil on an empty stomach"→Fish oil is generally fine with or without food.
    "log lunch"→What did you have for lunch?
    "hi"→Hi! How can I help?
    "log"→What would you like to log — food, weight, or a workout?
    If chat context shows "What did you have for lunch?" and user says "rice and dal"→{"tool":"log_food","name":"rice, dal"}
    JSON when you have enough info. Ask follow-up if details missing. Short text for chat.
    """

    // MARK: - Shared helpers

    static func extractTool(_ response: String) -> String? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              let data = String(response[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String else { return nil }
        return tool
    }

    static func classify(_ message: String, history: String = "") async -> String? {
        guard let backend = perStageGemmaBackend else { return nil }
        let userMsg = history.isEmpty ? message : "Chat:\n\(String(history.prefix(400)))\n\nUser: \(message)"
        return await backend.respond(to: userMsg, systemPrompt: systemPrompt)
    }
}

// MARK: - XCTestCase helper

extension XCTestCase {
    func assertRoutesSingleStage(
        _ query: String,
        to expectedTool: String,
        history: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        guard let response = await PerStageEvalSupport.classify(query, history: history) else {
            XCTFail("No response for '\(query)'", file: file, line: line)
            return false
        }
        let tool = PerStageEvalSupport.extractTool(response)
        let ok = tool == expectedTool
        if !ok {
            print("❌ [\(String(describing: type(of: self)))] '\(query)' → '\(tool ?? "text")' (expected '\(expectedTool)')")
        }
        return ok
    }
}
