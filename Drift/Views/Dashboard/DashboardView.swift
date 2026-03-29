import SwiftUI

struct DashboardView: View {
    @Binding var syncComplete: Bool
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Weight + Deficit (always primary)
                    weightDeficitCard

                    // Goal progress
                    goalCard

                    // Energy Balance (prominent if food logged, muted if not)
                    calorieBalanceCard

                    // Health row
                    healthRow

                    // Sleep & Recovery mini
                    if viewModel.sleepHours > 0 {
                        sleepRecoveryCard
                    }

                    // Supplements
                    if viewModel.supplementsTotal > 0 {
                        supplementCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Drift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await viewModel.loadToday() }
            .refreshable { await viewModel.loadToday() }
            .onChange(of: syncComplete) { _, done in
                if done { Task { await viewModel.loadToday() } }
            }
        }
    }

    // MARK: - Calorie Balance + Macros (combined)

    private var hasLoggedFood: Bool { viewModel.todayNutrition.calories > 0 }

    private var calorieBalanceCard: some View {
        VStack(spacing: 10) {
            if hasLoggedFood {
                // Active state: food logged
                HStack {
                    Text("Energy Balance")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Today").font(.caption).foregroundStyle(.tertiary)
                }

                HStack(spacing: 0) {
                    calorieColumn(value: Int(viewModel.todayNutrition.calories), label: "Eaten", color: Theme.calorieBlue)
                    Spacer()
                    Text("\u{2212}").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    calorieColumn(value: Int(viewModel.caloriesBurned), label: "Burned", color: Theme.stepsOrange)
                    Spacer()
                    Text("=").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    let balance = Int(viewModel.calorieBalance)
                    calorieColumn(
                        value: abs(balance),
                        label: balance <= 0 ? "Deficit" : "Surplus",
                        color: balance <= 0 ? Theme.deficit : Theme.surplus,
                        prefix: balance < 0 ? "-" : "+"
                    )
                }

                // Inline macros
                HStack(spacing: 6) {
                    macroChip("P", value: viewModel.todayNutrition.proteinG, color: Theme.proteinRed)
                    macroChip("C", value: viewModel.todayNutrition.carbsG, color: Theme.carbsGreen)
                    macroChip("F", value: viewModel.todayNutrition.fatG, color: Theme.fatYellow)
                    macroChip("Fiber", value: viewModel.todayNutrition.fiberG, color: Theme.fiberBrown)
                }
            } else {
                // Muted state: no food logged
                HStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No food logged today")
                            .font(.subheadline).foregroundStyle(.tertiary)
                        Text("Log meals to see energy balance and macros")
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                    Spacer()
                }
            }
        }
        .card()
    }

    private func calorieColumn(value: Int, label: String, color: Color, prefix: String = "") -> some View {
        VStack(spacing: 2) {
            Text("\(prefix)\(value)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(minWidth: 50)
    }

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))g \(label)")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }

    // MARK: - Weight + Deficit

    private var weightDeficitCard: some View {
        HStack(spacing: 12) {
            // Current weight
            VStack(alignment: .leading, spacing: 4) {
                Label("Weight", systemImage: "scalemass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let w = viewModel.currentWeight {
                    Text(String(format: "%.1f", Preferences.weightUnit.convert(fromKg: w)))
                        .font(.title.weight(.bold).monospacedDigit())
                    Text(Preferences.weightUnit.displayName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("--")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            // Weekly rate + deficit
            VStack(alignment: .leading, spacing: 4) {
                Label("Trend", systemImage: "chart.line.downtrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let rate = viewModel.weeklyRate {
                    let display = Preferences.weightUnit.convert(fromKg: rate)
                    Text(String(format: "%+.2f", display))
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(rate < 0 ? Theme.deficit : rate > 0 ? Theme.surplus : .primary)
                    Text("\(Preferences.weightUnit.displayName)/wk")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("--")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: - Macros

    // macroCard removed - macros now inline in calorieBalanceCard

    private func macroPill(_ label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(Int(value))g")
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Health

    private var healthRow: some View {
        HStack(spacing: 12) {
            healthPill(icon: "flame.fill", value: "\(Int(viewModel.activeCalories))", label: "Active", color: Theme.stepsOrange)
            healthPill(icon: "figure.walk", value: formatSteps(viewModel.steps), label: "Steps", color: Theme.deficit)
        }
    }

    private func healthPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func formatSteps(_ steps: Double) -> String {
        if steps >= 1000 {
            return String(format: "%.1fk", steps / 1000)
        }
        return "\(Int(steps))"
    }

    // MARK: - Goal

    private var goalCard: some View {
        Group {
            if let goal = WeightGoal.load(), let current = viewModel.currentWeight {
                let progress = goal.progress(currentWeightKg: current)
                let remaining = goal.remainingKg(currentWeightKg: current)
                let unit = Preferences.weightUnit

                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "target").foregroundStyle(Theme.deficit).font(.caption)
                        Text("Goal: \(String(format: "%.1f", unit.convert(fromKg: goal.targetWeightKg))) \(unit.displayName)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let days = goal.daysRemaining {
                            Text("\(days)d left").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(Theme.cardBackgroundElevated).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3).fill(Theme.accent)
                                .frame(width: max(0, geo.size.width * progress), height: 6)
                        }
                    }
                    .frame(height: 6)

                    HStack {
                        Text("\(Int(progress * 100))% done")
                            .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                        Spacer()
                        Text("\(String(format: "%.1f", abs(unit.convert(fromKg: remaining)))) \(unit.displayName) to go")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Supplements

    // MARK: - Sleep & Recovery

    private var sleepRecoveryCard: some View {
        HStack(spacing: 10) {
            // Sleep
            VStack(spacing: 3) {
                Image(systemName: "bed.double.fill").font(.caption).foregroundStyle(Theme.sleepIndigo)
                Text(String(format: "%.1fh", viewModel.sleepHours))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text("Sleep").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).card()

            // Recovery
            let recoveryColor: Color = viewModel.recoveryLevel == .green ? Theme.deficit : viewModel.recoveryLevel == .yellow ? Theme.fatYellow : Theme.surplus
            VStack(spacing: 3) {
                Image(systemName: "heart.circle.fill").font(.caption).foregroundStyle(recoveryColor)
                Text("\(viewModel.recoveryScore)%")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(recoveryColor)
                Text("Recovery").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).card()

            // HRV
            if viewModel.hrvMs > 0 {
                VStack(spacing: 3) {
                    Image(systemName: "waveform.path").font(.caption).foregroundStyle(Theme.deficit)
                    Text("\(Int(viewModel.hrvMs))ms")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text("HRV").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).card()
            }

            // RHR
            if viewModel.restingHR > 0 {
                VStack(spacing: 3) {
                    Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.heartRed)
                    Text("\(Int(viewModel.restingHR))")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text("RHR").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).card()
            }
        }
    }

    // MARK: - Supplements

    private var supplementCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "pill.fill")
                .foregroundStyle(.mint)
            Text("Supplements")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(viewModel.supplementsTaken)/\(viewModel.supplementsTotal)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(viewModel.supplementsTaken == viewModel.supplementsTotal ? Theme.deficit : .secondary)
            Text("taken")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}
