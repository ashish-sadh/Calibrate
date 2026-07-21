import Testing
@testable import DriftCore

/// Tier 0 — deterministic glucose-spike tool output; no DB or glucose device.
@Suite struct GlucoseSpikeAnalysisFormattingTests {

    private func food(_ name: String, count: Int, average: Double) -> GlucoseAnalyticsService.FoodSpikeRecord {
        .init(foodName: name, spikeCount: count, avgDeltaMgdl: average)
    }

    @Test func noDetectedSpikesReportsSteadyMeals() {
        let output = GlucoseSpikeAnalysisTool.format(
            foods: [], spikeCount: 0, readingCount: 18, windowDays: 14
        )

        #expect(output == "No post-meal glucose spikes detected in the last 14 days (18 readings). Keep it up — your meals appear to be keeping glucose steady.")
    }

    @Test func unrankedSpikesExplainObservationMinimumWithCorrectPluralization() {
        let singular = GlucoseSpikeAnalysisTool.format(
            foods: [], spikeCount: 1, readingCount: 7, windowDays: 30
        )
        let plural = GlucoseSpikeAnalysisTool.format(
            foods: [], spikeCount: 3, readingCount: 12, windowDays: 30
        )

        #expect(singular == "Detected 1 glucose spike but each food had fewer than 2 observations. Log more meals to see patterns.")
        #expect(plural == "Detected 3 glucose spikes but each food had fewer than 2 observations. Log more meals to see patterns.")
    }

    @Test func rankedFoodLineRoundsAverageAndPluralizesObservations() {
        let output = GlucoseSpikeAnalysisTool.format(
            foods: [food("white rice", count: 2, average: 42.6)],
            spikeCount: 2,
            readingCount: 24,
            windowDays: 21
        )

        #expect(output.contains("Meals linked to glucose spikes (last 21d, 24 readings, threshold >30 mg/dL):"))
        #expect(output.contains("• white rice: +43 mg/dL avg spike (2 observations)"))
        #expect(output.hasSuffix("Tip: try smaller portions or pairing with protein/fat to blunt the spike."))
    }

    @Test func rankedOutputCapsFoodsAtFiveAndReportsOverflow() {
        let foods = (1...7).map { food("food \($0)", count: $0, average: Double(30 + $0)) }
        let output = GlucoseSpikeAnalysisTool.format(
            foods: foods, spikeCount: 28, readingCount: 80, windowDays: 90
        )

        for index in 1...5 {
            #expect(output.contains("• food \(index):"))
        }
        #expect(!output.contains("• food 6:"))
        #expect(!output.contains("• food 7:"))
        #expect(output.contains("…and 2 more"))
    }
}
