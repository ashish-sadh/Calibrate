import Foundation
import Testing
@testable import DriftCore

/// Tier 0 — deterministic boundary coverage for biomarker trend classification.
@Suite struct BiomarkerInsightsTrendBoundaryTests {
    private let definition = BiomarkerDefinition(
        id: "test_marker",
        name: "Test Marker",
        category: "Test",
        unit: "units",
        optimalLow: 80,
        optimalHigh: 120,
        sufficientLow: 60,
        sufficientHigh: 140,
        absoluteLow: 0,
        absoluteHigh: 200,
        description: "",
        whyItMatters: "",
        relationships: "",
        howToImprove: "",
        healthMetrics: "",
        impactCategories: []
    )

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
    }

    @Test func unsortedReadingsUseChronologicalEndpointsAndPreviousStatus() throws {
        let trend = try #require(BiomarkerInsights.trend(
            biomarkerId: definition.id,
            results: [(day(2), 150), (day(0), 100), (day(1), 130)],
            definition: definition
        ))

        #expect(trend.firstValue == 100)
        #expect(trend.latestValue == 150)
        #expect(trend.absoluteChange == 50)
        #expect(trend.previousStatus == .sufficient)
        #expect(trend.latestStatus == .outOfRange)
        #expect(trend.direction == .rising)
    }

    @Test func threePercentCutoffSeparatesStableFromDirectionalMovement() throws {
        let belowCutoff = try #require(BiomarkerInsights.trend(
            biomarkerId: definition.id,
            results: [(day(0), 100), (day(1), 102.99)],
            definition: definition
        ))
        let atCutoff = try #require(BiomarkerInsights.trend(
            biomarkerId: definition.id,
            results: [(day(0), 100), (day(1), 103)],
            definition: definition
        ))

        #expect(belowCutoff.direction == .stable)
        #expect(atCutoff.direction == .rising)
    }

    @Test func zeroBaselineProducesAbsoluteTrendWithoutPercentChange() throws {
        let trend = try #require(BiomarkerInsights.trend(
            biomarkerId: definition.id,
            results: [(day(0), 0), (day(1), 5)],
            definition: definition
        ))

        #expect(trend.direction == .rising)
        #expect(trend.absoluteChange == 5)
        #expect(trend.percentChange == nil)
        #expect(!trend.narrative.contains("%"))
    }

    @Test func sufficientValuesWarnNearTheEdgeTheyAreApproaching() throws {
        let rising = try #require(BiomarkerInsights.trend(
            biomarkerId: definition.id,
            results: [(day(0), 125), (day(1), 135)],
            definition: definition
        ))
        let falling = try #require(BiomarkerInsights.trend(
            biomarkerId: definition.id,
            results: [(day(0), 75), (day(1), 70)],
            definition: definition
        ))

        #expect(rising.approachingEdge)
        #expect(rising.narrative.contains("upper limit"))
        #expect(falling.approachingEdge)
        #expect(falling.narrative.contains("lower limit"))
    }
}
