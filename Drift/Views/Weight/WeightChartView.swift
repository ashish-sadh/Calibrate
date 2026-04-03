import SwiftUI
import Charts

struct WeightChartView: View {
    let trend: WeightTrendCalculator.WeightTrend?
    let unit: WeightUnit
    let granularity: WeightViewModel.Granularity

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
                // Starting weight reference line (gray, dashed)
                if let startWeight = displayPoints.first?.ema {
                    RuleMark(y: .value("", startWeight))
                        .foregroundStyle(.secondary.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [4, 3]))
                        .annotation(position: .topLeading, spacing: 2) {
                            Text(String(format: "%.1f", startWeight))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary.opacity(0.7))
                                .padding(.horizontal, 3)
                                .background(Theme.cardBackground.opacity(0.8))
                        }
                }

                // Current weight reference line (accent, solid)
                if let currentWeight = displayPoints.last?.ema {
                    RuleMark(y: .value("", currentWeight))
                        .foregroundStyle(Theme.accent.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .bottomTrailing, spacing: 2) {
                            Text(String(format: "%.1f", currentWeight))
                                .font(.caption.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(Theme.cardBackground.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                        }
                }

                // Scale weight points - gray/white, clearly different from trend
                ForEach(displayPoints.indices, id: \.self) { i in
                    if let actual = displayPoints[i].actual {
                        PointMark(x: .value("", displayPoints[i].date), y: .value("", actual))
                            .foregroundStyle(Color.gray)
                            .symbolSize(granularity == .weekly ? 45 : 30)
                            .symbol(.circle)
                    }
                }

                // Trend line - solid purple, clearly distinct
                ForEach(displayPoints.indices, id: \.self) { i in
                    LineMark(x: .value("", displayPoints[i].date), y: .value("", displayPoints[i].ema))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Circle().fill(Color.gray).frame(width: 7, height: 7)
                    Text("Scale Weight").font(.caption2).foregroundStyle(.secondary)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1).fill(Theme.accent).frame(width: 14, height: 2.5)
                    Text("Trend Weight").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .card()
    }

    private var averageWeight: Double {
        let a = displayPoints.compactMap(\.actual)
        guard !a.isEmpty else { return 0 }
        return a.reduce(0, +) / Double(a.count)
    }

    private var totalDifference: Double? {
        guard let f = displayPoints.first?.ema, let l = displayPoints.last?.ema else { return nil }
        return l - f
    }
}
