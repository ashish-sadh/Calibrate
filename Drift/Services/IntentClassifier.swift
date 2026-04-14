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

    // MARK: - System Prompt (~150 tokens)

    static let systemPrompt = """
    Health app. Reply JSON tool call or short text. Fix typos, word numbers, slang — understand messy input.
    Tools: log_food(name,servings?,calories?,protein?,carbs?,fat?) food_info(query) log_weight(value,unit?) weight_info(query?) start_workout(name?) log_activity(name,duration?) exercise_info(query?) sleep_recovery(period?) mark_supplement(name) set_goal(target,unit?) delete_food(query?) body_comp(query?) navigate_to(screen)
    "log 2 eggs and toast"→{"tool":"log_food","name":"eggs, toast","servings":"2"}
    "had biryani"→{"tool":"log_food","name":"biryani"}
    "I had 2 to 3 banans"→{"tool":"log_food","name":"banana","servings":"3"}
    "chipotle bowl 3000 cal 30p 45c 67f"→{"tool":"log_food","name":"chipotle bowl","calories":"3000","protein":"30","carbs":"45","fat":"67"}
    "calories left"→{"tool":"food_info","query":"calories left"}
    "how am I doing"→{"tool":"food_info","query":"daily summary"}
    "what about protein?"→{"tool":"food_info","query":"protein"}
    "I weigh 75 kg"→{"tool":"log_weight","value":"75","unit":"kg"}
    "weight trend"→{"tool":"weight_info","query":"trend"}
    "start push day"→{"tool":"start_workout","name":"push day"}
    "did yoga for like half an hour"→{"tool":"log_activity","name":"yoga","duration":"30"}
    "took vitamin d"→{"tool":"mark_supplement","name":"vitamin d"}
    "how'd I sleep"→{"tool":"sleep_recovery"}
    "how's my muscle recovery"→{"tool":"exercise_info","query":"muscle recovery"}
    "set my goal to one sixty"→{"tool":"set_goal","target":"160","unit":"lbs"}
    "delete last"→{"tool":"delete_food"}
    "show me my weight chart"→{"tool":"navigate_to","screen":"weight"}
    "go to food tab"→{"tool":"navigate_to","screen":"food"}
    "open exercise"→{"tool":"navigate_to","screen":"exercise"}
    "log lunch"→What did you have for lunch?
    "add my dinner"→What did you have for dinner?
    "hi"→Hi! How can I help?
    "i just love breakfast"→That's great! What did you have?
    "i love eating healthy"→Nice! Want to log something?
    If chat context shows "What did you have for lunch?" and user says "rice and dal"→{"tool":"log_food","name":"rice, dal"}
    JSON when you have enough info. Ask follow-up if details missing. Short text for chat.
    """

    // MARK: - Classify

    /// Build the user message with optional history context. Public for testing.
    nonisolated static func buildUserMessage(message: String, history: String) -> String {
        if !history.isEmpty {
            return "Chat:\n\(String(history.prefix(200)))\n\nUser: \(message)"
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
