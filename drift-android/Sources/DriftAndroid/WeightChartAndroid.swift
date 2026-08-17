import SwiftUI
import DriftCore

/// Path-based weight chart for the Android Body tab (#1092) — SkipUI has no
/// Charts/Canvas (skip_fuse_is_the_availability_tree), so this replicates
/// `Drift/Views/Weight/WeightChartView.swift` (dashed current-weight rule,
/// thin Scale reading line + dots, hero goal-aware Trend/EMA line, coral
/// latest-value dot) as merged `Path`s. `points` is already range-filtered by
/// the caller — v1 re-windows via the range chips rather than iOS's
/// chartScrollableAxes pan (SkipUI HScroll/GeometryReader-per-frame traps;
/// see #1092 plan).
struct WeightChartAndroid: View {
    let points: [WeightChartSeries.Point]
    let unit: WeightUnit
    let goalChangeKg: Double?
    /// Weekly aggregation plots far fewer readings, so iOS grows the scale
    /// marker (symbolSize 26 vs 14, `WeightChartView.swift:182`); mirror that.
    var isWeekly: Bool = false

    private var averageWeight: Double {
        let actuals = points.compactMap(\.actual)
        if !actuals.isEmpty { return actuals.reduce(0, +) / Double(actuals.count) }
        guard !points.isEmpty else { return 0 }
        return points.map(\.ema).reduce(0, +) / Double(points.count)
    }

    /// Trend (EMA) endpoints over the visible window — matches
    /// `WeightChartView.totalDifference` (the smoothed net movement, not a
    /// raw first-vs-last actual comparison).
    private var totalDifference: Double? {
        guard let f = points.first?.ema, let l = points.last?.ema else { return nil }
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
            WeightChartPlot(points: points, trendColor: trendColor, isWeekly: isWeekly)
                .frame(height: 165)
            if let f = points.first?.date, let l = points.last?.date {
                HStack {
                    Text(DateFormatters.shortDisplay.string(from: f))
                    Spacer()
                    Text(DateFormatters.shortDisplay.string(from: l))
                }
                .font(.caption2).foregroundStyle(Theme.textSecondary)
                .padding(.trailing, 30)
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
    let points: [WeightChartSeries.Point]
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

    private var yDomain: (lo: Double, hi: Double)? {
        let values = points.compactMap(\.actual) + points.map(\.ema)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        let pad = max(0.5, (hi - lo) * 0.12)
        return (lo - pad, hi + pad)
    }

    private var yAxisLabels: some View {
        VStack {
            if let d = yDomain {
                Text(String(format: "%.0f", d.hi))
                Spacer()
                Text(String(format: "%.0f", d.lo))
            }
        }
        .font(.caption2).foregroundStyle(Theme.textSecondary)
    }

    @ViewBuilder
    private func plotLayer(in size: CGSize) -> some View {
        if let chart = Self.cachedChart(points: points, size: size, isWeekly: isWeekly) {
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

    private static func cachedChart(points: [WeightChartSeries.Point], size: CGSize, isWeekly: Bool) -> BuiltChart? {
        guard points.count >= 2, size.width > 0, size.height > 0 else { return nil }
        let key = "\(Int(size.width))x\(Int(size.height))|\(points.count)|\(isWeekly)"
            + "|\(points.first?.date.timeIntervalSince1970 ?? 0)"
            + "|\(points.last?.date.timeIntervalSince1970 ?? 0)"
            + "|\(points.last?.ema ?? 0)|\(points.last?.actual ?? -1)"
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = cache[key] { return cached }
        let built = build(points: points, size: size, isWeekly: isWeekly)
        cache[key] = built
        return built
    }

    private static func build(points: [WeightChartSeries.Point], size: CGSize, isWeekly: Bool) -> BuiltChart? {
        let values = points.compactMap(\.actual) + points.map(\.ema)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        let pad = max(0.5, (hi - lo) * 0.12)
        let yLo = lo - pad
        let yRange = max(0.001, (hi + pad) - yLo)

        let firstDate = points[0].date
        let lastDate = points[points.count - 1].date
        let span = max(1, lastDate.timeIntervalSince(firstDate))
        // 4% trailing pad so the coral dot/label never sits flush on the
        // right edge (WeightChartView.trailingPadSeconds precedent).
        let effectiveWidth = size.width / 1.04

        // A lone weigh-in has no span to spread across — centre it instead of
        // pinning the dot to x=0 against the left edge.
        let singlePoint = points.count == 1
        func x(for date: Date) -> CGFloat {
            guard !singlePoint else { return effectiveWidth / 2 }
            return CGFloat(date.timeIntervalSince(firstDate) / span) * effectiveWidth
        }
        func y(for value: Double) -> CGFloat {
            size.height - CGFloat((value - yLo) / yRange) * size.height
        }

        var scaleLine = Path()
        var scaleDots = Path()
        var scaleStarted = false
        let dotRadius: CGFloat = isWeekly ? 2.6 : 1.9
        for p in points {
            guard let actual = p.actual else { continue }
            let pt = CGPoint(x: x(for: p.date), y: y(for: actual))
            if scaleStarted { scaleLine.addLine(to: pt) } else { scaleLine.move(to: pt); scaleStarted = true }
            scaleDots.addEllipse(in: CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius,
                                             width: dotRadius * 2, height: dotRadius * 2))
        }

        var trendLine = Path()
        for (i, p) in points.enumerated() {
            let pt = CGPoint(x: x(for: p.date), y: y(for: p.ema))
            if i == 0 { trendLine.move(to: pt) } else { trendLine.addLine(to: pt) }
        }

        var ruleY: CGFloat?
        var coralCenter: CGPoint?
        var coralValue: Double?
        if let last = points.last(where: { $0.actual != nil }), let actual = last.actual {
            let ry = y(for: actual)
            ruleY = ry
            coralCenter = CGPoint(x: x(for: last.date), y: ry)
            coralValue = actual
        }

        return BuiltChart(scaleLine: scaleLine, scaleDots: scaleDots, trendLine: trendLine,
                           ruleY: ruleY, coralCenter: coralCenter, coralValue: coralValue)
    }
}
