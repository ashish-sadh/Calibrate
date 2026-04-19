import Foundation
import Testing
@testable import Drift

// MARK: - ConversationHistoryBuilder

@Test @MainActor func historyBuilderReturnsEmptyForNoMessages() {
    Preferences.conversationHistoryEnabled = true
    ConversationState.shared.reset()
    let result = ConversationHistoryBuilder.build(messages: [])
    #expect(result.isEmpty)
}

@Test @MainActor func historyBuilderReturnsEmptyWhenFlagOff() {
    let original = Preferences.conversationHistoryEnabled
    Preferences.conversationHistoryEnabled = false
    defer { Preferences.conversationHistoryEnabled = original }
    ConversationState.shared.reset()

    let msgs = [
        AIChatViewModel.ChatMessage(role: .user, text: "hi"),
        AIChatViewModel.ChatMessage(role: .assistant, text: "Hello")
    ]
    #expect(ConversationHistoryBuilder.build(messages: msgs).isEmpty)
}

@Test @MainActor func historyBuilderFormatsQAPairs() {
    Preferences.conversationHistoryEnabled = true
    ConversationState.shared.reset()
    let msgs = [
        AIChatViewModel.ChatMessage(role: .user, text: "log lunch"),
        AIChatViewModel.ChatMessage(role: .assistant, text: "What did you have for lunch?")
    ]
    let result = ConversationHistoryBuilder.build(messages: msgs)
    #expect(result.contains("Q: log lunch"))
    #expect(result.contains("A: What did you have for lunch?"))
    // Newest turn must appear last so the LLM sees the latest assistant turn
    // adjacent to the current user query.
    let qIdx = result.range(of: "Q: log lunch")?.lowerBound
    let aIdx = result.range(of: "A: What did")?.lowerBound
    #expect(qIdx != nil && aIdx != nil && qIdx! < aIdx!)
}

@Test @MainActor func historyBuilderRespectsTokenBudget() {
    Preferences.conversationHistoryEnabled = true
    ConversationState.shared.reset()
    // 6 turns of 240-char "A:" answers — total well above a 100-token
    // (~400 char) budget. Builder should drop oldest turns.
    let bigText = String(repeating: "x", count: 240)
    let msgs = (0..<6).map { i -> AIChatViewModel.ChatMessage in
        AIChatViewModel.ChatMessage(
            role: i % 2 == 0 ? .user : .assistant,
            text: "\(i) \(bigText)")
    }
    let result = ConversationHistoryBuilder.build(messages: msgs, maxTokens: 100)
    let budgetChars = 100 * ConversationHistoryBuilder.charsPerToken
    #expect(result.count <= budgetChars)
    // Oldest turns dropped: "0 …" should NOT appear, newest "5 …" should.
    #expect(!result.contains("0 xxxxxxxx"))
    #expect(result.contains("5 xxxxxxxx"))
}

@Test @MainActor func historyBuilderTruncatesLongSingleMessage() {
    Preferences.conversationHistoryEnabled = true
    ConversationState.shared.reset()
    // 1000-char assistant answer — per-message cap is 60 tokens ≈ 240 chars.
    let huge = String(repeating: "y", count: 1000)
    let msgs = [
        AIChatViewModel.ChatMessage(role: .user, text: "tell me"),
        AIChatViewModel.ChatMessage(role: .assistant, text: huge)
    ]
    let result = ConversationHistoryBuilder.build(messages: msgs, maxTokens: 400)
    let perMsgChars = ConversationHistoryBuilder.perMessageTokens * ConversationHistoryBuilder.charsPerToken
    // "A: " prefix + truncated body
    let assistantLine = result.components(separatedBy: "\n").last ?? ""
    #expect(assistantLine.count <= perMsgChars + 3)
}

@Test @MainActor func historyBuilderKeepsRecentWhenWindowExceedsSix() {
    Preferences.conversationHistoryEnabled = true
    ConversationState.shared.reset()
    // 10 turns: builder only considers the last 6.
    let msgs = (0..<10).map { i -> AIChatViewModel.ChatMessage in
        AIChatViewModel.ChatMessage(
            role: i % 2 == 0 ? .user : .assistant,
            text: "turn\(i)")
    }
    let result = ConversationHistoryBuilder.build(messages: msgs, maxTokens: 400)
    #expect(!result.contains("turn0"))
    #expect(!result.contains("turn3"))
    #expect(result.contains("turn9"))
    #expect(result.contains("turn4"))
}

@Test @MainActor func historyBuilderSingleShortMessageFits() {
    Preferences.conversationHistoryEnabled = true
    ConversationState.shared.reset()
    let msgs = [AIChatViewModel.ChatMessage(role: .user, text: "hi")]
    let result = ConversationHistoryBuilder.build(messages: msgs, maxTokens: 400)
    #expect(result == "Q: hi")
}

// MARK: - Last Tool Summary (#184)

@Test @MainActor func historyBuilderPrependsFreshToolSummary() {
    Preferences.conversationHistoryEnabled = true
    let state = ConversationState.shared
    state.reset()
    // Simulate: user sent turn 1 → tool captured → user sent turn 2.
    state.beginUserTurn()                                         // turn 1
    state.captureToolSummary("Logged 200g rice (260 cal, 56g carbs, 5g protein, 0g fat)")
    state.beginUserTurn()                                         // turn 2 — asking follow-up

    let msgs = [
        AIChatViewModel.ChatMessage(role: .user, text: "log 200g rice"),
        AIChatViewModel.ChatMessage(role: .assistant, text: "Logged rice.")
    ]
    let result = ConversationHistoryBuilder.build(messages: msgs)
    #expect(result.contains("[LAST ACTION:"))
    #expect(result.contains("260 cal"))
    #expect(result.contains("56g carbs"))
    // Must come BEFORE the Q/A block so the LLM sees it as priming context.
    let lastActionIdx = result.range(of: "[LAST ACTION:")?.lowerBound
    let qIdx = result.range(of: "Q: log 200g rice")?.lowerBound
    #expect(lastActionIdx != nil && qIdx != nil && lastActionIdx! < qIdx!)

    state.reset()
}

@Test @MainActor func historyBuilderSkipsStaleToolSummary() {
    Preferences.conversationHistoryEnabled = true
    let state = ConversationState.shared
    state.reset()
    // Tool captured on turn 1, but 3 more user turns have elapsed → stale.
    state.beginUserTurn()                                         // turn 1
    state.captureToolSummary("Logged 200g rice (260 cal)")
    state.beginUserTurn()                                         // turn 2
    state.beginUserTurn()                                         // turn 3
    state.beginUserTurn()                                         // turn 4

    let msgs = [AIChatViewModel.ChatMessage(role: .user, text: "hello")]
    let result = ConversationHistoryBuilder.build(messages: msgs)
    #expect(!result.contains("[LAST ACTION:"))
    #expect(!result.contains("260 cal"))

    state.reset()
}

@Test @MainActor func historyBuilderOmitsToolSummaryWhenNeverCaptured() {
    Preferences.conversationHistoryEnabled = true
    let state = ConversationState.shared
    state.reset()
    state.beginUserTurn()

    let msgs = [AIChatViewModel.ChatMessage(role: .user, text: "hi")]
    let result = ConversationHistoryBuilder.build(messages: msgs)
    #expect(!result.contains("[LAST ACTION:"))
    #expect(result == "Q: hi")

    state.reset()
}

@Test @MainActor func historyBuilderCapsLastActionPrefixLength() {
    Preferences.conversationHistoryEnabled = true
    let state = ConversationState.shared
    state.reset()
    // Inject an oversize summary; builder must cap it before prepending.
    state.beginUserTurn()
    let giant = String(repeating: "z", count: 2000)
    state.captureToolSummary(giant)
    state.beginUserTurn()

    let msgs = [AIChatViewModel.ChatMessage(role: .user, text: "hi")]
    let result = ConversationHistoryBuilder.build(messages: msgs, maxTokens: 400)
    let totalBudgetChars = 400 * ConversationHistoryBuilder.charsPerToken
    #expect(result.count <= totalBudgetChars)
    // Q/A must still fit alongside the prefix — "Q: hi" is in there.
    #expect(result.contains("Q: hi"))

    state.reset()
}
