import SwiftUI
import Charts

struct WeightChartView: View {
    let trend: WeightTrendCalculator.WeightTrend
    let unit: WeightUnit

    private var displayPoints: [(date: Date, actual: Double?, ema: Double)] {
        trend.dataPoints.map { point in
            (
                date: point.date,
                actual: point.actualWeight.map { unit.convert(fromKg: $0) },
                ema: unit.convert(fromKg: point.emaWeight)
            )
        }
    }

    private var averageWeight: Double {
        let actuals = displayPoints.compactMap(\.actual)
        guard !actuals.isEmpty else { return 0 }
        return actuals.reduce(0, +) / Double(actuals.count)
    }

    private var totalDifference: Double? {
        guard let first = displayPoints.first?.ema,
              let last = displayPoints.last?.ema else { return nil }
        return last - first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with average and difference
            HStack {
                VStack(alignment: .leading) {
                    Text("Average")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", averageWeight)) \(unit.displayName)")
                        .font(.title2.bold())
                }

                Spacer()

                if let diff = totalDifference {
                    VStack(alignment: .trailing) {
                        Text("Difference")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff)) \(unit.displayName)")
                            .font(.title2.bold())
                            .foregroundStyle(diff < 0 ? .green : diff > 0 ? .red : .primary)
                    }
                }
            }

            // Chart
            Chart {
                // Scale weight points
                ForEach(displayPoints.indices, id: \.self) { i in
                    let point = displayPoints[i]
                    if let actual = point.actual {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Weight", actual)
                        )
                        .foregroundStyle(.purple.opacity(0.5))
                        .symbolSize(20)
                    }
                }

                // Trend line
                ForEach(displayPoints.indices, id: \.self) { i in
                    let point = displayPoints[i]
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Trend", point.ema)
                    )
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }

            // Legend
            HStack(spacing: 16) {
                Label("Scale Weight", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.purple.opacity(0.5))
                Label("Trend Weight", systemImage: "line.diagonal")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }
        }
    }
}
