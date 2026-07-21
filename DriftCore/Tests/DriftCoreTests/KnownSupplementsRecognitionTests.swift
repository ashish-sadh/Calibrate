import Testing
@testable import DriftCore

/// Tier 0 — normalization and matching contracts for the curated supplement
/// recognizer. Pure logic; no database or platform services.
struct KnownSupplementsRecognitionTests {

    @Test func punctuationCaseAndWhitespaceAreNormalized() {
        let recognized = KnownSupplements.recognize(
            in: "OMEGA-3, then\n  magnesium   glycinate"
        )

        #expect(recognized == ["Omega 3", "Magnesium"])
    }

    @Test func aliasesDoNotMatchInsideLongerWords() {
        let recognized = KnownSupplements.recognize(
            in: "The ironic creativity study used biotinylated samples."
        )

        #expect(recognized.isEmpty)
    }

    @Test func resultsFollowPhraseOrderInsteadOfCatalogOrder() {
        let recognized = KnownSupplements.recognize(
            in: "Tulsi before creatine, followed by vitamin D."
        )

        #expect(recognized == ["Tulsi", "Creatine", "Vitamin D"])
    }

    @Test func repeatedAliasesReturnOneCanonicalName() {
        let recognized = KnownSupplements.recognize(
            in: "fish oil, omega3, and omega-3"
        )

        #expect(recognized == ["Omega 3"])
    }

    @Test func regionalAliasesMapToCanonicalDisplayNames() {
        let recognized = KnownSupplements.recognize(
            in: "guduchi with haldi and psyllium husk"
        )

        #expect(recognized == ["Giloy", "Turmeric", "Isabgol"])
    }
}
