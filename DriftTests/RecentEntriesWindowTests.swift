import Foundation
import Testing
@testable import Drift

/// Unit tests for the recent-entries rolling window (#227).
/// Covers: LRU cap, TTL expiry, ordinal resolution, context block format.

// MARK: - LRU cap

@Test @MainActor func recentEntriesCapEvictsOldest() {
    let state = ConversationState.shared
    state.reset()
    for i in 1...(ConversationState.recentEntriesCap + 3) {
        state.pushRecentEntry(.init(
            id: Int64(i), name: "food\(i)", mealType: "lunch",
            calories: 100, loggedAt: Date()
        ))
    }
    #expect(state.recentEntries.count == ConversationState.recentEntriesCap)
    #expect(state.recentEntries.first?.id == 4)
    #expect(state.recentEntries.last?.id == Int64(ConversationState.recentEntriesCap + 3))
}

@Test @MainActor func recentEntriesDuplicateIdUpdatesInPlace() {
    let state = ConversationState.shared
    state.reset()
    state.pushRecentEntry(.init(id: 42, name: "rice", mealType: "lunch", calories: 150, loggedAt: Date()))
    state.pushRecentEntry(.init(id: 7, name: "dal", mealType: "lunch", calories: 200, loggedAt: Date()))
    state.pushRecentEntry(.init(id: 42, name: "rice", mealType: "lunch", calories: 300, loggedAt: Date()))
    #expect(state.recentEntries.count == 2)
    // id 42 should be last (newest position) since it was re-pushed
    #expect(state.recentEntries.last?.id == 42)
    #expect(state.recentEntries.last?.calories == 300)
}

@Test @MainActor func recentEntriesDropByIdRemoves() {
    let state = ConversationState.shared
    state.reset()
    state.pushRecentEntry(.init(id: 1, name: "a", mealType: "snack", calories: 50, loggedAt: Date()))
    state.pushRecentEntry(.init(id: 2, name: "b", mealType: "snack", calories: 60, loggedAt: Date()))
    state.dropRecentEntry(id: 1)
    #expect(state.recentEntries.count == 1)
    #expect(state.recentEntries.first?.id == 2)
}

// MARK: - TTL expiry

@Test @MainActor func recentEntriesTTLExpiresOldRows() {
    let state = ConversationState.shared
    state.reset()
    let now = Date()
    let stale = now.addingTimeInterval(-(ConversationState.recentEntriesTTL + 60))
    state.pushRecentEntry(.init(id: 1, name: "old", mealType: "lunch", calories: 100, loggedAt: stale))
    state.pushRecentEntry(.init(id: 2, name: "fresh", mealType: "lunch", calories: 150, loggedAt: now))
    state.pruneExpiredRecentEntries(now: now)
    #expect(state.recentEntries.count == 1)
    #expect(state.recentEntries.first?.id == 2)
}

// MARK: - Ordinal resolution

@Test @MainActor func ordinalResolvesLastAndFirst() {
    let state = ConversationState.shared
    state.reset()
    let now = Date()
    state.pushRecentEntry(.init(id: 10, name: "first-in", mealType: "breakfast", calories: 100, loggedAt: now))
    state.pushRecentEntry(.init(id: 20, name: "middle", mealType: "lunch", calories: 200, loggedAt: now))
    state.pushRecentEntry(.init(id: 30, name: "newest", mealType: "dinner", calories: 300, loggedAt: now))
    #expect(state.resolveOrdinal("first")?.id == 10)
    #expect(state.resolveOrdinal("last")?.id == 30)
    #expect(state.resolveOrdinal("just logged")?.id == 30)
    #expect(state.resolveOrdinal("most recent")?.id == 30)
}

@Test @MainActor func ordinalResolvesSecondToLast() {
    let state = ConversationState.shared
    state.reset()
    let now = Date()
    state.pushRecentEntry(.init(id: 1, name: "a", mealType: "lunch", calories: 100, loggedAt: now))
    state.pushRecentEntry(.init(id: 2, name: "b", mealType: "lunch", calories: 200, loggedAt: now))
    state.pushRecentEntry(.init(id: 3, name: "c", mealType: "lunch", calories: 300, loggedAt: now))
    #expect(state.resolveOrdinal("second to last")?.id == 2)
    #expect(state.resolveOrdinal("penultimate")?.id == 2)
    #expect(state.resolveOrdinal("third to last")?.id == 1)
}

@Test @MainActor func ordinalNumericPositions() {
    let state = ConversationState.shared
    state.reset()
    let now = Date()
    for i in 1...4 {
        state.pushRecentEntry(.init(id: Int64(i * 10), name: "f\(i)", mealType: "lunch", calories: i * 100, loggedAt: now))
    }
    #expect(state.resolveOrdinal("second")?.id == 20)
    #expect(state.resolveOrdinal("2nd")?.id == 20)
    #expect(state.resolveOrdinal("third")?.id == 30)
    #expect(state.resolveOrdinal("4th")?.id == 40)
}

@Test @MainActor func ordinalReturnsNilWhenOutOfRange() {
    let state = ConversationState.shared
    state.reset()
    state.pushRecentEntry(.init(id: 1, name: "only", mealType: "lunch", calories: 100, loggedAt: Date()))
    #expect(state.resolveOrdinal("second to last") == nil)
    #expect(state.resolveOrdinal("5th") == nil)
    #expect(state.resolveOrdinal("not an ordinal") == nil)
}

@Test @MainActor func ordinalReturnsNilOnEmptyWindow() {
    let state = ConversationState.shared
    state.reset()
    #expect(state.resolveOrdinal("last") == nil)
    #expect(state.resolveOrdinal("first") == nil)
}

// MARK: - Context block formatting

@Test @MainActor func contextBlockFormatsRowsWithRelativeTime() {
    let state = ConversationState.shared
    state.reset()
    let now = Date()
    let fiveMinAgo = now.addingTimeInterval(-5 * 60)
    state.pushRecentEntry(.init(id: 42, name: "rice", mealType: "lunch", calories: 180, loggedAt: fiveMinAgo))
    let block = state.recentEntriesContextBlock(now: now)
    #expect(block != nil)
    #expect(block!.contains("<recent_entries>"))
    #expect(block!.contains("</recent_entries>"))
    #expect(block!.contains("42|lunch|rice|180cal|5m"))
}

@Test @MainActor func contextBlockNilWhenEmpty() {
    let state = ConversationState.shared
    state.reset()
    #expect(state.recentEntriesContextBlock() == nil)
}

// MARK: - IntentClassifier context injection

@Test func needsRecentEntriesMatchesDeleteEditKeywords() {
    #expect(IntentClassifier.needsRecentEntries("delete the rice"))
    #expect(IntentClassifier.needsRecentEntries("remove the first one"))
    #expect(IntentClassifier.needsRecentEntries("edit the 500 cal one"))
    #expect(IntentClassifier.needsRecentEntries("update my breakfast to 2 servings"))
    #expect(IntentClassifier.needsRecentEntries("replace chicken with tofu"))
    #expect(IntentClassifier.needsRecentEntries("the one I just logged"))
}

@Test func needsRecentEntriesFalseForLogOrInfo() {
    #expect(!IntentClassifier.needsRecentEntries("log 2 eggs"))
    #expect(!IntentClassifier.needsRecentEntries("calories in banana"))
    #expect(!IntentClassifier.needsRecentEntries("how am I doing"))
    #expect(!IntentClassifier.needsRecentEntries("I had biryani"))
}

// Tracked in failing-queries.md: "No, I had the other chicken instead" — correction-as-replacement.
// "instead" / "no, i had" / "actually i had" are not in deleteEditTriggers so recent entries
// context is never injected and the LLM creates a duplicate log instead of replacing.
// Fix: add these triggers to IntentClassifier.deleteEditTriggers (tier 0).
@Test(.disabled("tracked: informal correction triggers — failing-queries.md"))
func needsRecentEntriesForInformalCorrections() {
    #expect(IntentClassifier.needsRecentEntries("No, I had the other chicken instead"))
    #expect(IntentClassifier.needsRecentEntries("Actually I had salmon, not chicken"))
    #expect(IntentClassifier.needsRecentEntries("Wait, it was 2 eggs not 3"))
}

@Test func composeUserMessageOrdersRecentBeforeHistory() {
    let msg = IntentClassifier.composeUserMessage(
        message: "delete the rice",
        history: "Q: log rice\nA: Logged.",
        recentBlock: "<recent_entries>\n42|lunch|rice|180cal|3m\n</recent_entries>"
    )
    guard let recentIdx = msg.range(of: "<recent_entries>")?.lowerBound,
          let chatIdx = msg.range(of: "Chat:")?.lowerBound,
          let userIdx = msg.range(of: "User:")?.lowerBound else {
        Issue.record("Missing expected sections in composed message")
        return
    }
    #expect(recentIdx < chatIdx)
    #expect(chatIdx < userIdx)
}

@Test func composeUserMessageOmitsRecentWhenNil() {
    let msg = IntentClassifier.composeUserMessage(
        message: "log eggs",
        history: "",
        recentBlock: nil
    )
    #expect(!msg.contains("<recent_entries>"))
    // Preserves pre-#227 bare-message shape when neither context applies.
    #expect(msg == "log eggs")
}

@Test func composeUserMessagePrependsRecentWhenHistoryEmpty() {
    let msg = IntentClassifier.composeUserMessage(
        message: "delete the rice",
        history: "",
        recentBlock: "<recent_entries>\n42|lunch|rice|180cal|3m\n</recent_entries>"
    )
    #expect(msg.contains("<recent_entries>"))
    #expect(msg.contains("User: delete the rice"))
}
