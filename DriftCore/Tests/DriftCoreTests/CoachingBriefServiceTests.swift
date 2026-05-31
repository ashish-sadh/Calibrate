import Foundation
@testable import DriftCore
import Testing

// MARK: - Fixtures (pure — no DB, no MainActor)

private func makeAlert(_ title: String, isPositive: Bool = false, dismissKey: String? = nil) -> BehaviorInsight {
    BehaviorInsight(icon: "x", title: title, detail: "detail of \(title)", isPositive: isPositive, dismissKey: dismissKey)
}

private func makePattern(_ a: String, _ b: String, r: Double = 0.5, summary: String = "summary") -> CrossDomainPattern {
    CrossDomainPattern(metricA: a, metricB: b, r: r, n: 20, windowDays: 30, summary: summary)
}

private func toolSignal(_ id: String) -> BriefSignal {
    BriefSignal(id: id, source: .tool, title: "Tool \(id)", detail: "tool detail", goalDirection: .neutral)
}

// MARK: - Ranking

@Test func rankDedupCapOrdersBySourcePriorityRegardlessOfInputOrder() {
    // Fed in reverse priority order; output must still rank alert > pattern > tool.
    let signals = [
        toolSignal("t1"),
        BriefSignal(id: "p1", source: .pattern, title: "P", detail: "d", goalDirection: .neutral),
        BriefSignal(id: "a1", source: .alert, title: "A", detail: "d", goalDirection: .against),
    ]
    let ranked = CoachingBriefService.rankDedupCap(signals)
    #expect(ranked.map(\.source) == [.alert, .pattern, .tool])
    #expect(ranked.map(\.id) == ["a1", "p1", "t1"])
}

@Test func rankDedupCapKeepsSourceInternalOrderViaIndexTiebreak() {
    // Two same-source signals keep their incoming order (explicit index tiebreak, not sort stability).
    let signals = [
        BriefSignal(id: "a1", source: .alert, title: "first", detail: "d", goalDirection: .against),
        BriefSignal(id: "a2", source: .alert, title: "second", detail: "d", goalDirection: .against),
    ]
    #expect(CoachingBriefService.rankDedupCap(signals).map(\.id) == ["a1", "a2"])
}

// MARK: - Dedup

@Test func dedupKeepsHighestPriorityFirstWinnerOnIdCollision() {
    // Same id on a tool and an alert — the alert (higher priority, sorted first) survives.
    let signals = [
        toolSignal("dup"),
        BriefSignal(id: "dup", source: .alert, title: "alertWins", detail: "d", goalDirection: .against),
    ]
    let ranked = CoachingBriefService.rankDedupCap(signals)
    #expect(ranked.count == 1)
    #expect(ranked.first?.source == .alert)
    #expect(ranked.first?.title == "alertWins")
}

// MARK: - 3-cap

@Test func rankDedupCapCapsAtThree() {
    let signals = (1...6).map { toolSignal("t\($0)") }
    let ranked = CoachingBriefService.rankDedupCap(signals)
    #expect(ranked.count == 3)
    #expect(ranked.map(\.id) == ["t1", "t2", "t3"])
}

@Test func buildBriefInputCapsAtThreeAcrossSources() {
    let brief = CoachingBriefService.buildBriefInput(
        alerts: [makeAlert("A1"), makeAlert("A2")],
        patterns: [makePattern("weight", "protein"), makePattern("carbs", "glucose_avg")],
        toolSignals: [toolSignal("weight-trend")],
        dataDayCount: 10
    )
    #expect(brief.signals.count == 3)
    #expect(brief.signals.map(\.source) == [.alert, .alert, .pattern]) // alerts win the cap
    #expect(!brief.isThinData)
}

// MARK: - Thin-data

@Test func thinDataBelowThreeDays() {
    for days in [0, 1, 2] {
        let brief = CoachingBriefService.buildBriefInput(
            alerts: [makeAlert("A1")],
            patterns: [makePattern("weight", "protein")],
            toolSignals: [toolSignal("weight-trend")],
            dataDayCount: days
        )
        #expect(brief.isThinData)
        #expect(brief.signals.isEmpty) // explicit thin-data signal, not a fabricated insight
        #expect(brief.dataDayCount == days)
    }
}

@Test func notThinDataAtBoundaryOfThreeDays() {
    let brief = CoachingBriefService.buildBriefInput(
        alerts: [makeAlert("A1")],
        patterns: [],
        toolSignals: [],
        dataDayCount: 3
    )
    #expect(!brief.isThinData)
    #expect(brief.signals.count == 1)
}

// MARK: - Determinism

@Test func deterministicForEqualInput() {
    func build() -> BriefInput {
        CoachingBriefService.buildBriefInput(
            alerts: [makeAlert("A1", dismissKey: "k1"), makeAlert("A2")],
            patterns: [makePattern("weight", "protein", summary: "s")],
            toolSignals: [toolSignal("weight-trend")],
            dataDayCount: 10
        )
    }
    #expect(build() == build())
}

// MARK: - Mappers

@Test func alertSignalMapsDirectionAndId() {
    let positive = CoachingBriefService.signal(from: makeAlert("Workout goal hit", isPositive: true, dismissKey: "wk"))
    #expect(positive.source == .alert)
    #expect(positive.goalDirection == .aligned)
    #expect(positive.id == "wk") // dismissKey reused as the stable id

    let negative = CoachingBriefService.signal(from: makeAlert("Protein below target", isPositive: false))
    #expect(negative.goalDirection == .against)
    #expect(negative.id == "alert-protein-below-target") // slug fallback when no dismissKey
}

@Test func patternSignalIsNeutralWithOrderStableId() {
    let s1 = CoachingBriefService.signal(from: makePattern("weight", "protein", summary: "corr"))
    let s2 = CoachingBriefService.signal(from: makePattern("protein", "weight", summary: "corr")) // metrics swapped
    #expect(s1.source == .pattern)
    #expect(s1.goalDirection == .neutral) // a correlation has no goal direction
    #expect(s1.id == s2.id) // UnorderedMetricPair → stable dedup id regardless of A/B order
    #expect(s1.detail == "corr")
}

@Test func weightTrendNotReadySentinelsReturnNil() {
    #expect(CoachingBriefService.weightTrendSignal(summary: "Set a goal weight first — try 'set my goal to 75 kg'.") == nil)
    #expect(CoachingBriefService.weightTrendSignal(summary: "Need at least 7 days of weight data to predict — you have 3.") == nil)
    #expect(CoachingBriefService.weightTrendSignal(summary: "Couldn't compute a trend. Make sure weights are logged.") == nil)
}

@Test func weightTrendActionableSummaryBecomesSignal() {
    let summary = "At your current rate of 0.50 kg/week, you'll reach 75.0 kg around July 1, 2026 (~12 weeks). Trend confidence: high (R²=80%)."
    let signal = CoachingBriefService.weightTrendSignal(summary: summary)
    #expect(signal?.source == .tool)
    #expect(signal?.id == "weight-trend")
    #expect(signal?.detail == summary)
    #expect(signal?.goalDirection == .neutral)
}
