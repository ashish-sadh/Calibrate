import Foundation
import Testing
@testable import Drift

// MARK: - ConversationHistoryBuilder

@Test @MainActor func historyBuilderReturnsEmptyForNoMessages() {
    Preferences.conversationHistoryEnabled = true
    let result = ConversationHistoryBuilder.build(messages: [])
    #expect(result.isEmpty)
}

@Test @MainActor func historyBuilderReturnsEmptyWhenFlagOff() {
    let original = Preferences.conversationHistoryEnabled
    Preferences.conversationHistoryEnabled = false
    defer { Preferences.conversationHistoryEnabled = original }

    let msgs = [
        AIChatViewModel.ChatMessage(role: .user, text: "hi"),
        AIChatViewModel.ChatMessage(role: .assistant, text: "Hello")
    ]
    #expect(ConversationHistoryBuilder.build(messages: msgs).isEmpty)
}

@Test @MainActor func historyBuilderFormatsQAPairs() {
    Preferences.conversationHistoryEnabled = true
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
    let msgs = [AIChatViewModel.ChatMessage(role: .user, text: "hi")]
    let result = ConversationHistoryBuilder.build(messages: msgs, maxTokens: 400)
    #expect(result == "Q: hi")
}
