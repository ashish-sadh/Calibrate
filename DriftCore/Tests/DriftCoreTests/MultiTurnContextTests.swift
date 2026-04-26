import XCTest
@testable import DriftCore

/// Deterministic multi-turn pipeline tests (no LLM): IntentClassifier message
/// builder, response parser, ConversationState topic classifier,
/// InputNormalizer. Validates the data layer *before* the LLM sees it.
///
/// LLM-backed multi-turn behavior (does Gemma 4 actually use the history we
/// build?) lives in `DriftLLMEvalMacOS/MultiTurnContextEval.swift`.
///
/// Run: `cd DriftCore && swift test --filter MultiTurnContextTests`
final class MultiTurnContextTests: XCTestCase {

    // MARK: - IntentClassifier History Window

    func testClassifierIncludesHistory() {
        let history = "Q: log lunch\nA: What did you have for lunch?"
        let msg = IntentClassifier.buildUserMessage(message: "rice and dal", history: history)
        XCTAssertTrue(msg.contains("Chat:"), "Should include Chat: prefix")
        XCTAssertTrue(msg.contains("What did you have"), "Should include assistant's question")
        XCTAssertTrue(msg.contains("User: rice and dal"), "Should include current message")
    }

    func testClassifierEmptyHistory() {
        let msg = IntentClassifier.buildUserMessage(message: "log 2 eggs", history: "")
        XCTAssertEqual(msg, "log 2 eggs", "No history = raw message")
        XCTAssertFalse(msg.contains("Chat:"), "No Chat: prefix without history")
    }

    func testClassifierHistoryWindow400Chars() {
        // History up to 400 chars should be preserved
        let longHistory = String(repeating: "Q: test\nA: reply\n", count: 30) // ~540 chars
        let msg = IntentClassifier.buildUserMessage(message: "next", history: longHistory)
        // After Chat:\n prefix and 400 char truncation, msg should be reasonable
        let chatPortion = msg.components(separatedBy: "\n\nUser:").first ?? ""
        // The "Chat:\n" prefix is 5 chars, so content should be ~400
        XCTAssertLessThanOrEqual(chatPortion.count, 410, "History should be capped near 400 chars")
    }

    func testClassifierHistoryPreservesRecentContext() {
        // The most recent exchange should appear in history (it's at the end)
        let history = "Q: how many calories left\nA: You have 800 calories remaining\nQ: and protein?\nA: 45g of 120g target"
        let msg = IntentClassifier.buildUserMessage(message: "what about carbs", history: history)
        XCTAssertTrue(msg.contains("protein"), "Recent protein exchange should be visible")
        XCTAssertTrue(msg.contains("what about carbs"), "Current query should be present")
    }

    // MARK: - Classifier Response Parsing for Multi-Turn

    func testClassifierParsesMealFollowUp() {
        // When classifier sees history "What did you have?" and user says "rice and dal",
        // the LLM should return a log_food tool call
        let response = #"{"tool":"log_food","name":"rice, dal"}"#
        let result = IntentClassifier.parseResponse(response)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.tool, "log_food")
        XCTAssertEqual(result?.params["name"], "rice, dal")
    }

    func testClassifierParsesQuantityFollowUp() {
        // "How many eggs?" → "3"
        let response = #"{"tool":"log_food","name":"eggs","servings":"3"}"#
        let result = IntentClassifier.parseResponse(response)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.params["servings"], "3")
    }

    func testClassifierParsesFollowUpQuestion() {
        // Classifier may ask a follow-up instead of executing a tool
        let response = "How many eggs did you have?"
        let result = IntentClassifier.mapResponse(response)
        if case .text(let text) = result {
            XCTAssertTrue(text.contains("eggs"), "Follow-up should mention the food")
        } else {
            XCTFail("Should parse as text response, not tool call")
        }
    }

    // MARK: - ConversationState Topic Tracking

    @MainActor
    func testTopicClassifiesFood() {
        let topic = ConversationState.shared.classifyTopic("I had 2 eggs for breakfast")
        XCTAssertEqual(topic, .food, "'I had 2 eggs' should classify as food topic")
    }

    @MainActor
    func testTopicClassifiesWeight() {
        let topic = ConversationState.shared.classifyTopic("how's my weight trend")
        XCTAssertEqual(topic, .weight, "'weight trend' should classify as weight topic")
    }

    @MainActor
    func testTopicClassifiesExercise() {
        let topic = ConversationState.shared.classifyTopic("what should I train today")
        XCTAssertEqual(topic, .exercise, "'train today' should classify as exercise topic")
    }

    @MainActor
    func testTopicClassifiesSleep() {
        let topic = ConversationState.shared.classifyTopic("how did I sleep last night")
        XCTAssertEqual(topic, .sleep, "'sleep last night' should classify as sleep topic")
    }

    @MainActor
    func testTopicPersistsAcrossReset() {
        // lastTopic should survive a reset (for multi-turn continuity)
        ConversationState.shared.classifyTopic("I had 2 eggs")
        let topicBefore = ConversationState.shared.lastTopic
        ConversationState.shared.reset()
        let topicAfter = ConversationState.shared.lastTopic
        XCTAssertEqual(topicBefore, topicAfter, "lastTopic should persist across reset")
    }

    // MARK: - Conversation History Builder

    func testBuildConversationHistoryFormat() {
        // Verify the Q/A compact format matches what IntentClassifier expects
        // The format should be parseable by the LLM
        let sampleHistory = "Q: log lunch\nA: What did you have for lunch?"
        let msg = IntentClassifier.buildUserMessage(message: "rice", history: sampleHistory)
        // Should contain the Q/A exchange followed by the new user message
        XCTAssertTrue(msg.hasPrefix("Chat:\n"), "Should start with Chat: prefix")
        XCTAssertTrue(msg.hasSuffix("User: rice"), "Should end with current user message")
    }

    // MARK: - Multi-Turn Scenario: Meal Logging

    func testMealLoggingScenarioHistory() {
        // Simulate: "log lunch" → AI: "What did you have?" → "rice and dal"
        let history = "Q: log lunch\nA: What did you have for lunch?"
        let msg = IntentClassifier.buildUserMessage(message: "rice and dal", history: history)

        // Verify the full message has enough context for the LLM
        XCTAssertTrue(msg.contains("log lunch"), "Should see original request")
        XCTAssertTrue(msg.contains("What did you have"), "Should see follow-up question")
        XCTAssertTrue(msg.contains("rice and dal"), "Should see the answer")

        // The classifier prompt example handles this case:
        // "If chat context shows 'What did you have for lunch?' and user says 'rice and dal'
        //  →{"tool":"log_food","name":"rice, dal"}"
    }

    func testTopicSwitchScenarioHistory() {
        // Simulate: food chat → "how's my weight"
        let history = "Q: log 2 eggs\nA: Logged 2 eggs (140 cal)\nQ: calories left\nA: 800 remaining"
        let msg = IntentClassifier.buildUserMessage(message: "how's my weight going", history: history)

        // Even though history is about food, the new query is about weight
        XCTAssertTrue(msg.contains("weight"), "Current query should be visible for topic switch")
    }

    func testProteinFollowUpScenarioHistory() {
        // Simulate: "how am I doing" → summary → "what about protein?"
        let history = "Q: how am I doing\nA: You've eaten 1200 of 2000 calories today"
        let msg = IntentClassifier.buildUserMessage(message: "what about protein", history: history)

        // "what about protein?" is a continuation that needs history
        XCTAssertTrue(msg.contains("calories"), "Should see prior nutrition context")
        XCTAssertTrue(msg.contains("protein"), "Should see follow-up query")
    }

    // MARK: - InputNormalizer + Multi-Turn

    func testNormalizerPreservesMultiTurnMeaning() {
        // Voice follow-ups should normalize without losing meaning
        let followUps = [
            ("umm rice and dal", "rice and dal"),
            ("uh like 3 eggs", "3 eggs"),
            ("oh and also some toast", "also some toast"),
        ]
        for (input, expectedContains) in followUps {
            let normalized = InputNormalizer.normalize(input)
            XCTAssertTrue(normalized.lowercased().contains(expectedContains),
                "'\(input)' → '\(normalized)' should contain '\(expectedContains)'")
        }
    }

    func testNormalizerDoesNotBreakShortFollowUps() {
        // Very short follow-ups (common in multi-turn) should not be destroyed
        let shortFollowUps = ["yes", "no", "3", "rice", "sure", "ok"]
        for input in shortFollowUps {
            let normalized = InputNormalizer.normalize(input)
            XCTAssertFalse(normalized.isEmpty, "Short input '\(input)' should not become empty")
        }
    }
}
