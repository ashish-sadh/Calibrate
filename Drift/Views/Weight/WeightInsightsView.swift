import SwiftUI

struct WeightInsightsView: View {
    let trend: WeightTrendCalculator.WeightTrend
    let unit: WeightUnit
    var isLosing: Bool = true
    @State private var activeTooltip: String?

    private func changeColor(_ value: Double) -> Color {
        let isDecrease = value < -0.01
        let isIncrease = value > 0.01
        if isLosing {
            return isDecrease ? Theme.deficit : isIncrease ? Theme.surplus : .secondary
        } else {
            return isIncrease ? Theme.deficit : isDecrease ? Theme.surplus : .secondary
        }
    }

    private func directionIcon(_ value: Double) -> String {
        value < -0.01 ? "arrow.down.right" : value > 0.01 ? "arrow.up.right" : "arrow.right"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Key metrics — 2×2 compact grid
            HStack(spacing: 8) {
                metricCell(
                    id: "current",
                    label: "Current",
                    value: String(format: "%.1f", unit.convert(fromKg: trend.currentEMA)),
                    valueUnit: unit.displayName,
                    color: .primary,
                    tooltip: "Your true weight after smoothing out day-to-day fluctuations."
                )

                let rate = trend.weeklyRateKg
                metricCell(
                    id: "weekly",
                    label: "Weekly",
                    value: String(format: "%+.2f", unit.convert(fromKg: rate)),
                    valueUnit: "\(unit.displayName)/wk",
                    color: changeColor(rate),
                    direction: directionIcon(rate),
                    directionColor: changeColor(rate),
                    tooltip: "Your typical weekly rate of change over the past \(WeightTrendCalculator.loadConfig().regressionWindowDays) days."
                )
            }

            HStack(spacing: 8) {
                let deficit = trend.estimatedDailyDeficit
                let deficitColor = isLosing
                    ? (deficit < 0 ? Theme.deficit : Theme.surplus)
                    : (deficit > 0 ? Theme.deficit : Theme.surplus)
                metricCell(
                    id: "deficit",
                    label: deficit < 0 ? "Est. Deficit" : "Est. Surplus",
                    value: String(format: "%+.0f", deficit),
                    valueUnit: "kcal/day",
                    color: deficitColor,
                    direction: directionIcon(deficit),
                    directionColor: deficitColor,
                    tooltip: "Estimated daily caloric \(deficit < 0 ? "deficit" : "surplus") based on your weight trend over the past \(WeightTrendCalculator.loadConfig().regressionWindowDays) days."
                )

                if let proj = trend.projection30Day {
                    metricCell(
                        id: "projected",
                        label: "Projected",
                        labelIcon: "chart.line.flattrend.xyaxis",
                        value: String(format: "%.1f", unit.convert(fromKg: proj)),
                        valueUnit: "\(unit.displayName) in 30d",
                        color: .primary,
                        tooltip: "Your projected weight in 30 days if your current rate continues."
                    )
                } else {
                    metricCell(
                        id: "projected",
                        label: "Projected",
                        labelIcon: "chart.line.flattrend.xyaxis",
                        value: "--",
                        valueUnit: "",
                        color: .secondary,
                        tooltip: "Not enough data yet. Keep logging for a few weeks."
                    )
                }
            }

            // Compact weight-change chips
            weightChangesRow
        }
    }

    // MARK: - Metric Cell

    private func metricCell(
        id: String,
        label: String,
        labelIcon: String? = nil,
        value: String,
        valueUnit: String,
        color: Color,
        direction: String? = nil,
        directionColor: Color? = nil,
        tooltip: String
    ) -> some View {
        VStack(spacing: 4) {
            // Label row: icon + label + direction arrow + info
            HStack(spacing: 4) {
                if let labelIcon {
                    Image(systemName: labelIcon)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let direction {
                    Image(systemName: direction)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(directionColor ?? color)
                }
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        activeTooltip = activeTooltip == id ? nil : id
                    }
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle().inset(by: -8))
            }

            // Clean value — signed number only, no arrow
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                if !valueUnit.isEmpty {
                    Text(valueUnit)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Expandable tooltip
            if activeTooltip == id {
                Text(tooltip)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                    .padding(.horizontal, 2)
                    .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
    }

    // MARK: - Weight Changes Row

    private var weightChangesRow: some View {
        HStack(spacing: 0) {
            changeChip("3d", value: trend.weightChanges.threeDay)
            changeChip("7d", value: trend.weightChanges.sevenDay)
            changeChip("14d", value: trend.weightChanges.fourteenDay)
            changeChip("30d", value: trend.weightChanges.thirtyDay)
            changeChip("90d", value: trend.weightChanges.ninetyDay)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
    }

    private func changeChip(_ period: String, value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(period)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let value {
                let d = unit.convert(fromKg: value)
                HStack(spacing: 1) {
                    Image(systemName: directionIcon(value))
                        .font(.caption2.weight(.bold))
                    Text(String(format: "%+.1f", d))
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                .foregroundStyle(changeColor(value))
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
