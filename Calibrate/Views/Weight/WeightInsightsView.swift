import SwiftUI

/// MacroFactor-inspired weight insights panel.
struct WeightInsightsView: View {
    let trend: WeightTrendCalculator.WeightTrend
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Insights & Data")
                .font(.headline)

            // Weight Changes table
            VStack(spacing: 0) {
                Text("Weight Changes")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)

                changeRow("3-day", value: trend.weightChanges.threeDay)
                changeRow("7-day", value: trend.weightChanges.sevenDay)
                changeRow("14-day", value: trend.weightChanges.fourteenDay)
                changeRow("30-day", value: trend.weightChanges.thirtyDay)
                changeRow("90-day", value: trend.weightChanges.ninetyDay)
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            // Key metrics
            HStack(spacing: 12) {
                metricCard(
                    value: String(format: "%.1f", unit.convert(fromKg: trend.currentEMA)),
                    unit: unit.displayName,
                    label: "Current Weight",
                    detail: "Smoothed estimate"
                )

                metricCard(
                    value: String(format: "%.2f", unit.convert(fromKg: trend.weeklyRateKg)),
                    unit: "\(unit.displayName)/week",
                    label: "Weekly Change",
                    detail: trend.trendDirection.displayText
                )
            }

            HStack(spacing: 12) {
                metricCard(
                    value: String(format: "%+.0f", trend.estimatedDailyDeficit),
                    unit: "kcal/day",
                    label: "Energy \(trend.estimatedDailyDeficit < 0 ? "Deficit" : "Surplus")",
                    detail: "From weight trend"
                )

                if let projection = trend.projection30Day {
                    metricCard(
                        value: String(format: "%.1f", unit.convert(fromKg: projection)),
                        unit: unit.displayName,
                        label: "30-Day Projection",
                        detail: "At current rate"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func changeRow(_ period: String, value: Double?) -> some View {
        HStack {
            Text(period)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)

            if let value {
                let display = unit.convert(fromKg: value)
                Text("\(display >= 0 ? "+" : "")\(String(format: "%.1f", display)) \(unit.displayName)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(display < 0 ? .green : display > 0 ? .red : .primary)

                Spacer()

                Image(systemName: display < -0.01 ? "arrow.down.right" : display > 0.01 ? "arrow.up.right" : "arrow.right")
                    .font(.caption)
                    .foregroundStyle(display < -0.01 ? .green : display > 0.01 ? .red : .secondary)

                Text(display < -0.01 ? "Decrease" : display > 0.01 ? "Increase" : "Stable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("--")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private func metricCard(value: String, unit: String, label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.bold().monospacedDigit())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(label)
                .font(.subheadline.bold())
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
