import SwiftUI
import DriftCore
import Charts

struct WeightChartView: View {
    let trend: WeightTrendCalculator.WeightTrend?
    let unit: WeightUnit
    let granularity: WeightViewModel.Granularity
    var rawEntries: [WeightEntry] = []
    var rangeStart: Date? = nil

    /// X-value the user is touching, via `.chartXSelection` — coexists with the
    /// scroll gesture (the old DragGesture overlay would have eaten the scroll).
    @State private var selectedDate: Date?

    @State private var scrollX = Date()

    /// ALL trend points (full history) — the chart PLOTS these so you can scroll
    /// through your whole timeline. `rangeStart` no longer filters the data; it
    /// sets the initial visible WINDOW via `.chartXVisibleDomain`. The EMA values
    /// are the ones the calculator produced across all history. Series building
    /// lives in DriftCore (`WeightChartSeries`) so the mapping is Tier-0 tested.
    /// Memoizes the built series so a render (and every scroll frame) doesn't
    /// rebuild it ~11× — the property is read by many chart marks + derived
    /// properties. The cache key is (granularity, unit, point count, currentEMA):
    /// any add/delete changes the count, and any weight edit — even mid-history —
    /// changes currentEMA (the EMA depends on every point), so there is no
    /// staleness. (#950)
    private final class SeriesCache {
        private var key = ""
        private var value: [WeightChartSeries.Point] = []
        func points(key: String, build: () -> [WeightChartSeries.Point]) -> [WeightChartSeries.Point] {
            if key != self.key { value = build(); self.key = key }
            return value
        }
    }
    @State private var seriesCache = SeriesCache()

    private var displayPoints: [WeightChartSeries.Point] {
        guard let trend else { return [] }
        let key = "\(granularity)-\(unit)-\(trend.dataPoints.count)-\(trend.currentEMA)"
        return seriesCache.points(key: key) {
            granularity == .weekly
                ? WeightChartSeries.weekly(trend.dataPoints, unit: unit)
                : WeightChartSeries.daily(trend.dataPoints, unit: unit)
        }
    }

    /// The selected-range slice — drives the Average / Difference / date-range
    /// HEADER so those numbers track the window you start on (not 2 years).
    private var rangePoints: [WeightChartSeries.Point] {
        guard let start = rangeStart else { return displayPoints }
        return displayPoints.filter { $0.date >= start }
    }

    // MARK: - Scroll window (range button = zoom; pan through history)

    private var lastChartDate: Date { displayPoints.last?.date ?? Date() }
    private var firstChartDate: Date { displayPoints.first?.date ?? lastChartDate.addingTimeInterval(-86_400) }

    /// Trailing breathing room past the last weigh-in (~4% of the visible
    /// window). Without it the "you are here" dot sits ON the plot's clip
    /// edge — half the dot and its value label were swallowed by the y-axis
    /// gutter (field complaint 2026-07-07).
    private var trailingPadSeconds: TimeInterval { visibleSeconds * 0.04 }
    private var paddedLastChartDate: Date { lastChartDate.addingTimeInterval(trailingPadSeconds) }

    /// Width of the visible window in seconds = the selected range (All = full span).
    private var visibleSeconds: TimeInterval {
        let total = max(86_400, lastChartDate.timeIntervalSince(firstChartDate))
        guard let start = rangeStart else { return total }
        return min(total, max(7 * 86_400, lastChartDate.timeIntervalSince(start)))
    }

    /// Y-range of just the points in the current visible window, padded — so a
    /// scrolled-to month fills the chart instead of looking flat against the
    /// full-history range.
    private var visibleYDomain: ClosedRange<Double> {
        let hi = scrollX.addingTimeInterval(visibleSeconds)
        let windowYs = displayPoints.filter { $0.date >= scrollX && $0.date <= hi }
            .flatMap { [$0.ema] + ($0.actual.map { [$0] } ?? []) }
        let pool = windowYs.count >= 2 ? windowYs
            : displayPoints.flatMap { [$0.ema] + ($0.actual.map { [$0] } ?? []) }
        guard let lo = pool.min(), let hiY = pool.max(), hiY > lo else { return 0...1 }
        let pad = max(0.5, (hiY - lo) * 0.12)
        return (lo - pad)...(hiY + pad)
    }

    private func anchorScrollToLatest() {
        // Anchor to the PADDED end so the trailing breathing room (and the
        // fully-visible latest dot) is on screen, not scrolled past.
        scrollX = paddedLastChartDate.addingTimeInterval(-visibleSeconds)
    }

    /// The data point nearest the user's `.chartXSelection` touch (nil = none).
    private var selectedChartPoint: (date: Date, value: Double)? {
        guard let d = selectedDate,
              let nearest = displayPoints.min(by: {
                  abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d))
              }) else { return nil }
        return (nearest.date, nearest.actual ?? nearest.ema)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if trend != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Average").font(.caption2).foregroundStyle(Theme.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(String(format: "%.1f", averageWeight)).font(.title2.weight(.bold).monospacedDigit())
                            Text(unit.displayName).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    if let diff = totalDifference {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Difference").font(.caption2).foregroundStyle(Theme.textTertiary)
                            Text("\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff)) \(unit.displayName)")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(diff < 0 ? Theme.deficit : diff > 0 ? Theme.surplus : .secondary)
                        }
                    }
                }

                if let f = rangePoints.first?.date, let l = rangePoints.last?.date {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(DateFormatters.shortDisplay.string(from: f)) – \(DateFormatters.shortDisplay.string(from: l))")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                        Spacer()
                        // Legend lives once, below the chart (Scale / Trend) —
                        // the old header legend here duplicated it and had stale
                        // colours after the trend went indigo.
                    }
                }

            }

            Chart {
                // Current value reference line (accent, horizontal) —
                // anchored to the latest *actual* weight so the user's
                // most recent weigh-in is the line you see, not the
                // smoothed trend value (which can sit several pounds
                // away after a sharp move).
                // Value label moved off the RuleMark's trailing edge — there it
                // collided with the y-axis gutter and got clipped to a sliver
                // (field complaint 2026-07-07); it now rides the coral dot below.
                if let currentActual = displayPoints.last(where: { $0.actual != nil })?.actual {
                    RuleMark(y: .value("", currentActual))
                        .foregroundStyle(Theme.textTertiary.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }

                // Raw scale readings — connected by a thin light line with a
                // marker on each actual weigh-in (#932, the TrendWeight /
                // Happy Scale pattern: you see the real day-to-day path, not
                // isolated dots). The 2026-05 connected line was removed for
                // catmullRom loop artifacts; this one interpolates LINEARLY —
                // straight segments between readings can't overshoot a spike.
                // Gaps (days without a weigh-in) are skipped so the line
                // connects reading→reading rather than dropping to zero.
                ForEach(Array(displayPoints.enumerated().filter { $0.element.actual != nil }), id: \.offset) { i, p in
                    LineMark(
                        x: .value("", p.date),
                        y: .value("Scale", p.actual ?? 0),
                        series: .value("Series", "Scale")
                    )
                    .foregroundStyle(Theme.textTertiary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)

                    PointMark(
                        x: .value("", p.date),
                        y: .value("Scale", p.actual ?? 0)
                    )
                    .foregroundStyle(Theme.textTertiary.opacity(0.5))
                    .symbolSize(granularity == .weekly ? 26 : 14)
                }

                // Trend (EMA) is the HERO — the heavier smoothed line drawn
                // over the raw path, goal-aware per tenets: green when the
                // window's trend moves toward the goal, red when against it,
                // neutral ink when flat (#932).
                ForEach(displayPoints.indices, id: \.self) { i in
                    LineMark(
                        x: .value("", displayPoints[i].date),
                        y: .value("Trend", displayPoints[i].ema),
                        series: .value("Series", "Trend")
                    )
                    .foregroundStyle(trendColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }
                // For the coarse weekly view, mark each aggregated point on the
                // trend line so the sparse series reads as discrete weeks.
                if granularity == .weekly {
                    ForEach(displayPoints.indices, id: \.self) { i in
                        if displayPoints[i].actual != nil {
                            PointMark(
                                x: .value("", displayPoints[i].date),
                                y: .value("Trend", displayPoints[i].ema)
                            )
                            .foregroundStyle(trendColor)
                            .symbolSize(22)
                        }
                    }
                }

                // Single coral "you are here" dot on the most recent weigh-in,
                // placed on the ACTUAL value (sitting on the dashed current-weight
                // rule), not the smoothed trend — the one brand accent on an
                // otherwise neutral chart.
                if let last = displayPoints.last(where: { $0.actual != nil }), let actual = last.actual {
                    PointMark(x: .value("", last.date), y: .value("Scale", actual))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(70)
                        // Latest value rides the dot, fitted INSIDE the plot so
                        // neither the axis gutter nor the top edge can clip it.
                        .annotation(position: .top, spacing: 5,
                                    overflowResolution: .init(x: .fit(to: .plot), y: .fit(to: .plot))) {
                            Text(String(format: "%.1f", actual))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                        }
                }

                // Selected point callout
                if let sel = selectedChartPoint {
                    PointMark(x: .value("", sel.date), y: .value("", sel.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(80)
                        .annotation(position: .top, spacing: 6) {
                            VStack(spacing: 2) {
                                Text(sel.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(String(format: "%.1f \(unit.displayName)", sel.value))
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            // V7 mobile fix: `.ultraThinMaterial`
                            // rendered as a near-opaque dark blob over
                            // the coral chart line on the light theme
                            // (the material's adaptive blur picked up
                            // the saturated coral and went dark
                            // instead of frosted). Solid cardBackground
                            // + a hairline border reads cleanly on top
                            // of the line and matches the rest of the
                            // V7 chrome.
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Theme.separator, lineWidth: 0.5)
                            )
                            // #premium-polish: was a 4th ad-hoc shadow recipe;
                            // use the shared card elevation so the scrub callout
                            // matches every other floating chrome surface.
                            .shadowSoft()
                        }
                }
            }
            .chartYScale(domain: visibleYDomain)
            .chartXScale(domain: firstChartDate...paddedLastChartDate)
            .chartScrollableAxes(.horizontal)
            .chartXVisibleDomain(length: visibleSeconds)
            .chartScrollPosition(x: $scrollX)
            .onAppear { anchorScrollToLatest() }
            .onChange(of: rangeStart) { _, _ in anchorScrollToLatest() }
            .onChange(of: granularity) { _, _ in anchorScrollToLatest() }
            .chartXAxis {
                // Span-aware labels. One fixed format can't serve both ends:
                // month+day on the All range rendered five identical "Jan 1"
                // ticks across years (field report 2026-07-14), and
                // month-only on a single-day range rendered "May May May"
                // (the V7 fix). Pick by the visible window:
                //   ≤ ~3.5 months  → "Jul 8"
                //   ≤ ~1.5 years   → "Jul 2026"
                //   beyond         → "2026"
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    if visibleSeconds > 550 * 86_400 {
                        AxisValueLabel(format: .dateTime.year())
                            .foregroundStyle(Theme.textSecondary)
                    } else if visibleSeconds > 110 * 86_400 {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year())
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .chartYAxis {
                // Single weight axis (#932) — the leading kcal axis left with
                // the calorie overlay.
                AxisMarks(position: .trailing) {
                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                }
            }
            // Tap / long-press to read a value — `.chartXSelection` instead of a
            // DragGesture overlay so it coexists with the horizontal scroll
            // gesture (the old minimumDistance-0 drag would have eaten the scroll).
            .chartXSelection(value: $selectedDate)

            // Scale vs Trend legend — the light connected reading line with
            // markers vs the heavier smoothed trend. Lives WITH the chart
            // (moved from WeightTabView, #932) so the trend swatch always
            // matches the goal-aware line colour actually drawn above.
            HStack(spacing: 18) {
                HStack(spacing: 5) {
                    ZStack {
                        Capsule().fill(Theme.textTertiary.opacity(0.35)).frame(width: 16, height: 1.5)
                        Circle().fill(Theme.textTertiary.opacity(0.5)).frame(width: 5, height: 5)
                    }
                    Text("Scale").font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 5) {
                    Capsule().fill(trendColor).frame(width: 16, height: 3)
                    Text("Trend").font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Weight chart. Average \(String(format: "%.1f", averageWeight)) \(unit.displayName)\(totalDifference.map { ", change \(String(format: "%+.1f", $0))" } ?? "")")
    }

    private var averageWeight: Double {
        // Use ALL raw entries (including outliers) for honest average
        if !rawEntries.isEmpty {
            let weights = rawEntries.map { unit.convert(fromKg: $0.weightKg) }
            return weights.reduce(0, +) / Double(weights.count)
        }
        // Fallback to display points if no raw entries passed
        let a = displayPoints.compactMap(\.actual)
        if !a.isEmpty { return a.reduce(0, +) / Double(a.count) }
        let e = displayPoints.compactMap(\.ema)
        guard !e.isEmpty else { return 0 }
        return e.reduce(0, +) / Double(e.count)
    }

    private var totalDifference: Double? {
        // Trend (EMA) endpoints, NOT raw actuals. A raw first-vs-last comparison
        // is a low-day-vs-high-day artifact — a 115.2 dip on the left vs a 120.5
        // peak on the right reads "+5.3" of mostly water, contradicting the
        // smoothed "Holding steady" verdict on the same screen. The dashed trend
        // line's net movement over the window is the honest change (and matches
        // the trend-based delta chips). Falls back to actuals only when the window
        // somehow has no EMA (synthesized-point edge case).
        if let f = rangePoints.first?.ema, let l = rangePoints.last?.ema {
            return l - f
        }
        let actuals = rangePoints.compactMap(\.actual)
        guard let f = actuals.first, let l = actuals.last else { return nil }
        return l - f
    }

    // MARK: - Goal-aware trend colour (#932)

    /// Green when the smoothed trend moves toward the goal, red when against
    /// it, neutral ink when flat. Defaults to a losing goal when none is set
    /// (tenet). Static so the legend can use the identical mapping.
    static func trendColor(emaDelta: Double?, goalChangeKg: Double?) -> Color {
        guard let d = emaDelta, abs(d) > 0.05 else { return Theme.chartTrend }
        let gainIsGood = (goalChangeKg ?? -1) > 0
        return (d > 0) == gainIsGood ? Theme.deficit : Theme.surplus
    }

    private var trendColor: Color {
        Self.trendColor(emaDelta: totalDifference, goalChangeKg: WeightGoal.load()?.totalChangeKg)
    }
}
