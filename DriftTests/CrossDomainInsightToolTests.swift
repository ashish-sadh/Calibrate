import Foundation
import Testing
@testable import Drift

// MARK: - Pure correlation math

@Test func pearson_perfectPositive() {
    let xs = [1.0, 2, 3, 4, 5]
    let ys = [2.0, 4, 6, 8, 10]
    let r = CrossDomainInsightTool.pearsonR(xs: xs, ys: ys)
    #expect(r != nil)
    #expect(abs((r ?? 0) - 1.0) < 1e-9, "perfect linear → r = 1.0")
}

@Test func pearson_perfectNegative() {
    let xs = [1.0, 2, 3, 4, 5]
    let ys = [10.0, 8, 6, 4, 2]
    let r = CrossDomainInsightTool.pearsonR(xs: xs, ys: ys)
    #expect(r != nil)
    #expect(abs((r ?? 0) - -1.0) < 1e-9)
}

@Test func pearson_uncorrelated() {
    // Hand-built pair with mean-centered sum-of-products = 0.
    let xs = [1.0, 2, 3, 4, 5]
    let ys = [3.0, 1, 3, 1, 3]
    let r = CrossDomainInsightTool.pearsonR(xs: xs, ys: ys)
    #expect(r != nil)
    #expect(abs(r ?? 1) < 0.5, "should be weak, not strong")
}

@Test func pearson_flatSeriesReturnsNil() {
    // Zero variance on one side means r is undefined.
    let xs = [5.0, 5, 5, 5, 5]
    let ys = [1.0, 2, 3, 4, 5]
    #expect(CrossDomainInsightTool.pearsonR(xs: xs, ys: ys) == nil)
}

@Test func pearson_tooFewSamplesReturnsNil() {
    #expect(CrossDomainInsightTool.pearsonR(xs: [], ys: []) == nil)
    #expect(CrossDomainInsightTool.pearsonR(xs: [1.0], ys: [2.0]) == nil)
}

@Test func pearson_mismatchedLengthReturnsNil() {
    #expect(CrossDomainInsightTool.pearsonR(xs: [1.0, 2], ys: [1.0]) == nil)
}

@Test func pearson_clampsFloatingPointOvershoot() {
    // Tiny FP overshoot beyond ±1 should clamp to ±1 so downstream formatting
    // never sees "r=+1.01".
    let xs = (0..<100).map { Double($0) }
    let ys = xs.map { $0 * 2.0 + 1.0 }
    let r = CrossDomainInsightTool.pearsonR(xs: xs, ys: ys) ?? 0
    #expect(r >= -1.0 && r <= 1.0)
}

// MARK: - Strength + direction bucketing

@Test func strengthLabel_thresholds() {
    #expect(CrossDomainInsightTool.strengthLabel(0.8) == "strong")
    #expect(CrossDomainInsightTool.strengthLabel(-0.7) == "strong")
    #expect(CrossDomainInsightTool.strengthLabel(0.45) == "moderate")
    #expect(CrossDomainInsightTool.strengthLabel(-0.35) == "moderate")
    #expect(CrossDomainInsightTool.strengthLabel(0.1) == "weak")
    #expect(CrossDomainInsightTool.strengthLabel(0.0) == "weak")
    #expect(CrossDomainInsightTool.strengthLabel(0.6) == "strong", "0.6 boundary inclusive")
    #expect(CrossDomainInsightTool.strengthLabel(0.3) == "moderate", "0.3 boundary inclusive")
}

@Test func directionLabel_signs() {
    #expect(CrossDomainInsightTool.directionLabel(0.8) == "positive")
    #expect(CrossDomainInsightTool.directionLabel(-0.8) == "negative")
    #expect(CrossDomainInsightTool.directionLabel(0.02) == "flat")
    #expect(CrossDomainInsightTool.directionLabel(-0.02) == "flat")
}

// MARK: - Metric normalization

@Test func normalize_canonicalMetricsPassThrough() {
    for m in CrossDomainInsightTool.supportedMetrics {
        #expect(CrossDomainInsightTool.normalizeMetric(m) == m)
    }
}

@Test func normalize_commonAliases() {
    #expect(CrossDomainInsightTool.normalizeMetric("Weight") == "weight")
    #expect(CrossDomainInsightTool.normalizeMetric("bodyweight") == "weight")
    #expect(CrossDomainInsightTool.normalizeMetric("cal") == "calories")
    #expect(CrossDomainInsightTool.normalizeMetric("kcal") == "calories")
    #expect(CrossDomainInsightTool.normalizeMetric("carbs_g") == "carbs")
    #expect(CrossDomainInsightTool.normalizeMetric("carbohydrates") == "carbs")
    #expect(CrossDomainInsightTool.normalizeMetric("Sugar") == "glucose_avg")
    #expect(CrossDomainInsightTool.normalizeMetric("blood sugar") == "glucose_avg")
    #expect(CrossDomainInsightTool.normalizeMetric("Workouts") == "workout_volume")
    #expect(CrossDomainInsightTool.normalizeMetric("lifting") == "workout_volume")
    #expect(CrossDomainInsightTool.normalizeMetric("  FAT  ") == "fat")
}

@Test func normalize_pendingMetricsPreserved() {
    // Keep the key so `run()` can emit a targeted "not yet supported" message.
    #expect(CrossDomainInsightTool.normalizeMetric("sleep") == "sleep_hours")
    #expect(CrossDomainInsightTool.normalizeMetric("sleep_hours") == "sleep_hours")
    #expect(CrossDomainInsightTool.normalizeMetric("steps") == "steps")
    #expect(CrossDomainInsightTool.normalizeMetric("step_count") == "steps")
}

@Test func normalize_emptyReturnsEmpty() {
    #expect(CrossDomainInsightTool.normalizeMetric("") == "")
    #expect(CrossDomainInsightTool.normalizeMetric("   ") == "")
}

// MARK: - Window clamping

@Test func clampWindow_bucketsByThreshold() {
    #expect(CrossDomainInsightTool.clampWindow(nil) == 30)
    #expect(CrossDomainInsightTool.clampWindow(5) == 7)
    #expect(CrossDomainInsightTool.clampWindow(7) == 7)
    #expect(CrossDomainInsightTool.clampWindow(10) == 7)
    #expect(CrossDomainInsightTool.clampWindow(14) == 14)
    #expect(CrossDomainInsightTool.clampWindow(21) == 14)
    #expect(CrossDomainInsightTool.clampWindow(30) == 30)
    #expect(CrossDomainInsightTool.clampWindow(60) == 30)
    #expect(CrossDomainInsightTool.clampWindow(90) == 90)
    #expect(CrossDomainInsightTool.clampWindow(365) == 90)
}

// MARK: - Date helpers

@Test func dateWindow_includesEndDay() {
    let now = DateFormatters.dateOnly.date(from: "2026-04-20")!
    let (start, end) = CrossDomainInsightTool.dateWindow(windowDays: 7, now: now)
    #expect(end == "2026-04-20")
    #expect(start == "2026-04-14", "7-day inclusive window should span 14..20")
}

@Test func datesInRange_generatesConsecutiveDays() {
    let dates = CrossDomainInsightTool.datesInRange(startDate: "2026-04-18", endDate: "2026-04-21")
    #expect(dates == ["2026-04-18", "2026-04-19", "2026-04-20", "2026-04-21"])
}

@Test func datesInRange_emptyForReversedBounds() {
    let dates = CrossDomainInsightTool.datesInRange(startDate: "2026-04-21", endDate: "2026-04-18")
    #expect(dates.isEmpty)
}

// MARK: - Formatted summary

@Test func formatSummary_containsKeyFields() {
    let xs = [70.0, 71, 70.5, 72, 71.5]
    let ys = [100.0, 120, 110, 140, 130]
    let r = CrossDomainInsightTool.pearsonR(xs: xs, ys: ys) ?? 0
    let out = CrossDomainInsightTool.formatSummary(
        metricA: "weight", metricB: "workout_volume",
        xs: xs, ys: ys, r: r, windowDays: 30
    )
    #expect(out.contains("weight"))
    #expect(out.contains("workout volume"))
    #expect(out.contains("30 days"))
    #expect(out.contains("5 paired days"))
    #expect(out.contains("r=+") || out.contains("r=-"))
    #expect(out.contains("strong") || out.contains("moderate") || out.contains("weak"))
}

@Test func formatSummary_signedCoefficient() {
    let xs = [1.0, 2, 3]
    let ys = [3.0, 2, 1]
    let r = CrossDomainInsightTool.pearsonR(xs: xs, ys: ys) ?? 0
    let out = CrossDomainInsightTool.formatSummary(
        metricA: "calories", metricB: "weight",
        xs: xs, ys: ys, r: r, windowDays: 7
    )
    #expect(out.contains("r=-1.00"), "format should preserve sign to 2 decimals")
    #expect(out.contains("negative"))
}

// MARK: - Graceful degradation via run()

@Test @MainActor func run_unknownMetricMessage() {
    let out = CrossDomainInsightTool.run(metricA: "unicorn", metricB: "weight", windowDays: 30)
    #expect(out.lowercased().contains("unknown"))
}

@Test @MainActor func run_missingMetricsPromptsForBoth() {
    let out = CrossDomainInsightTool.run(metricA: "", metricB: "weight", windowDays: 30)
    #expect(out.lowercased().contains("which two metrics"))
}

@Test @MainActor func run_samePairRejected() {
    let out = CrossDomainInsightTool.run(metricA: "calories", metricB: "calories", windowDays: 30)
    #expect(out.lowercased().contains("two different"))
}

@Test @MainActor func run_pendingMetricGracefullyDeferred() {
    let out = CrossDomainInsightTool.run(metricA: "sleep_hours", metricB: "calories", windowDays: 30)
    #expect(out.lowercased().contains("sleep"))
    #expect(out.lowercased().contains("aren't wired up") || out.lowercased().contains("not"))
}

@Test @MainActor func run_insufficientDataDegradesGracefully() {
    // Shared test DB is unseeded for these metrics — expect the "need more
    // data" branch rather than a crash or a bogus correlation.
    let out = CrossDomainInsightTool.run(metricA: "weight", metricB: "glucose_avg", windowDays: 7)
    let lower = out.lowercased()
    #expect(lower.contains("need at least") || lower.contains("flat over"),
            "must surface a graceful degradation line; got: \(out)")
}

// MARK: - Tool registry wiring

@Test @MainActor func tool_registerRoundTrip() {
    CrossDomainInsightTool.syncRegistration()
    let t = ToolRegistry.shared.tool(named: CrossDomainInsightTool.toolName)
    #expect(t != nil)
    #expect(t?.service == "insights")
    #expect(t?.parameters.contains(where: { $0.name == "metric_a" }) == true)
    #expect(t?.parameters.contains(where: { $0.name == "metric_b" }) == true)
    #expect(t?.parameters.contains(where: { $0.name == "window_days" && !$0.required }) == true)
}

@Test @MainActor func tool_handlerRunsWithoutCrash() async {
    CrossDomainInsightTool.syncRegistration()
    let call = ToolCall(
        tool: CrossDomainInsightTool.toolName,
        params: ToolCallParams(values: [
            "metric_a": "weight",
            "metric_b": "workout_volume",
            "window_days": "30"
        ])
    )
    let result = await ToolRegistry.shared.execute(call)
    // Against an empty test DB we expect a text response (graceful degrade).
    if case .text(let s) = result {
        #expect(!s.isEmpty)
    } else {
        Issue.record("expected .text result, got \(result)")
    }
}

@Test @MainActor func tool_isRegisteredAsInfoTool() {
    // Cross-domain insights are read-only analytical — Gemma should treat
    // them like other info tools for streaming presentation.
    #expect(AIToolAgent.isInfoTool(CrossDomainInsightTool.toolName))
}

// MARK: - Intent threshold policy

@Test func intentThreshold_crossDomainInsightAlwaysProceeds() {
    // .data domain policy: no clarify, no required user-named entity.
    for confidence in ["high", "medium", "low"] {
        for complete in [true, false] {
            let d = IntentThresholds.shouldClarify(
                tool: CrossDomainInsightTool.toolName,
                confidence: confidence,
                hasCompleteParams: complete
            )
            #expect(d == .proceed, "cross_domain_insight should always proceed (conf=\(confidence), complete=\(complete))")
        }
    }
}
