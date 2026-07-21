import Testing
@testable import DriftCore

/// Tier 0 — deterministic alias normalization for training equipment.
@Suite struct TrainingProfileEquipmentNormalizationTests {
    @Test func commonAliasesAndMisspellingsMapToCatalogSlugs() {
        let cases: [(String, [String])] = [
            ("DUMBELL", ["dumbbell"]),
            ("olympic bar", ["barbell"]),
            ("power rack", ["barbell"]),
            ("pulley", ["cable"]),
            ("smith", ["machine"]),
            ("e-z", ["e-z curl bar"]),
            ("pullup bar", ["other"]),
        ]

        for (input, expected) in cases {
            #expect(TrainingProfile.normalizeEquipment(input) == expected)
        }
    }

    @Test func ballAndRecoveryAliasesRemainDistinct() {
        let cases: [(String, [String])] = [
            ("med ball", ["medicine ball"]),
            ("slam ball", ["medicine ball"]),
            ("swiss ball", ["exercise ball"]),
            ("stability ball", ["exercise ball"]),
            ("yoga ball", ["exercise ball"]),
            ("foam roller", ["foam roll"]),
        ]

        for (input, expected) in cases {
            #expect(TrainingProfile.normalizeEquipment(input) == expected)
        }
    }

    @Test func repeatedAliasesProduceOneSlugInStableCatalogOrder() {
        let input = "TRX rings dumbbells dumbell resistance bands band cable pulley"

        #expect(TrainingProfile.normalizeEquipment(input) == [
            "dumbbell", "bands", "cable", "other",
        ])
    }
}
