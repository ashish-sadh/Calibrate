import Testing
@testable import DriftCore

/// Tier 0 — deterministic metadata contracts for downloadable model tiers.
@Suite struct AIModelTierContractTests {
    @Test func displayNamesIdentifyEachModelFamily() {
        #expect(AIModelTier.small.displayName == "SmolLM2")
        #expect(AIModelTier.large.displayName == "Gemma 4")
    }

    @Test func smallTierUsesTheExpectedLocalModelManifest() throws {
        let tier = AIModelTier.small
        let file = try #require(tier.modelFiles.first)

        #expect(tier.modelFiles.count == 1)
        #expect(tier.downloadSizeMB == 368)
        #expect(file.name == "smollm2-360m-instruct-q8_0.gguf")
        #expect(file.sizeMB == 368)
        #expect(file.customURL == nil)
    }

    @Test func tierDownloadSizesMatchTheirFileManifests() {
        for tier in [AIModelTier.small, .large] {
            let manifestSize = tier.modelFiles.reduce(0) { $0 + $1.sizeMB }
            #expect(manifestSize == tier.downloadSizeMB)
        }
    }
}
