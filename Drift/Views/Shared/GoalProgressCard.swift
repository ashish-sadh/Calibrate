import SwiftUI
import DriftCore

/// Shared goal progress card used by Dashboard and GoalView.
/// Shows target, progress bar, remaining, start info, and edit link.
struct GoalProgressCard: View {
    let goal: WeightGoal
    let currentWeightKg: Double
    var trendWeightKg: Double? = nil
    @State private var showTrendInfo = false
    @State private var showStartedInfo = false

    private var progress: Double { goal.progress(currentWeightKg: currentWeightKg) }
    private var remaining: Double { goal.remainingKg(currentWeightKg: currentWeightKg) }
    private var unit: WeightUnit { Preferences.weightUnit }

    var body: some View {
        VStack(spacing: 8) {
            // Header: target + days left
            HStack {
                Image(systemName: "target").foregroundStyle(Theme.deficit).font(.caption)
                Text("Goal: \(String(format: "%.1f", unit.convert(fromKg: goal.targetWeightKg))) \(unit.displayName)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let days = goal.daysRemaining {
                    Text("\(days)d left").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.cardBackgroundElevated).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(Theme.accent)
                        .frame(width: max(0, geo.size.width * progress), height: 6)
                }
            }
            .frame(height: 6)

            // Progress % + remaining
            HStack {
                Text("\(Int(progress * 100))% done")
                    .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                Spacer()
                Text("\(String(format: "%.1f", abs(unit.convert(fromKg: remaining)))) \(unit.displayName) to go")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            // Now weight
            HStack(spacing: 4) {
                Text("Now \(String(format: "%.1f", unit.convert(fromKg: currentWeightKg))) \(unit.displayName)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }

            // Trend weight — only when it differs meaningfully
            if let trend = trendWeightKg, abs(trend - currentWeightKg) > 0.5 {
                HStack(spacing: 4) {
                    Text("Trend Weight: \(String(format: "%.1f", unit.convert(fromKg: trend))) \(unit.displayName)")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Button { showTrendInfo = true } label: {
                        Image(systemName: "info.circle").font(.caption2).foregroundStyle(.quaternary)
                    }.buttonStyle(.plain)
                    Spacer()
                }
            }

            // Started weight
            HStack(spacing: 4) {
                Text("Started: \(String(format: "%.1f", unit.convert(fromKg: goal.startWeightKg))) \(unit.displayName)")
                    .font(.caption2).foregroundStyle(.tertiary)
                Button { showStartedInfo = true } label: {
                    Image(systemName: "info.circle").font(.caption2).foregroundStyle(.quaternary)
                }.buttonStyle(.plain)
                if let startDate = DateFormatters.dateOnly.date(from: goal.startDate) {
                    Text("· \(DateFormatters.shortDisplay.string(from: startDate))")
                        .font(.caption2).foregroundStyle(.quaternary)
                }
                Spacer()
            }
        }
        .card()
        .alert("Trend Weight", isPresented: $showTrendInfo) {
            Button("OK") {}
        } message: {
            Text("Your trend weight smooths out daily fluctuations from water, food timing, and scale variance. It shows your true underlying weight direction, not day-to-day noise.")
        }
        .alert("Started Weight", isPresented: $showStartedInfo) {
            Button("OK") {}
        } message: {
            Text("Your weight when you set this goal. Progress is measured from this starting point to your target.")
        }
    }
}
