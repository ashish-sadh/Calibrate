import Foundation
@testable import DriftCore
import Testing

private func pronounBoundaryContext(_ summary: String = "150g chicken") -> ConversationState.LastEntryContext {
    .init(domain: .food, summary: summary, loggedAt: Date())
}

@Test @MainActor func queryCueResolvesPronounWithoutQuestionMark() {
    let rewritten = PronounResolver.resolve(
        message: "protein in that",
        context: pronounBoundaryContext())

    #expect(rewritten == "protein in 150g chicken")
}

@Test @MainActor func thatOneIsReplacedAsSinglePronoun() {
    let rewritten = PronounResolver.resolve(
        message: "what is the protein in that one?",
        context: pronounBoundaryContext("paneer tikka"))

    #expect(rewritten == "what is the protein in paneer tikka?")
}

@Test(
    "Remaining mutation actions are not rewritten",
    arguments: ["track", "remove", "edit", "undo", "update", "change"]
)
@MainActor
func remainingActionPrefixesAreNotRewritten(_ action: String) {
    let rewritten = PronounResolver.resolve(
        message: "\(action) it?",
        context: pronounBoundaryContext())

    #expect(rewritten == nil)
}

@Test(
    "Pronoun substrings inside words are not rewritten",
    arguments: [
        "how many items are there?",
        "what is iteration count?",
    ]
)
@MainActor
func pronounSubstringsInQueriesAreNotRewritten(_ message: String) {
    let rewritten = PronounResolver.resolve(
        message: message,
        context: pronounBoundaryContext())

    #expect(rewritten == nil)
}
