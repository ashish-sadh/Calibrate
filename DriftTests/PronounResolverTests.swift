import Foundation
import Testing
@testable import Drift

/// Cross-domain pronoun resolution (#241). Rewrites pronoun-bearing
/// *queries* (not actions) into explicit references to the last-touched
/// entry in any domain.

@MainActor
private func foodContext(_ name: String, minutesAgo: Int = 1) -> ConversationState.LastEntryContext {
    .init(domain: .food, summary: name,
          loggedAt: Date(timeIntervalSinceNow: -TimeInterval(minutesAgo * 60)))
}

@MainActor
private func weightContext(_ summary: String, minutesAgo: Int = 1) -> ConversationState.LastEntryContext {
    .init(domain: .weight, summary: summary,
          loggedAt: Date(timeIntervalSinceNow: -TimeInterval(minutesAgo * 60)))
}

// MARK: - Positive cases: food → nutrition query

@Test @MainActor func thatAfterFoodLogResolvesToMealName() {
    let rewritten = PronounResolver.resolve(
        message: "how much protein is in that?",
        context: foodContext("150g chicken"))
    #expect(rewritten == "how much protein is in 150g chicken?")
}

@Test @MainActor func itAfterFoodLogResolvesToMealName() {
    let rewritten = PronounResolver.resolve(
        message: "how many calories in it?",
        context: foodContext("biryani"))
    #expect(rewritten == "how many calories in biryani?")
}

@Test @MainActor func thisOneResolvesMultiwordPronoun() {
    let rewritten = PronounResolver.resolve(
        message: "what's the fat in this one?",
        context: foodContext("paneer"))
    #expect(rewritten?.contains("paneer") == true)
    #expect(rewritten?.contains("this one") == false)
}

// MARK: - Positive cases: weight → goal/trend query

@Test @MainActor func amIUnderGoalResolvesWithWeightContext() {
    let rewritten = PronounResolver.resolve(
        message: "am i under goal with that?",
        context: weightContext("180 lbs"))
    #expect(rewritten == "am i under goal with 180 lbs?")
}

@Test @MainActor func isThatGoodAfterWeightLog() {
    let rewritten = PronounResolver.resolve(
        message: "is that good?",
        context: weightContext("75 kg"))
    #expect(rewritten == "is 75 kg good?")
}

// MARK: - Negative cases — action verbs stay untouched

@Test @MainActor func logThatActionIsNotRewritten() {
    let rewritten = PronounResolver.resolve(
        message: "log that again",
        context: foodContext("chicken"))
    #expect(rewritten == nil, "food logging pronouns go through the VM's food resolver")
}

@Test @MainActor func deleteItActionIsNotRewritten() {
    let rewritten = PronounResolver.resolve(
        message: "delete it",
        context: foodContext("chicken"))
    #expect(rewritten == nil)
}

@Test @MainActor func addThisIsNotRewritten() {
    let rewritten = PronounResolver.resolve(
        message: "add this to breakfast",
        context: foodContext("eggs"))
    #expect(rewritten == nil)
}

// MARK: - Negative cases — no pronoun / no context

@Test @MainActor func nonQueryMessageIsNotRewritten() {
    // No question mark, no query cue, no action verb — don't rewrite
    let rewritten = PronounResolver.resolve(
        message: "yeah I know that",
        context: foodContext("chicken"))
    #expect(rewritten == nil)
}

@Test @MainActor func messageWithoutPronounNotRewritten() {
    let rewritten = PronounResolver.resolve(
        message: "how much protein in chicken?",
        context: foodContext("rice"))
    #expect(rewritten == nil)
}

@Test @MainActor func nilContextReturnsNil() {
    let rewritten = PronounResolver.resolve(
        message: "how much protein is in that?",
        context: nil)
    #expect(rewritten == nil)
}

// MARK: - Whole-word matching — don't mangle compound words

@Test @MainActor func pronounInsideLargerWordNotTouched() {
    // "thats" and "its" substrings shouldn't be captured by a whole-word
    // match — regression against a naive `String.replacingOccurrences`.
    let rewritten = PronounResolver.resolve(
        message: "thats cool",
        context: foodContext("chicken"))
    #expect(rewritten == nil)
}

@Test @MainActor func questionWithMultiplePronounsOnlyReplacesFirst() {
    let rewritten = PronounResolver.resolve(
        message: "how much is that and is that healthy?",
        context: foodContext("chicken"))
    // First replacement wins — second "that" remains so user can still
    // reference context later. Downstream LLM handles the rest.
    #expect(rewritten?.hasPrefix("how much is chicken and is that healthy?") == true)
}

// MARK: - ConversationState integration

@Test @MainActor func pushRecentEntryAutoPopulatesLastAnyEntry() {
    let state = ConversationState.shared
    state.reset()
    state.pushRecentEntry(.init(id: 1, name: "rice and dal",
                                 mealType: "lunch", calories: 450,
                                 loggedAt: Date()))
    #expect(state.lastAnyEntry?.domain == .food)
    #expect(state.lastAnyEntry?.summary == "rice and dal")
}

@Test @MainActor func recordLastEntryRejectsEmptySummary() {
    let state = ConversationState.shared
    state.reset()
    state.recordLastEntry(domain: .weight, summary: "   ")
    #expect(state.lastAnyEntry == nil)
}

@Test @MainActor func freshLastEntryRespectsTTL() {
    let state = ConversationState.shared
    state.reset()
    let stale = Date(timeIntervalSinceNow: -(ConversationState.recentEntriesTTL + 60))
    state.recordLastEntry(domain: .food, summary: "chicken", at: stale)
    #expect(state.lastAnyEntry != nil, "stored")
    #expect(state.freshLastEntry() == nil, "stale — outside TTL")
}

@Test @MainActor func resetClearsLastAnyEntry() {
    let state = ConversationState.shared
    state.recordLastEntry(domain: .weight, summary: "75 kg")
    state.reset()
    #expect(state.lastAnyEntry == nil)
}
