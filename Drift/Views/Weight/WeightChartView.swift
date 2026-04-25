import SwiftUI
import DriftCore
import Charts

struct WeightChartView: View {
    let trend: WeightTrendCalculator.WeightTrend?
    let unit: WeightUnit
    let granularity: WeightViewModel.Granularity
    var rawEntries: [WeightEntry] = []  // all entries (unfiltered) for average calculation

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
            }

            Chart {
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

                // Single clean line — EMA trend with dots at each point
                ForEach(displayPoints.indices, id: \.self) { i in
                    LineMark(x: .value("", displayPoints[i].date), y: .value("", displayPoints[i].ema))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                    PointMark(x: .value("", displayPoints[i].date), y: .value("", displayPoints[i].ema))
                        .foregroundStyle(.white.opacity(0.8))
                        .symbolSize(granularity == .weekly ? 30 : 16)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(.tertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) {
                    AxisValueLabel().foregroundStyle(.tertiary)
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
}
