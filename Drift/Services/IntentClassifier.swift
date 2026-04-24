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

    static var systemPrompt: String = """
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

    // MARK: - Classify

    /// Trigger tokens that switch on recent-entries context injection. Kept
    /// narrow to avoid leaking the window into unrelated turns where the
    /// tokens would just waste budget.
    nonisolated static let deleteEditTriggers: [String] = [
        "delete", "remove", "undo", "edit", "change", "update",
        "replace", "swap", "the one", "the first", "the second",
        "the last", "the 500", "just logged", "just added",
        "instead", "actually i had", "no, i had", "no i had"
    ]

    /// Build the user message with optional history context. Public for
    /// testing — keeps the pre-#227 signature for deterministic callers.
    /// The MainActor-aware variant below injects recent-entries context.
    nonisolated static func buildUserMessage(message: String, history: String) -> String {
        composeUserMessage(message: message, history: history, recentBlock: nil)
    }

    /// MainActor variant used by the live pipeline. Prepends the recent-
    /// entries block when the message looks like a delete/edit turn AND
    /// the window has rows. Optional `literalHint` is used by the #240
    /// auto-retry path to nudge the extractor toward a more literal read.
    @MainActor
    static func buildContextualUserMessage(
        message: String, history: String, literalHint: String? = nil
    ) -> String {
        let recentBlock = needsRecentEntries(message)
            ? ConversationState.shared.recentEntriesContextBlock()
            : nil
        return composeUserMessage(
            message: message, history: history,
            recentBlock: recentBlock, literalHint: literalHint
        )
    }

    /// Pure composer — deterministic, test-friendly. Order of precedence:
    /// `<recent_entries>` → `Chat:` → `User:`. Falls back to the bare
    /// message when neither recent-entries nor history applies, preserving
    /// the pre-#227 prompt shape for unaffected turns.
    nonisolated static func composeUserMessage(
        message: String, history: String, recentBlock: String?, literalHint: String? = nil
    ) -> String {
        if recentBlock == nil && history.isEmpty && literalHint == nil { return message }
        var parts: [String] = []
        if let recentBlock { parts.append(recentBlock) }
        if !history.isEmpty { parts.append("Chat:\n\(String(history.prefix(400)))") }
        if let literalHint { parts.append("Hint: \(literalHint)") }
        parts.append("User: \(message)")
        return parts.joined(separator: "\n\n")
    }

    /// Heuristic: does this message plausibly reference a recent entry?
    nonisolated static func needsRecentEntries(_ message: String) -> Bool {
        let lower = message.lowercased()
        return deleteEditTriggers.contains(where: { lower.contains($0) })
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
    /// `literalHint` (optional) is appended to the user message and is used by
    /// the #240 auto-retry to nudge the extractor toward a more literal read.
    static func classifyFull(
        message: String, history: String, literalHint: String? = nil
    ) async -> ClassifyResult? {
        let msg = buildContextualUserMessage(
            message: message, history: history, literalHint: literalHint
        )
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
