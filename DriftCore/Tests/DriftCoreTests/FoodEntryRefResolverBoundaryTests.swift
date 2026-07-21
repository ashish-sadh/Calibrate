import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — pure name-resolution boundaries without database or shared-state setup.
@Suite struct FoodEntryRefResolverBoundaryTests {
    private func entry(id: Int64, name: String) -> ConversationState.FoodEntryRef {
        .init(
            id: id,
            name: name,
            mealType: "snack",
            calories: 100,
            loggedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test @MainActor func longerPhraseContainingEntryNameResolves() {
        let window = [entry(id: 41, name: "Greek Yogurt")]

        let resolved = FoodEntryRefResolver.resolveByName(
            "please edit greek yogurt",
            in: window
        )

        #expect(resolved == 41)
    }

    @Test @MainActor func exactNameRemainsAmbiguousWhenItContainsAnotherEntryName() {
        let window = [
            entry(id: 10, name: "Rice"),
            entry(id: 20, name: "Rice Bowl"),
        ]

        #expect(FoodEntryRefResolver.resolveByName("Rice Bowl", in: window) == nil)
    }

    @Test @MainActor func whitespaceOnlyPhraseDoesNotResolve() {
        let window = [entry(id: 7, name: "Banana")]

        #expect(FoodEntryRefResolver.resolveByName(" \n\t ", in: window) == nil)
    }

    @Test @MainActor func emptyWindowDoesNotResolve() {
        #expect(FoodEntryRefResolver.resolveByName("oatmeal", in: []) == nil)
    }
}
