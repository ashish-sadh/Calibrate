import Testing
@testable import DriftCore

/// Tier 0 — deterministic boundaries around database-backed spell correction.
@Suite struct SpellCorrectServiceBoundaryTests {

    @Test func singleEditMisspellingFuzzyMatchesBundledFoodWord() {
        #expect(SpellCorrectService.correct("applf") == "apple")
    }

    @Test func knownFoodPrefixIsNotOverCorrected() {
        #expect(SpellCorrectService.correct("chick") == "chick")
    }

    @Test func synonymKeyIsLeftForSynonymExpansion() {
        #expect(SpellCorrectService.correct("murgh") == "murgh")
        #expect(SpellCorrectService.expandSynonyms("murgh") == "chicken")
    }

    @Test func unknownWordWithoutCloseFoodMatchPreservesOriginalText() {
        #expect(SpellCorrectService.correct("Zorbulate") == "Zorbulate")
    }

    @Test func correctionAndSynonymExpansionComposeAcrossWords() {
        let corrected = SpellCorrectService.correct("chiken aloo")

        #expect(corrected == "chicken aloo")
        #expect(SpellCorrectService.expandSynonyms(corrected) == "chicken potato")
    }
}
