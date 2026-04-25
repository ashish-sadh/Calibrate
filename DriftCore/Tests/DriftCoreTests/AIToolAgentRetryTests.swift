import Foundation
@testable import DriftCore
import Testing

/// Auto-retry on empty/incomplete extraction (#240).
/// Unit-level coverage for the `shouldRetryClassify` decision and the
/// per-tool `hasRequiredParams` matrix. Integration lift on a live
/// gold set is measured separately (opt-in, requires LLM runs).

// MARK: - shouldRetryClassify — positive cases (retry fires)

@Test func retriesWhenFirstResultIsNil() {
    #expect(AIToolAgent.shouldRetryClassify(nil) == true,
            "nil = timeout or empty LLM response — always retry")
}

@Test func retriesWhenLogFoodMissingName() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "log_food", params: [:], confidence: "low"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == true)
}

@Test func retriesWhenLogWeightMissingValue() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "log_weight", params: ["unit": "kg"], confidence: "low"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == true)
}

@Test func retriesWhenMarkSupplementMissingName() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "mark_supplement", params: [:], confidence: "high"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == true)
}

@Test func retriesWhenEditMealMissingAction() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "edit_meal", params: ["meal_period": "lunch"], confidence: "medium"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == true)
}

@Test func retriesWhenFoodInfoMissingQueryAndName() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "food_info", params: [:], confidence: "low"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == true)
}

@Test func retriesWhenLogFoodNameIsWhitespaceOnly() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "log_food", params: ["name": "   "], confidence: "low"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == true,
            "whitespace-only name is effectively empty")
}

@Test func retriesWhenToolHasParenthesesSuffix() {
    // LLM sometimes emits "log_food()" — stripping parens must still match target set
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "log_food()", params: [:], confidence: "low"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == true)
}

// MARK: - shouldRetryClassify — negative cases (no retry)

@Test func noRetryWhenLogFoodHasName() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "log_food", params: ["name": "chicken"], confidence: "high"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == false)
}

@Test func noRetryWhenLogWeightHasValue() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "log_weight", params: ["value": "75"], confidence: "high"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == false)
}

@Test func noRetryWhenFoodInfoHasQuery() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "food_info", params: ["query": "calories in rice"], confidence: "high"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == false)
}

@Test func noRetryWhenFoodInfoHasNameButNoQuery() {
    // food_info accepts EITHER query OR name — either alone is enough
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "food_info", params: ["name": "apple"], confidence: "high"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == false)
}

@Test func noRetryWhenNonTargetTool() {
    // exercise_info, sleep_recovery, etc. are NOT target tools — no retry
    // even when params are empty, because gold-set tail is in the 5 above
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "exercise_info", params: [:], confidence: "low"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == false)
}

@Test func noRetryWhenNavigateTool() {
    let intent = IntentClassifier.ClassifiedIntent(
        tool: "navigate_to", params: [:], confidence: "low"
    )
    #expect(AIToolAgent.shouldRetryClassify(.toolCall(intent)) == false)
}

@Test func noRetryWhenTextResponse() {
    // LLM chose to respond with text (follow-up question, greeting) — keep it
    #expect(AIToolAgent.shouldRetryClassify(.text("Hi! How can I help?")) == false)
}

@Test func noRetryWhenTextResponseEmpty() {
    // Even empty-text — retry fires only on nil, not on empty-text (LLM
    // chose text, that's its prerogative; don't second-guess).
    #expect(AIToolAgent.shouldRetryClassify(.text("")) == false)
}

// MARK: - hasRequiredParams — matrix

@Test func hasRequiredParams_logFood_nameOnly() {
    #expect(AIToolAgent.hasRequiredParams(tool: "log_food", params: ["name": "rice"]) == true)
}

@Test func hasRequiredParams_logFood_emptyParams() {
    #expect(AIToolAgent.hasRequiredParams(tool: "log_food", params: [:]) == false)
}

@Test func hasRequiredParams_editMeal_actionOnly() {
    #expect(AIToolAgent.hasRequiredParams(tool: "edit_meal", params: ["action": "remove"]) == true)
}

@Test func hasRequiredParams_logWeight_valueOnly() {
    #expect(AIToolAgent.hasRequiredParams(tool: "log_weight", params: ["value": "75"]) == true)
}

@Test func hasRequiredParams_markSupplement_nameOnly() {
    #expect(AIToolAgent.hasRequiredParams(tool: "mark_supplement", params: ["name": "vitamin d"]) == true)
}

@Test func hasRequiredParams_foodInfo_queryOrName() {
    #expect(AIToolAgent.hasRequiredParams(tool: "food_info", params: ["query": "x"]) == true)
    #expect(AIToolAgent.hasRequiredParams(tool: "food_info", params: ["name": "x"]) == true)
    #expect(AIToolAgent.hasRequiredParams(tool: "food_info", params: [:]) == false)
}

@Test func hasRequiredParams_nonTargetTool_defaultsTrue() {
    // Non-target tools don't go through retry, but the helper shouldn't
    // spuriously demand params for them — default to "has what it needs".
    #expect(AIToolAgent.hasRequiredParams(tool: "supplements", params: [:]) == true)
    #expect(AIToolAgent.hasRequiredParams(tool: "glucose", params: [:]) == true)
}

// MARK: - Literal-hint composition

@Test func literalHintAppendsToUserMessage() {
    let msg = IntentClassifier.composeUserMessage(
        message: "had biryani",
        history: "",
        recentBlock: nil,
        literalHint: "Be literal."
    )
    #expect(msg.contains("Hint: Be literal."))
    #expect(msg.contains("User: had biryani"))
    #expect(msg.contains("Be literal.") && msg.contains("had biryani"))
}

@Test func literalHintSkippedWhenNil() {
    // No recent-entries, no history, no literal hint → bare message
    let msg = IntentClassifier.composeUserMessage(
        message: "log 2 eggs", history: "", recentBlock: nil, literalHint: nil
    )
    #expect(msg == "log 2 eggs")
}

@Test func literalHintOrder_hintBeforeUser() {
    // Hint must precede the user line so Gemma reads it as priming
    let msg = IntentClassifier.composeUserMessage(
        message: "x", history: "", recentBlock: nil, literalHint: "H"
    )
    let hintRange = msg.range(of: "Hint:")
    let userRange = msg.range(of: "User:")
    #expect(hintRange != nil && userRange != nil)
    if let h = hintRange?.lowerBound, let u = userRange?.lowerBound {
        #expect(h < u, "Hint must appear before User line")
    }
}

@Test func retryTargetTools_includesFiveExpected() {
    // Regression: if someone changes the target-tool set, this should
    // fail loudly. Ticket spec says log_food, edit_meal, log_weight,
    // mark_supplement, food_info — verify all five.
    let expected: Set<String> = ["log_food", "edit_meal", "log_weight", "mark_supplement", "food_info"]
    #expect(AIToolAgent.retryTargetTools == expected)
}
