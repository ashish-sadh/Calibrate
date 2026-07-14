import Testing
import Foundation
@testable import DriftCore

/// Tier 0 — the personalized biomarker narrative/trajectory/pattern engine.
/// Pure logic, no DB, no device.
struct BiomarkerInsightsTests {

    private func def(_ id: String) -> BiomarkerDefinition {
        BiomarkerKnowledgeBase.byId[id]!
    }
    private func day(_ offset: Int) -> Date {
        // Fixed epoch base so tests are deterministic (no Date() — banned in
        // DriftCore anyway). Ordering is all that matters.
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
    }

    // MARK: - Trend

    @Test func risingMarkerCrossingOutOfRangeNarrates() {
        let ldl = def("ldl_cholesterol")
        let trend = BiomarkerInsights.trend(
            biomarkerId: "ldl_cholesterol",
            results: [(day(0), 96), (day(90), 118), (day(180), 135)],
            definition: ldl)
        let t = try! #require(trend)
        #expect(t.direction == .rising)
        #expect(t.firstValue == 96 && t.latestValue == 135)
        #expect(t.readingCount == 3)
        #expect(t.latestStatus == .outOfRange)
        #expect(t.narrative.contains("rose"))
        #expect(t.narrative.contains("outside the healthy range"))
    }

    @Test func fallingIntoOptimalIsEncouraging() {
        let ldl = def("ldl_cholesterol")
        let t = try! #require(BiomarkerInsights.trend(
            biomarkerId: "ldl_cholesterol",
            results: [(day(0), 150), (day(90), 95)],
            definition: ldl))
        #expect(t.direction == .falling)
        #expect(t.latestStatus == .optimal)
        #expect(t.narrative.contains("optimal"))
    }

    @Test func smallMoveIsStable() {
        let ferr = def("ferritin")
        let t = try! #require(BiomarkerInsights.trend(
            biomarkerId: "ferritin",
            results: [(day(0), 100), (day(90), 101.5)],
            definition: ferr))
        #expect(t.direction == .stable)
        #expect(t.narrative.contains("held"))
    }

    @Test func singleReadingHasNoTrend() {
        #expect(BiomarkerInsights.trend(biomarkerId: "ferritin", results: [(day(0), 50)], definition: def("ferritin")) == nil)
    }

    @Test func approachingEdgeEarlyWarning() {
        // Total cholesterol optimal 120–200; rising to 195 from 150 while still
        // "optimal" should flag approaching the upper edge.
        let tc = def("total_cholesterol")
        let t = try! #require(BiomarkerInsights.trend(
            biomarkerId: "total_cholesterol",
            results: [(day(0), 150), (day(90), 195)],
            definition: tc))
        #expect(t.latestStatus == .optimal)
        #expect(t.approachingEdge == true)
        #expect(t.narrative.contains("trending toward"))
    }

    @Test func inRangeStableDoesNotWarn() {
        let tc = def("total_cholesterol")
        let t = try! #require(BiomarkerInsights.trend(
            biomarkerId: "total_cholesterol",
            results: [(day(0), 160), (day(90), 162)],
            definition: tc))
        #expect(t.approachingEdge == false)
    }

    // MARK: - Report deltas

    @Test func reportDeltasRankAndScoreImprovement() {
        let deltas = BiomarkerInsights.reportDeltas(
            current: [("ldl_cholesterol", 110), ("hdl_cholesterol", 62), ("ferritin", 40)],
            previous: [("ldl_cholesterol", 150), ("hdl_cholesterol", 55), ("ferritin", 40)])
        // ferritin unchanged → excluded.
        #expect(deltas.count == 2)
        // LDL 150→110 is the biggest relative move → first.
        #expect(deltas.first?.biomarkerId == "ldl_cholesterol")
        let ldl = deltas.first { $0.biomarkerId == "ldl_cholesterol" }!
        #expect(ldl.change == -40)
        #expect(ldl.improved == true)   // moved toward optimal midpoint
    }

    // MARK: - Patterns

    @Test func ironDeficiencyPatternFiresWithCorroboration() {
        let patterns = BiomarkerInsights.patterns(latest: [
            "ferritin": 18, "mcv": 76, "rdw": 15.5, "hemoglobin": 15.0])
        let iron = try! #require(patterns.first { $0.id == "iron_deficiency" })
        #expect(iron.severity == .concern)
        #expect(iron.markerIds.contains("ferritin"))
        #expect(iron.markerIds.contains("mcv"))
    }

    @Test func lowFerritinAloneIsWatchNotConcern() {
        let patterns = BiomarkerInsights.patterns(latest: ["ferritin": 22, "mcv": 90, "rdw": 13])
        let iron = try! #require(patterns.first { $0.id == "iron_deficiency" })
        #expect(iron.severity == .watch)
        #expect(iron.markerIds == ["ferritin"])
    }

    @Test func metabolicPatternNeedsBothLipids() {
        // High TG alone should NOT fire the metabolic pattern.
        #expect(BiomarkerInsights.patterns(latest: ["triglycerides": 200]).contains { $0.id == "metabolic_syndrome" } == false)
        // High TG + low HDL fires; adding pre-diabetic HbA1c escalates.
        let p = BiomarkerInsights.patterns(latest: ["triglycerides": 200, "hdl_cholesterol": 38, "hba1c": 5.9])
        let metabolic = try! #require(p.first { $0.id == "metabolic_syndrome" })
        #expect(metabolic.severity == .concern)
        #expect(metabolic.markerIds.contains("hba1c"))
    }

    @Test func hypothyroidPatternDistinguishesSubclinical() {
        let sub = BiomarkerInsights.patterns(latest: ["thyroid_tsh": 6.0, "free_t4": 1.1])
        #expect(try! #require(sub.first { $0.id == "hypothyroid" }).detail.contains("subclinical"))
    }

    @Test func healthyPanelProducesNoPatterns() {
        let patterns = BiomarkerInsights.patterns(latest: [
            "ferritin": 80, "hdl_cholesterol": 60, "triglycerides": 90,
            "ldl_cholesterol": 90, "thyroid_tsh": 1.8, "hs_crp": 0.5, "hba1c": 5.1])
        #expect(patterns.isEmpty)
    }
}
