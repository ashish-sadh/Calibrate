import SwiftUI

struct DashboardView: View {
    @Binding var syncComplete: Bool
    @State private var viewModel = DashboardViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Calorie Balance
                    calorieBalanceCard

                    // Weight + Deficit
                    weightDeficitCard

                    // Goal progress
                    goalCard

                    // Macros
                    macroCard

                    // Health row
                    healthRow

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
            .navigationTitle("Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await viewModel.loadToday() }
            .refreshable { await viewModel.loadToday() }
            .onChange(of: syncComplete) { _, done in
                if done { Task { await viewModel.loadToday() } }
            }
        }
    }

    // MARK: - Calorie Balance

    private var calorieBalanceCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Energy Balance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Today")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 0) {
                calorieColumn(value: Int(viewModel.todayNutrition.calories), label: "Eaten", color: Theme.calorieBlue)
                Spacer()
                Text("\u{2212}")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                calorieColumn(value: Int(viewModel.caloriesBurned), label: "Burned", color: Theme.stepsOrange)
                Spacer()
                Text("=")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                let balance = Int(viewModel.calorieBalance)
                calorieColumn(
                    value: abs(balance),
                    label: balance <= 0 ? "Deficit" : "Surplus",
                    color: balance <= 0 ? Theme.deficit : Theme.surplus,
                    prefix: balance < 0 ? "-" : "+"
                )
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
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 50)
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

    private var macroCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Macros")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 10) {
                macroPill("P", value: viewModel.todayNutrition.proteinG, color: Theme.proteinRed)
                macroPill("C", value: viewModel.todayNutrition.carbsG, color: Theme.carbsGreen)
                macroPill("F", value: viewModel.todayNutrition.fatG, color: Theme.fatYellow)
                macroPill("Fiber", value: viewModel.todayNutrition.fiberG, color: Theme.fiberBrown)
            }
        }
        .card()
    }

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
            healthPill(icon: "bed.double.fill", value: String(format: "%.1fh", viewModel.sleepHours), label: "Sleep", color: Theme.sleepIndigo)
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
