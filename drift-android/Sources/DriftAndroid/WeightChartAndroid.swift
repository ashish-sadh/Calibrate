import SwiftUI
import DriftCore

/// Path-based weight chart for the Android Body tab (#1092) — SkipUI has no
/// Charts/Canvas (skip_fuse_is_the_availability_tree), so this replicates
/// `Drift/Views/Weight/WeightChartView.swift` (dashed current-weight rule,
/// thin Scale reading line + dots, hero goal-aware Trend/EMA line, coral
/// latest-value dot) as merged `Path`s.
///
/// `points` is the FULL series: exactly like iOS, the range chip sets the
/// visible WINDOW (`rangeStart` → `WeightChartWindow`, anchored at the last
/// data point) and never filters the data, so no chip can blank the chart
/// (#1220). Average / Difference / the date-range subtitle are range-scoped
/// the same way iOS scopes them.
///
/// v1 has no pan gesture — the chips are the whole windowing mechanism
/// (SkipUI HScroll/GeometryReader-per-frame traps; see #1092 plan).
struct WeightChartAndroid: View {
    /// Full daily (or weekly-aggregated) series — never pre-windowed.
    let points: [WeightChartSeries.Point]
    /// Raw weigh-ins inside the selected range, already in display units —
    /// iOS averages exactly these (`WeightChartView.averageWeight`).
    var rawWeightsInUnit: [Double] = []
    let unit: WeightUnit
    let goalChangeKg: Double?
    /// The chip's cutoff (nil = All). Scopes the header, sizes the window.
    var rangeStart: Date? = nil
    /// Weekly aggregation plots far fewer readings, so iOS grows the scale
    /// marker (symbolSize 26 vs 14, `WeightChartView.swift:182`); mirror that.
    var isWeekly: Bool = false

    /// Visible X window: anchored at the last point with a 7-day floor and a
    /// 4% trailing pad — `WeightChartWindow` is the Tier-0 port of iOS's
    /// `visibleSeconds` / `anchorScrollToLatest`.
    private var window: WeightChartWindow.Window? {
        guard let first = points.first?.date, let last = points.last?.date else { return nil }
        return WeightChartWindow.resolve(firstDate: first, lastDate: last, rangeStart: rangeStart)
    }

    /// The selected-range slice — drives Average / Difference / the date-range
    /// subtitle, exactly as iOS's `rangePoints` does.
    private var rangePoints: [WeightChartSeries.Point] {
        guard let start = rangeStart else { return points }
        return points.filter { $0.date >= start }
    }

    /// iOS `WeightChartView.averageWeight`: the raw entries in range (outliers
    /// included — an honest average), falling back to the full series.
    private var averageWeight: Double {
        if !rawWeightsInUnit.isEmpty {
            return rawWeightsInUnit.reduce(0, +) / Double(rawWeightsInUnit.count)
        }
        let actuals = points.compactMap(\.actual)
        if !actuals.isEmpty { return actuals.reduce(0, +) / Double(actuals.count) }
        guard !points.isEmpty else { return 0 }
        return points.map(\.ema).reduce(0, +) / Double(points.count)
    }

    /// Trend (EMA) endpoints over the SELECTED RANGE — matches
    /// `WeightChartView.totalDifference` (the smoothed net movement, not a raw
    /// first-vs-last actual comparison). Nil hides the row, as on iOS.
    private var totalDifference: Double? {
        if let f = rangePoints.first?.ema, let l = rangePoints.last?.ema { return l - f }
        let actuals = rangePoints.compactMap(\.actual)
        guard let f = actuals.first, let l = actuals.last else { return nil }
        return l - f
    }

    /// Verbatim port of `WeightChartView.trendColor` (three-similar-lines
    /// tenet — only 2 call sites here, not worth hoisting to DriftCore).
    static func trendTint(emaDelta: Double?, goalChangeKg: Double?) -> Color {
        guard let d = emaDelta, abs(d) > 0.05 else { return Theme.chartTrend }
        let gainIsGood = (goalChangeKg ?? -1) > 0
        return (d > 0) == gainIsGood ? Theme.deficit : Theme.surplus
    }

    private var trendColor: Color {
        Self.trendTint(emaDelta: totalDifference, goalChangeKg: goalChangeKg)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let window {
                WeightChartPlot(points: points, windowStart: window.start, windowEnd: window.end,
                                trendColor: trendColor, isWeekly: isWeekly)
                    .frame(height: 165)
                xAxisLabels(window: window)
            }
            legend
        }
        .card()
        // accessibilityElement(children:) is unavailable on SkipUI (Fuse) —
        // the label still applies, just without collapsing the sub-texts.
        // Text-wrapped: Fuse's String overload of accessibilityLabel requires
        // an explicit isEnabled argument, so a bare String has no match.
        .accessibilityLabel(Text(accessibilitySummary))
    }

    private var accessibilitySummary: String {
        var text = "Weight chart. Average \(String(format: "%.1f", averageWeight)) \(unit.displayName)"
        if let diff = totalDifference {
            text += ", change \(String(format: "%+.1f", diff))"
        }
        return text
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Average").font(.caption2).foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(String(format: "%.1f", averageWeight))
                            .font(.title2.weight(.bold).monospacedDigit())
                        Text(unit.displayName).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if let diff = totalDifference {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Difference").font(.caption2).foregroundStyle(Theme.textTertiary)
                        Text("\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff)) \(unit.displayName)")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(abs(diff) <= 0.05 ? Theme.textSecondary : trendColor)
                    }
                }
            }
            // The resolved window as a subtitle, iOS's exact source + format
            // (`WeightChartView.swift:131-140`): the RANGE points, hidden when
            // the range holds none.
            if let f = rangePoints.first?.date, let l = rangePoints.last?.date {
                Text("\(DateFormatters.shortDisplay.string(from: f)) – \(DateFormatters.shortDisplay.string(from: l))")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    /// Date ticks across the visible window, span-aware like iOS's
    /// `chartXAxis` thresholds and at its tick density (`desiredCount: 4`).
    /// Computed once per body — never inside the GeometryReader plot layer,
    /// which recomposes per frame on Fuse.
    private func xAxisLabels(window: WeightChartWindow.Window) -> some View {
        // Equal columns: the outer two align to the plot edges and the inner
        // two centre in their column, so the DRAWN positions are
        // 0 / .375 / .625 / 1 of the width — the same fractions the dates are
        // computed from, so every tick sits under its own date.
        let fractions: [Double] = [0, 0.375, 0.625, 1]
        let span = window.seconds
        let formatter: DateFormatter = span > 550 * 86_400 ? DateFormatters.yearOnly
            : span > 110 * 86_400 ? DateFormatters.shortMonthYear
            : DateFormatters.shortDisplay
        return HStack(spacing: 0) {
            ForEach(fractions.indices, id: \.self) { i in
                Text(formatter.string(from: window.start.addingTimeInterval(span * fractions[i])))
                    .frame(maxWidth: .infinity,
                           alignment: i == 0 ? .leading : (i == fractions.count - 1 ? .trailing : .center))
            }
        }
        .font(.caption2).foregroundStyle(Theme.textSecondary)
        // Matches the plot's trailing y-label gutter (32 + the 4pt HStack gap)
        // so the last tick sits under the plot's right edge, not the card's.
        .padding(.trailing, 36)
    }

    private var legend: some View {
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
}

// MARK: - Plot

/// The line/dot layer only — isolated so `.drawingGroup()` rasterizes just
/// the Path work once per built size, mirroring `MuscleBodyView` (#1074):
/// GeometryReader recomposes on every scroll frame on Fuse (global-position
/// invalidation), so the expensive part (point math, merged Paths) is cached
/// by size; only the cheap cached-Path draw re-runs per frame.
struct WeightChartPlot: View {
    /// The FULL series — the window decides what is drawn, not the caller.
    let points: [WeightChartSeries.Point]
    let windowStart: Date
    let windowEnd: Date
    let trendColor: Color
    var isWeekly: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            GeometryReader { geo in
                plotLayer(in: geo.size)
            }
            .drawingGroup()
            yAxisLabels
                .frame(width: 32)
        }
    }

    /// Three gridline values, matching the density iOS's automatic Y axis
    /// renders (it drew 104 / 102 / 100 against Android's two — #1205).
    private var yAxisLabels: some View {
        VStack {
            if let d = Self.yDomain(points: points, windowStart: windowStart, windowEnd: windowEnd) {
                // A narrow window (one weigh-in inside it) spans well under a
                // whole unit, and whole-number labels printed "82 / 82 / 82".
                let decimals = (d.hi - d.lo) < 3 ? 1 : 0
                Text(String(format: "%.\(decimals)f", d.hi))
                Spacer()
                Text(String(format: "%.\(decimals)f", (d.hi + d.lo) / 2))
                Spacer()
                Text(String(format: "%.\(decimals)f", d.lo))
            }
        }
        .font(.caption2).foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private func plotLayer(in size: CGSize) -> some View {
        if let chart = Self.cachedChart(points: points, windowStart: windowStart,
                                        windowEnd: windowEnd, size: size, isWeekly: isWeekly) {
            ZStack(alignment: .topLeading) {
                if let ruleY = chart.ruleY {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: ruleY))
                        p.addLine(to: CGPoint(x: size.width, y: ruleY))
                    }
                    .stroke(Theme.textTertiary.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                chart.scaleDots.fill(Theme.textTertiary.opacity(0.5))
                chart.scaleLine.stroke(Theme.textTertiary.opacity(0.35),
                                        style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                chart.trendLine.stroke(trendColor,
                                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                if let coral = chart.coralCenter {
                    Circle().fill(Theme.accent).frame(width: 9, height: 9).position(coral)
                    if let value = chart.coralValue {
                        Text(String(format: "%.1f", value))
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                            .fixedSize()
                            .position(x: min(max(coral.x, 22), size.width - 22), y: max(coral.y - 14, 8))
                    }
                }
            }
        }
    }

    // MARK: - Built-Path cache (#1074 precedent)

    private struct BuiltChart {
        let scaleLine: Path
        let scaleDots: Path
        let trendLine: Path
        let ruleY: CGFloat?
        let coralCenter: CGPoint?
        let coralValue: Double?
    }

    private static var cache: [String: BuiltChart] = [:]
    private static let cacheLock = NSLock()

    private static func cachedChart(points: [WeightChartSeries.Point], windowStart: Date, windowEnd: Date,
                                    size: CGSize, isWeekly: Bool) -> BuiltChart? {
        // >= 1, not >= 2: a first-time user's single weigh-in must draw its dot
        // rather than blank-card the chart.
        guard points.count >= 1, size.width > 0, size.height > 0 else { return nil }
        // The window is part of the key: the same points under a different chip
        // lay out differently, and without it the cache serves a stale Path.
        let key = "\(Int(size.width))x\(Int(size.height))|\(points.count)|\(isWeekly)"
            + "|\(Int(windowStart.timeIntervalSince1970))|\(Int(windowEnd.timeIntervalSince1970))"
            + "|\(points.last?.ema ?? 0)|\(points.last?.actual ?? -1)"
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        let built = build(points: points, windowStart: windowStart, windowEnd: windowEnd,
                          size: size, isWeekly: isWeekly)
        cache[key] = built
        return built
    }

    /// Y-range of just the points in the visible window (plus the interpolated
    /// left-edge values), padded — iOS `visibleYDomain`, including its fallback
    /// to the full pool when the window holds fewer than two values. Shared by
    /// `build` and `yAxisLabels` so the axis can never disagree with the plot.
    static func yDomain(points: [WeightChartSeries.Point],
                        windowStart: Date, windowEnd: Date) -> (lo: Double, hi: Double)? {
        // Strictly the IN-WINDOW values — iOS `visibleYDomain` does not widen
        // the scale for the interpolated edge, and including it flattened the
        // whole plot against a 20 kg-older reading (Android read 101 / 80 where
        // iOS read 84 / 82 on the same data). The edge point simply runs off
        // the top, exactly as iOS's clipped chart draws it.
        var windowValues: [Double] = []
        for p in points where p.date >= windowStart && p.date <= windowEnd {
            windowValues.append(p.ema)
            if let a = p.actual { windowValues.append(a) }
        }
        let pool = windowValues.count >= 2 ? windowValues
            : points.flatMap { p -> [Double] in p.actual.map { [p.ema, $0] } ?? [p.ema] }
        guard let lo = pool.min(), let hi = pool.max() else { return nil }
        let pad = max(0.5, (hi - lo) * 0.12)
        return (lo - pad, hi + pad)
    }

    /// Where a series crosses the window's left edge, so a line entering from
    /// off-screen starts at x=0 exactly where iOS's clipped plot shows it
    /// (instead of jumping in at the first in-window point). Nil when the
    /// series has nothing before the edge, or nothing after it to interpolate
    /// toward.
    private static func edgeValue(points: [WeightChartSeries.Point],
                                  windowStart: Date, actualsOnly: Bool) -> Double? {
        var before: (date: Date, value: Double)?
        var after: (date: Date, value: Double)?
        for p in points {
            let raw: Double? = actualsOnly ? p.actual : p.ema
            guard let v = raw else { continue }
            if p.date < windowStart {
                before = (p.date, v)
            } else if after == nil {
                after = (p.date, v)
            }
        }
        guard let b = before, let a = after else { return nil }
        let t = windowStart.timeIntervalSince(b.date) / max(0.001, a.date.timeIntervalSince(b.date))
        return b.value + (a.value - b.value) * t
    }

    private static func build(points: [WeightChartSeries.Point], windowStart: Date, windowEnd: Date,
                              size: CGSize, isWeekly: Bool) -> BuiltChart? {
        guard let domain = yDomain(points: points, windowStart: windowStart, windowEnd: windowEnd) else { return nil }
        let yLo = domain.lo
        let yRange = max(0.001, domain.hi - yLo)
        let span = max(1, windowEnd.timeIntervalSince(windowStart))

        func x(for date: Date) -> CGFloat {
            CGFloat(date.timeIntervalSince(windowStart) / span) * size.width
        }
        func y(for value: Double) -> CGFloat {
            size.height - CGFloat((value - yLo) / yRange) * size.height
        }

        let visible = points.filter { $0.date >= windowStart && $0.date <= windowEnd }

        var scaleLine = Path()
        var scaleDots = Path()
        var scaleStarted = false
        if let edge = edgeValue(points: points, windowStart: windowStart, actualsOnly: true) {
            scaleLine.move(to: CGPoint(x: 0, y: y(for: edge)))
            scaleStarted = true
        }
        let dotRadius: CGFloat = isWeekly ? 2.6 : 1.9
        for p in visible {
            guard let actual = p.actual else { continue }
            let pt = CGPoint(x: x(for: p.date), y: y(for: actual))
            if scaleStarted { scaleLine.addLine(to: pt) } else { scaleLine.move(to: pt); scaleStarted = true }
            scaleDots.addEllipse(in: CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius,
                                             width: dotRadius * 2, height: dotRadius * 2))
        }

        var trendLine = Path()
        var trendStarted = false
        if let edge = edgeValue(points: points, windowStart: windowStart, actualsOnly: false) {
            trendLine.move(to: CGPoint(x: 0, y: y(for: edge)))
            trendStarted = true
        }
        for p in visible {
            let pt = CGPoint(x: x(for: p.date), y: y(for: p.ema))
            if trendStarted { trendLine.addLine(to: pt) } else { trendLine.move(to: pt); trendStarted = true }
        }

        var ruleY: CGFloat?
        var coralCenter: CGPoint?
        var coralValue: Double?
        if let last = visible.last(where: { $0.actual != nil }), let actual = last.actual {
            let ry = y(for: actual)
            ruleY = ry
            coralCenter = CGPoint(x: x(for: last.date), y: ry)
            coralValue = actual
        }

        return BuiltChart(scaleLine: scaleLine, scaleDots: scaleDots, trendLine: trendLine,
                           ruleY: ruleY, coralCenter: coralCenter, coralValue: coralValue)
    }
}
