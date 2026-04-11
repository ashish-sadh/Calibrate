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

    // MARK: - System Prompt (~150 tokens)

    static let systemPrompt = """
    Health tracker assistant. Respond with ONE JSON tool call or short text.

    Tools:
    log_food(name,servings?) — log food eaten
    food_info(query) — nutrition questions, calories left, daily summary, meal suggestions
    log_weight(value,unit?) — record weight (default lbs)
    weight_info(query?) — weight trend, progress, TDEE
    start_workout(name?) — begin workout session (empty=smart)
    log_activity(name,duration?) — log completed exercise
    exercise_info(query?) — workout history, what to train
    sleep_recovery(period?) — sleep quality, HRV, recovery
    mark_supplement(name) — mark supplement taken
    set_goal(target,unit?) — set weight goal
    delete_food(query?) — delete last food entry
    body_comp(query?) — body fat, DEXA, BMI info

    Examples:
    "log 2 eggs and toast" → {"tool":"log_food","name":"eggs, toast","servings":"2"}
    "had chicken biryani for lunch" → {"tool":"log_food","name":"chicken biryani"}
    "calories left" → {"tool":"food_info","query":"calories left"}
    "how am I doing" → {"tool":"food_info","query":"daily summary"}
    "suggest dinner" → {"tool":"food_info","query":"suggest dinner"}
    "I weigh 75 kg" → {"tool":"log_weight","value":"75","unit":"kg"}
    "weight trend" → {"tool":"weight_info","query":"trend"}
    "start push day" → {"tool":"start_workout","name":"push day"}
    "I did yoga 30 min" → {"tool":"log_activity","name":"yoga","duration":"30"}
    "took vitamin d" → {"tool":"mark_supplement","name":"vitamin d"}
    "how did I sleep" → {"tool":"sleep_recovery"}
    "sleep this week" → {"tool":"sleep_recovery","period":"week"}
    "set goal to 155" → {"tool":"set_goal","target":"155","unit":"lbs"}
    "delete last entry" → {"tool":"delete_food"}
    "body fat percentage" → {"tool":"body_comp","query":"body fat"}
    "hi" → Hi! What can I help with?
    JSON only for actions/queries. Short friendly text for greetings/chat.
    """

    // MARK: - Classify

    /// Classify user message into intent + tool call via LLM.
    /// Returns nil if LLM times out or returns non-JSON (chat response).
    static func classify(message: String, history: String) async -> ClassifiedIntent? {
        let userMessage: String
        if !history.isEmpty {
            userMessage = "Chat:\n\(String(history.prefix(200)))\n\nUser: \(message)"
        } else {
            userMessage = message
        }

        let msg = userMessage  // capture for Sendable closure
        let response = await withTimeout(seconds: 10) {
            await LocalAIService.shared.respondDirect(
                systemPrompt: systemPrompt,
                message: msg
            )
        }

        guard let response else { return nil }
        return parseResponse(response)
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

    private static func withTimeout<T: Sendable>(seconds: Int, operation: @Sendable @escaping () async -> T?) async -> T? {
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
