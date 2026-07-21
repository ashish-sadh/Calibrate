import Testing
@testable import DriftCore

/// Tier 0 — deterministic biomarker range classification and normalization.
struct BiomarkerDefinitionLogicTests {

    private func definition(absoluteLow: Double = 0, absoluteHigh: Double = 200) -> BiomarkerDefinition {
        BiomarkerDefinition(
            id: "test_marker",
            name: "Test Marker",
            category: "Test",
            unit: "units",
            optimalLow: 80,
            optimalHigh: 120,
            sufficientLow: 60,
            sufficientHigh: 140,
            absoluteLow: absoluteLow,
            absoluteHigh: absoluteHigh,
            description: "",
            whyItMatters: "",
            relationships: "",
            howToImprove: "",
            healthMetrics: "",
            impactCategories: []
        )
    }

    @Test func optimalRangeIncludesBothBoundaries() {
        let marker = definition()

        #expect(marker.status(for: 80) == .optimal)
        #expect(marker.status(for: 100) == .optimal)
        #expect(marker.status(for: 120) == .optimal)
    }

    @Test func sufficientRangeExcludesValuesOutsideItsBoundaries() {
        let marker = definition()

        #expect(marker.status(for: 60) == .sufficient)
        #expect(marker.status(for: 79.9) == .sufficient)
        #expect(marker.status(for: 120.1) == .sufficient)
        #expect(marker.status(for: 140) == .sufficient)
        #expect(marker.status(for: 59.9) == .outOfRange)
        #expect(marker.status(for: 140.1) == .outOfRange)
    }

    @Test func normalizedPositionInterpolatesAndClampsToAbsoluteRange() {
        let marker = definition()

        #expect(marker.normalizedPosition(for: -50) == 0)
        #expect(marker.normalizedPosition(for: 0) == 0)
        #expect(marker.normalizedPosition(for: 50) == 0.25)
        #expect(marker.normalizedPosition(for: 100) == 0.5)
        #expect(marker.normalizedPosition(for: 200) == 1)
        #expect(marker.normalizedPosition(for: 250) == 1)
    }

    @Test func normalizedPositionUsesMidpointForInvalidAbsoluteRange() {
        #expect(definition(absoluteLow: 100, absoluteHigh: 100).normalizedPosition(for: 25) == 0.5)
        #expect(definition(absoluteLow: 200, absoluteHigh: 100).normalizedPosition(for: 250) == 0.5)
    }
}
