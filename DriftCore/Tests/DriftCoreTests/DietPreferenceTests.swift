import Testing
@testable import DriftCore

/// Tier 0 — deterministic macro-distribution constants and display copy.
@Suite struct DietPreferenceTests {
    @Test func macroProfilesMatchTheirPublishedTargets() {
        let expected: [(DietPreference, proteinPerKg: Double, fatFraction: Double)] = [
            (.balanced, 1.6, 0.30),
            (.highProtein, 2.2, 0.25),
            (.lowCarb, 1.8, 0.45),
            (.lowFat, 1.4, 0.20),
            (.custom, 1.6, 0.30),
        ]

        for (preference, proteinPerKg, fatFraction) in expected {
            #expect(preference.proteinPerKg == proteinPerKg)
            #expect(preference.fatCalorieFraction == fatFraction)
        }
    }

    @Test func displayNamesCoverEveryPreference() {
        let expected: [(DietPreference, String)] = [
            (.balanced, "Balanced"),
            (.highProtein, "High Protein"),
            (.lowCarb, "Low Carb"),
            (.lowFat, "Low Fat"),
            (.custom, "Custom"),
        ]

        #expect(expected.map(\.0) == DietPreference.allCases)
        for (preference, displayName) in expected {
            #expect(preference.displayName == displayName)
        }
    }

    @Test func subtitlesDescribeTheConfiguredMacroProfile() {
        #expect(DietPreference.balanced.subtitle == "30% fat, 1.6 g/kg protein, flexible")
        #expect(DietPreference.highProtein.subtitle == "2.2 g/kg protein, muscle-focused")
        #expect(DietPreference.lowCarb.subtitle == "45% fat, fewer carbs, keto-friendly")
        #expect(DietPreference.lowFat.subtitle == "20% fat, higher carbs, endurance-friendly")
        #expect(DietPreference.custom.subtitle == "Set your own protein, carbs & fat in grams")
    }
}
