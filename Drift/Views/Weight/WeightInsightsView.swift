import SwiftUI

struct WeightInsightsView: View {
    let trend: WeightTrendCalculator.WeightTrend
    let unit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Insights & Data")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            // Weight Changes table
            VStack(spacing: 0) {
                Text("Weight Changes")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 6)

                changeRow("3-day", value: trend.weightChanges.threeDay)
                changeRow("7-day", value: trend.weightChanges.sevenDay)
                changeRow("14-day", value: trend.weightChanges.fourteenDay)
                changeRow("30-day", value: trend.weightChanges.thirtyDay)
                changeRow("90-day", value: trend.weightChanges.ninetyDay)
            }
            .card()

            // MacroFactor-style descriptive metric cards
            insightCard(
                value: String(format: "%.1f", unit.convert(fromKg: trend.currentEMA)),
                valueUnit: unit.displayName,
                title: "Current Weight",
                description: "Our estimate of your true weight after smoothing out day-to-day fluctuations.",
                valueColor: .primary
            )

            insightCard(
                value: String(format: "%.2f", unit.convert(fromKg: trend.weeklyRateKg)),
                valueUnit: "\(unit.displayName) per week",
                title: "Weekly Weight Change",
                description: "Your typical weekly rate of weight \(trend.weeklyRateKg < 0 ? "loss" : "change") over the past three weeks.",
                valueColor: trend.weeklyRateKg < -0.05 ? Theme.deficit : trend.weeklyRateKg > 0.05 ? Theme.surplus : .primary
            )

            insightCard(
                value: String(format: "%+.0f", trend.estimatedDailyDeficit),
                valueUnit: "kcal per day",
                title: "Energy \(trend.estimatedDailyDeficit < 0 ? "Deficit" : "Surplus")",
                description: "Our estimate of your average daily caloric \(trend.estimatedDailyDeficit < 0 ? "deficit" : "surplus"), based on your rate of weight \(trend.weeklyRateKg < 0 ? "loss" : "change") over the past three weeks.",
                valueColor: trend.estimatedDailyDeficit < 0 ? Theme.deficit : Theme.surplus
            )

            if let proj = trend.projection30Day {
                insightCard(
                    value: String(format: "%.1f", unit.convert(fromKg: proj)),
                    valueUnit: unit.displayName,
                    title: "30-Day Projection",
                    description: "Your projected weight in 30 days if your current rate of weight \(trend.weeklyRateKg < 0 ? "loss" : "change") continues. Changes in energy intake or expenditure can significantly alter this projection.",
                    valueColor: .primary
                )
            }
        }
    }

    // MARK: - Components

    private func changeRow(_ period: String, value: Double?) -> some View {
        HStack {
            Text(period)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            if let value {
                let d = unit.convert(fromKg: value)
                Text("\(d >= 0 ? "+" : "")\(String(format: "%.1f", d)) \(unit.displayName)")
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(d < -0.01 ? Theme.deficit : d > 0.01 ? Theme.surplus : .primary)
                Spacer()
                Image(systemName: d < -0.01 ? "arrow.down.right" : d > 0.01 ? "arrow.up.right" : "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(d < -0.01 ? Theme.deficit : d > 0.01 ? Theme.surplus : .secondary)
                Text(d < -0.01 ? "Decrease" : d > 0.01 ? "Increase" : "Stable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("--").font(.subheadline).foregroundStyle(.tertiary)
                Spacer()
            }
        }
        .padding(.vertical, 6)
    }

    private func insightCard(value: String, valueUnit: String, title: String, description: String, valueColor: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            // Value box
            VStack(spacing: 2) {
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(valueColor)
                Text(valueUnit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 90)
            .padding(.vertical, 12)
            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))

            // Title + description
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}
