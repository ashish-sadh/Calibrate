import Foundation

/// LLM-driven intent classification + tool calling.
/// Replaces keyword-based ToolRanker for Gemma 4.
/// Compact prompt (~150 tokens system + examples).
@MainActor
enum IntentClassifier {

    // MARK: - Intent Types

    struct ClassifiedIntent: Sendable {
        let tool: String          // tool name or "chat"
        let params: [String: String]  // extracted parameters
        let confidence: String    // "high", "medium", "low"
    }

    /// Result of classification: either a tool call or a text response (follow-up question, greeting, etc.)
    enum ClassifyResult: Sendable {
        case toolCall(ClassifiedIntent)
        case text(String)  // LLM chose to respond with text (follow-up question, greeting, etc.)
    }

    // MARK: - System Prompt

    static let systemPrompt = """
    Health app. Reply JSON tool call or short text. Fix typos, word numbers, slang — understand messy input.
    Tools: log_food(name,servings?,calories?,protein?,carbs?,fat?) food_info(query) log_weight(value,unit?) weight_info(query?) start_workout(name?) log_activity(name,duration?) exercise_info(query?) sleep_recovery(period?) mark_supplement(name) supplements() set_goal(target,unit?) delete_food(query?) edit_meal(meal_period?,action,target_food,new_value?) body_comp() glucose() biomarkers() navigate_to(screen)
    RULES: NEVER generate health data from memory — ALWAYS call a tool. "calories in X" → food_info (NOT log_food). Use log_food only when user ate/had/logged. "log lunch"/"log breakfast"/"log dinner" alone (no food named) → ask what they had, do NOT call log_food. "daily summary"/"weekly summary" → food_info. "weight trend"/"weight history" → weight_info. "body fat/lean mass/DEXA/body composition" → body_comp. "blood sugar/blood glucose" → glucose. "fat intake/sugar intake/carb intake" → food_info. "lab results/blood work/biomarkers/cholesterol" → biomarkers. "go to [screen]"/"open [screen]" → navigate_to. supplements() queries supplement tracking — ALWAYS call supplements() for any supplement status/history question, NEVER respond with text. mark_supplement(name) logs intake ONLY when user explicitly TOOK a specific supplement (vitamin, creatine, fish oil, omega-3). "had a protein shake/smoothie/drink" is food → log_food NOT mark_supplement. "when should I take" or "what time should I take" → supplements()/text (advice, not logging). HRV/heart rate variability → sleep_recovery.
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
    "had a protein shake"→{"tool":"log_food","name":"protein shake"}
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
    "remove rice from lunch"→{"tool":"edit_meal","meal_period":"lunch","action":"remove","target_food":"rice"}
    "change chicken to 2 servings"→{"tool":"edit_meal","action":"update_quantity","target_food":"chicken","new_value":"2"}
    "update oatmeal in breakfast to 200g"→{"tool":"edit_meal","meal_period":"breakfast","action":"update_quantity","target_food":"oatmeal","new_value":"200g"}
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
    "I love eating rajma chawal"→Sounds tasty! Want to log it?
    If chat context shows "What did you have for lunch?" and user says "rice and dal"→{"tool":"log_food","name":"rice, dal"}
    If chat context shows sleep data and user says "what about last week"→{"tool":"sleep_recovery","period":"week"}
    JSON when you have enough info. Ask follow-up if details missing. Short text for chat.
    """

    // MARK: - Classify

    /// Build the user message with optional history context. Public for testing.
    nonisolated static func buildUserMessage(message: String, history: String) -> String {
        if !history.isEmpty {
            return "Chat:\n\(String(history.prefix(400)))\n\nUser: \(message)"
        }
        return message
    }

    /// Map raw LLM response string to a ClassifyResult. Public for testing.
    nonisolated static func mapResponse(_ response: String?) -> ClassifyResult? {
        guard let response else { return nil }
        if let intent = parseResponse(response) {
            return .toolCall(intent)
        }
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return .text(cleaned)
    }

    /// Classify user message into intent + tool call via LLM.
    /// Returns nil only on timeout. Text responses (follow-ups, greetings) are returned as .text.
    static func classifyFull(message: String, history: String) async -> ClassifyResult? {
        let msg = buildUserMessage(message: message, history: history)
        let response = await withTimeout(seconds: 10) {
            await LocalAIService.shared.respondDirect(
                systemPrompt: systemPrompt,
                message: msg
            )
        }
        return mapResponse(response)
    }

    /// Legacy: returns nil for text responses (backward compat)
    static func classify(message: String, history: String) async -> ClassifiedIntent? {
        guard let result = await classifyFull(message: message, history: history) else { return nil }
        if case .toolCall(let intent) = result { return intent }
        return nil
    }

    // MARK: - Parse Response

    /// Parse LLM response into intent. Public for testing. Nonisolated (pure parsing).
    nonisolated static func parseResponse(_ response: String) -> ClassifiedIntent? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to extract JSON from response
        guard let jsonStart = trimmed.firstIndex(of: "{"),
              let jsonEnd = trimmed.lastIndex(of: "}") else {
            return nil // Not a tool call — direct chat response
        }

        let jsonStr = String(trimmed[jsonStart...jsonEnd])
        guard let data = jsonStr.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String,
              !tool.isEmpty else {
            return nil
        }

        // Extract all string params
        var params: [String: String] = [:]
        for (key, value) in json where key != "tool" {
            if let str = value as? String {
                params[key] = str
            } else if let arr = value as? [String] {
                params[key] = arr.joined(separator: ", ")
            } else if let num = value as? Int {
                params[key] = "\(num)"
            } else if let num = value as? Double {
                params[key] = "\(num)"
            }
        }

        return ClassifiedIntent(
            tool: tool,
            params: params,
            confidence: json["confidence"] as? String ?? "high"
        )
    }

    // MARK: - Timeout Helper

    static func withTimeout<T: Sendable>(seconds: Int, operation: @Sendable @escaping () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}
