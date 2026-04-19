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

    static let systemPrompt = """
    Health app. Reply JSON tool call or short text. Fix typos, word numbers, slang — understand messy input.
    Tools: log_food(name,servings?,calories?,protein?,carbs?,fat?) food_info(query) log_weight(value,unit?) weight_info(query?) start_workout(name?) log_activity(name,duration?) exercise_info(query?) sleep_recovery(period?) mark_supplement(name) supplements() set_goal(target,unit?) delete_food(query?) edit_meal(meal_period?,action,target_food,new_value?) body_comp() glucose() biomarkers() navigate_to(screen)
    RULES: NEVER generate health data from memory — ALWAYS call a tool. "calories in X" → food_info (NOT log_food). Use log_food only when user ate/had/logged. "log lunch"/"log breakfast"/"log dinner" alone (no food named) → ask what they had, do NOT call log_food. "daily summary"/"weekly summary" → food_info. "weight trend"/"weight history" → weight_info. "body fat/lean mass/DEXA/body composition" → body_comp. "blood sugar/blood glucose" → glucose. "fat intake/sugar intake/carb intake" → food_info. "lab results/blood work/biomarkers/cholesterol" → biomarkers. "go to [screen]"/"open [screen]" → navigate_to. supplements() queries supplement tracking — ALWAYS call supplements() for any supplement status/history question, NEVER respond with text. mark_supplement(name) logs intake when user says they TOOK/HAD something. HRV/heart rate variability → sleep_recovery.
    ASK vs GUESS: when user names a concrete food/supplement/exercise/weight/screen, act — DO NOT ask back. Only ask a one-line clarifying question when the query has no object to act on (bare verbs like "log", "track", "add") or when two tools fit equally well.
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
    "what about protein?"→{"tool":"food_info","query":"protein"}
    "log 2 eggs"→{"tool":"log_food","name":"egg","servings":"2"}
    "had a protein shake"→{"tool":"log_food","name":"protein shake"}
    "I weigh 75 kg"→{"tool":"log_weight","value":"75","unit":"kg"}
    "am I on track for my goal"→{"tool":"weight_info","query":"goal progress"}
    "start push day"→{"tool":"start_workout","name":"push day"}
    "did yoga for like half an hour"→{"tool":"log_activity","name":"yoga","duration":"30"}
    "took vitamin d"→{"tool":"mark_supplement","name":"vitamin d"}
    "did I take my vitamins"→{"tool":"supplements"}
    "what's my body fat"→{"tool":"body_comp"}
    "DEXA results"→{"tool":"body_comp"}
    "any glucose spikes"→{"tool":"glucose"}
    "how's my blood sugar"→{"tool":"glucose"}
    "show my biomarkers"→{"tool":"biomarkers"}
    "how'd I sleep"→{"tool":"sleep_recovery"}
    "my hrv today"→{"tool":"sleep_recovery","query":"hrv"}
    "how's my muscle recovery"→{"tool":"exercise_info","query":"muscle recovery"}
    "set my goal to one sixty"→{"tool":"set_goal","target":"160","unit":"lbs"}
    "delete last"→{"tool":"delete_food"}
    "remove rice from lunch"→{"tool":"edit_meal","meal_period":"lunch","action":"remove","target_food":"rice"}
    "update oatmeal in breakfast to 200g"→{"tool":"edit_meal","meal_period":"breakfast","action":"update_quantity","target_food":"oatmeal","new_value":"200g"}
    "replace rice with quinoa in lunch"→{"tool":"edit_meal","meal_period":"lunch","action":"replace","target_food":"rice","new_value":"quinoa"}
    "show me my weight chart"→{"tool":"navigate_to","screen":"weight"}
    "go to food tab"→{"tool":"navigate_to","screen":"food"}
    "open exercise"→{"tool":"navigate_to","screen":"exercise"}
    "go to sleep tab"→{"tool":"navigate_to","screen":"bodyRhythm"}
    "open supplements"→{"tool":"navigate_to","screen":"supplements"}
    "show dashboard"→{"tool":"navigate_to","screen":"dashboard"}
    "go to glucose"→{"tool":"navigate_to","screen":"glucose"}
    "open biomarkers"→{"tool":"navigate_to","screen":"biomarkers"}
    "is it okay to take fish oil on an empty stomach"→Fish oil is generally fine with or without food, though some prefer taking it with meals.
    "should I take creatine before or after workout"→Either works — post-workout is slightly favored but timing matters less than consistency.
    "log lunch"→What did you have for lunch?
    "hi"→Hi! How can I help?
    "i just love breakfast"→That's great! What did you have?
    "I love eating rajma chawal"→Sounds tasty! Want to log it?
    "log"→What would you like to log — food, weight, or a workout?
    "track"→What should I track?
    "add"→What would you like to add?
    "how much"→How much what — calories, protein, carbs, or something else?
    If chat context shows "What did you have for lunch?" and user says "rice and dal"→{"tool":"log_food","name":"rice, dal"}
    If chat context shows sleep data and user says "what about last week"→{"tool":"sleep_recovery","period":"week"}
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
