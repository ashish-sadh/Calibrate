import Testing
@testable import DriftCore

/// Tier 0 — pure display formatting for supplement dosage metadata.
@Suite struct SupplementDosageDisplayTests {
    @Test func singleDailyDoseOmitsFrequencySuffix() {
        let supplement = Supplement(
            name: "Vitamin D3",
            dosage: "2000",
            unit: "IU"
        )

        #expect(supplement.dosageDisplay == "2000 IU")
    }

    @Test func multipleDailyDosesIncludeFrequencySuffix() {
        let supplement = Supplement(
            name: "Magnesium",
            dosage: "200",
            unit: "mg",
            dailyDoses: 3
        )

        #expect(supplement.dosageDisplay == "200 mg × 3/day")
    }

    @Test func missingDosageProducesEmptyDisplay() {
        let supplement = Supplement(name: "Creatine", unit: "g")

        #expect(supplement.dosageDisplay.isEmpty)
    }

    @Test func missingUnitProducesEmptyDisplay() {
        let supplement = Supplement(name: "Creatine", dosage: "5")

        #expect(supplement.dosageDisplay.isEmpty)
    }
}
