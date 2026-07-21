import Testing
@testable import DriftCore

/// Tier 0 — pure derived values for a recorded body weight.
@Suite struct WeightEntryLogicTests {

    @Test func weightLbsConvertsFromKilograms() {
        let entry = WeightEntry(date: "2026-07-21", weightKg: 70)

        #expect(abs(entry.weightLbs - 154.3234) < 0.000_001)
    }

    @Test func entryWithoutCompositionValuesHasNoBodyComposition() {
        let entry = WeightEntry(
            id: 42,
            date: "2026-07-21",
            weightKg: 70,
            source: "healthkit",
            createdAt: "2026-07-21T08:30:00Z",
            syncedFromHk: true
        )

        #expect(!entry.hasBodyComposition)
    }

    @Test func eachSupportedCompositionValueCountsAsBodyComposition() {
        let entries = [
            WeightEntry(date: "2026-07-21", weightKg: 70, bodyFatPct: 18.5),
            WeightEntry(date: "2026-07-21", weightKg: 70, bmi: 22.9),
            WeightEntry(date: "2026-07-21", weightKg: 70, waterPct: 56),
        ]

        for entry in entries {
            #expect(entry.hasBodyComposition)
        }
    }

    @Test func zeroCompositionValueIsStillPresent() {
        #expect(WeightEntry(date: "2026-07-21", weightKg: 70, bodyFatPct: 0).hasBodyComposition)
        #expect(WeightEntry(date: "2026-07-21", weightKg: 70, bmi: 0).hasBodyComposition)
        #expect(WeightEntry(date: "2026-07-21", weightKg: 70, waterPct: 0).hasBodyComposition)
    }
}
