import SwiftUI
import DriftCore
import Charts

struct WeightChartView: View {
    let trend: WeightTrendCalculator.WeightTrend?
    let unit: WeightUnit
    let granularity: WeightViewModel.Granularity
    var rawEntries: [WeightEntry] = []
    var rangeStart: Date? = nil
    var dailyCaloriesByDate: [String: Double] = [:]
    var showCaloriesOverlay: Bool = false

    @State private var selectedPoint: (date: Date, value: Double)? = nil

    private var displayPoints: [(date: Date, actual: Double?, ema: Double)] {
        guard let trend else { return [] }
        if granularity == .weekly { return weeklyAggregated(trend.dataPoints) }
        return trend.dataPoints.map {
            ($0.date, $0.actualWeight.map { unit.convert(fromKg: $0) }, unit.convert(fromKg: $0.emaWeight))
        }
    }

    private func weeklyAggregated(_ points: [WeightTrendCalculator.WeightDataPoint]) -> [(date: Date, actual: Double?, ema: Double)] {
        let calendar = Calendar.current
        var weeks: [Date: (actuals: [Double], emas: [Double])] = [:]
        for p in points {
            let ws = calendar.dateInterval(of: .weekOfYear, for: p.date)?.start ?? p.date
            if let a = p.actualWeight { weeks[ws, default: ([], [])].actuals.append(a) }
            weeks[ws, default: ([], [])].emas.append(p.emaWeight)
        }
        return weeks.sorted { $0.key < $1.key }.map { ws, data in
            let avgA = data.actuals.isEmpty ? nil : unit.convert(fromKg: data.actuals.reduce(0, +) / Double(data.actuals.count))
            let avgE = data.emas.isEmpty ? 0 : unit.convert(fromKg: data.emas.reduce(0, +) / Double(data.emas.count))
            return (ws, avgA, avgE)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if trend != nil {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Average").font(.caption2).foregroundStyle(.tertiary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(String(format: "%.1f", averageWeight)).font(.title2.weight(.bold).monospacedDigit())
                            Text(unit.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if let diff = totalDifference {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Difference").font(.caption2).foregroundStyle(.tertiary)
                            Text("\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff)) \(unit.displayName)")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(diff < 0 ? Theme.deficit : diff > 0 ? Theme.surplus : .secondary)
                        }
                    }
                }

                if let f = displayPoints.first?.date, let l = displayPoints.last?.date {
                    Text("\(DateFormatters.shortDisplay.string(from: f)) – \(DateFormatters.shortDisplay.string(from: l))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }

                // Toggle is ON but no bars rendered = no calorie data in
                // chart range. Without this caption, tapping the flame looks
                // like a silent no-op (most pronounced at 1W/1M when the
                // user hasn't logged calories yet for the visible window).
                if showCaloriesOverlay && scaledCalorieBars() == nil {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent.opacity(0.7))
                        Text("No calories logged in this range — log meals to see the overlay.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Chart {
                // Optional calorie bars in the background — scaled to fit the
                // weight Y range so a single scale renders cleanly. The
                // trailing axis labels show calories explicitly so the
                // shared scale isn't read as weight.
                if showCaloriesOverlay, let calBars = scaledCalorieBars() {
                    ForEach(calBars, id: \.date) { bar in
                        BarMark(
                            x: .value("", bar.date),
                            yStart: .value("", bar.scaledMin),
                            yEnd: .value("", bar.scaledMax)
                        )
                        // 0.18 was too faint on dark theme — users reported
                        // "I tap the flame and nothing happens". Bumped to
                        // 0.35 so sparse-day bars are visibly purple against
                        // the background without competing with the EMA line.
                        .foregroundStyle(Theme.accent.opacity(0.35))
                        .cornerRadius(2)
                    }
                }

                // Current value reference line (accent, horizontal)
                if let currentWeight = displayPoints.last?.ema {
                    RuleMark(y: .value("", currentWeight))
                        .foregroundStyle(Theme.accent.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .annotation(position: .trailing, spacing: 4) {
                            Text(String(format: "%.1f", currentWeight))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                        }
                }

                // Single clean line — EMA trend with dots at each point.
                // V7 light migration: was .white.opacity which rendered
                // invisible on the white card. Coral line + dots match
                // the reference design and read on paper-white.
                ForEach(displayPoints.indices, id: \.self) { i in
                    LineMark(x: .value("", displayPoints[i].date), y: .value("", displayPoints[i].ema))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("", displayPoints[i].date), y: .value("", displayPoints[i].ema))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(granularity == .weekly ? 30 : 16)
                }

                // Selected point callout
                if let sel = selectedPoint {
                    PointMark(x: .value("", sel.date), y: .value("", sel.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(80)
                        .annotation(position: .top, spacing: 6) {
                            VStack(spacing: 2) {
                                Text(sel.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
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
                            .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                        }
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXScale(domain: (rangeStart ?? displayPoints.first?.date ?? Date())...Date())
            .chartXAxis {
                // V7: include day so a single-day range doesn't render
                // "May May May" — when displayPoints all sit in one
                // month the formatter would otherwise emit identical
                // labels across desiredCount=4 ticks.
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) {
                    AxisValueLabel().foregroundStyle(Theme.textSecondary)
                }
                if showCaloriesOverlay, let bars = scaledCalorieBars() {
                    AxisMarks(position: .leading, values: leadingAxisTicks(bars: bars)) { value in
                        if let scaled = value.as(Double.self),
                           let cal = unscaleCalorie(value: scaled, bars: bars) {
                            AxisValueLabel { Text("\(Int(cal))").font(.caption2) }
                                .foregroundStyle(Theme.accent.opacity(0.7))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let origin = geo[proxy.plotAreaFrame].origin
                                    let location = CGPoint(
                                        x: value.location.x - origin.x,
                                        y: value.location.y - origin.y
                                    )
                                    if let date: Date = proxy.value(atX: location.x, as: Date.self),
                                       let nearest = displayPoints.min(by: {
                                           abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                       }) {
                                        selectedPoint = (nearest.date, nearest.ema)
                                    }
                                }
                                .onEnded { _ in selectedPoint = nil }
                        )
                }
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
        guard let f = displayPoints.first?.ema, let l = displayPoints.last?.ema else { return nil }
        return l - f
    }

    // MARK: - Calorie overlay helpers (#669)

    private struct ScaledCalorieBar {
        let date: Date
        let calories: Double
        let scaledMin: Double  // bar bottom — bottom of weight Y range
        let scaledMax: Double  // bar top — calories projected onto weight Y range
    }

    private struct CalorieScaling {
        let weightLow: Double
        let weightHigh: Double
        let maxCalories: Double
    }

    private func calorieScaling() -> CalorieScaling? {
        let weights = displayPoints.map(\.ema) + displayPoints.compactMap(\.actual)
        guard let lo = weights.min(), let hi = weights.max(), hi > lo else { return nil }
        let cals = dailyCaloriesByDate.values.filter { $0 > 0 }
        guard let maxCal = cals.max(), maxCal > 0 else { return nil }
        // Pad weight range so calorie bars don't paint over weight extremes.
        let pad = max(0.5, (hi - lo) * 0.1)
        return CalorieScaling(weightLow: lo - pad, weightHigh: hi + pad, maxCalories: maxCal)
    }

    private func scaledCalorieBars() -> [ScaledCalorieBar]? {
        guard let scaling = calorieScaling() else { return nil }
        let span = scaling.weightHigh - scaling.weightLow
        return dailyCaloriesByDate.compactMap { entry in
            guard entry.value > 0, let date = DateFormatters.dateOnly.date(from: entry.key) else { return nil }
            let frac = entry.value / scaling.maxCalories
            let top = scaling.weightLow + frac * span
            return ScaledCalorieBar(date: date, calories: entry.value, scaledMin: scaling.weightLow, scaledMax: top)
        }.sorted { $0.date < $1.date }
    }

    private func leadingAxisTicks(bars: [ScaledCalorieBar]) -> [Double] {
        guard let scaling = calorieScaling() else { return [] }
        let span = scaling.weightHigh - scaling.weightLow
        return [0.0, 0.5, 1.0].map { scaling.weightLow + $0 * span }
    }

    private func unscaleCalorie(value scaledY: Double, bars: [ScaledCalorieBar]) -> Double? {
        guard let scaling = calorieScaling() else { return nil }
        let span = scaling.weightHigh - scaling.weightLow
        guard span > 0 else { return nil }
        let frac = (scaledY - scaling.weightLow) / span
        return frac * scaling.maxCalories
    }
}
