import SwiftUI

struct DashboardView: View {
    @Binding var syncComplete: Bool
    @Binding var selectedTab: Int
    @State private var viewModel = DashboardViewModel()
    @State private var showDeficitExplainer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Weight + Deficit + Estimated deficit as tiles → Weight tab
                    Button { selectedTab = 1 } label: {
                        HStack(spacing: 12) {
                            // Left column: Weight
                            VStack(alignment: .leading, spacing: 2) {
                                Label("Weight", systemImage: "scalemass").font(.caption).foregroundStyle(.secondary)
                                if let w = viewModel.currentWeight {
                                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                                        Text(String(format: "%.1f", Preferences.weightUnit.convert(fromKg: w)))
                                            .font(.title2.weight(.bold).monospacedDigit())
                                        Text(Preferences.weightUnit.displayName).font(.caption2).foregroundStyle(.tertiary)
                                    }
                                } else {
                                    Text("--").font(.title2.weight(.bold)).foregroundStyle(.tertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(viewModel.currentWeight.map {
                                "Weight: \(String(format: "%.1f", Preferences.weightUnit.convert(fromKg: $0))) \(Preferences.weightUnit.displayName)"
                            } ?? "Weight: no data")

                            // Right column: Trend only (deficit moved to TDEE card)
                            VStack(alignment: .leading, spacing: 2) {
                                Label("Trend", systemImage: "chart.line.downtrend.xyaxis").font(.caption).foregroundStyle(.secondary)
                                if let rate = viewModel.weeklyRate {
                                    let display = Preferences.weightUnit.convert(fromKg: rate)
                                    let good = isGoalAligned(rate < 0 ? -1 : 1)
                                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                                        Text(String(format: "%+.2f", display))
                                            .font(.title2.weight(.bold).monospacedDigit())
                                            .foregroundStyle(good ? Theme.deficit : Theme.surplus)
                                        Text("\(Preferences.weightUnit.displayName)/wk").font(.caption2).foregroundStyle(.tertiary)
                                    }
                                } else {
                                    Text("--").font(.title2.weight(.bold)).foregroundStyle(.tertiary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .card()
                    }.buttonStyle(.plain)

                    // Goal progress → Goal page
                    NavigationLink { GoalView() } label: { goalCard }.tint(.primary)

                    // TDEE → Algorithm settings
                    NavigationLink { AlgorithmSettingsView() } label: { tdeeCard }.tint(.primary)

                    // Nutrition → Food tab
                    Button { selectedTab = 2 } label: { calorieBalanceCard }.buttonStyle(.plain)

                    // Active/Steps → Exercise tab
                    Button { selectedTab = 3 } label: { healthRow }.buttonStyle(.plain)

                    // Body Rhythm → SleepRecoveryView (always visible)
                    NavigationLink { SleepRecoveryView() } label: { sleepRecoveryCard }

                    // Supplements — show if any configured
                    if viewModel.supplementsTotal > 0 {
                        NavigationLink { SupplementsTabView() } label: { supplementCard }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "d.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                        Text("Drift")
                            .font(.headline.weight(.bold))
                    }
                }
            }
            .task { await viewModel.loadToday() }
            .refreshable { await viewModel.loadToday() }
            .onChange(of: syncComplete) { _, done in
                if done { Task { await viewModel.loadToday() } }
            }
        }
    }

    // MARK: - TDEE Card

    private var tdeeCard: some View {
        let est = TDEEEstimator.shared.cachedOrSync()
        let goal = WeightGoal.load()
        let target = goal?.macroTargets(currentWeightKg: viewModel.currentWeight)
        let unit = Preferences.weightUnit

        return VStack(spacing: 8) {
            // Row 1: TDEE + Target
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Est. Expenditure", systemImage: "flame").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(est.tdee))")
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("kcal/day").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if let t = target, let goal {
                    let remaining = abs(unit.convert(fromKg: goal.totalChangeKg))
                    let isLosing = goal.totalChangeKg < 0
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("eat to \(isLosing ? "lose" : "gain") \(String(format: "%.1f", remaining)) \(unit.displayName)")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(Int(t.calorieTarget))")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(Theme.accent)
                            Text("kcal").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            // Row 2: Energy balance bar (only when avg intake data exists)
            if viewModel.avgDailyIntake > 500 {
                let tdee = est.tdee
                let intake = viewModel.avgDailyIntake
                let deficit = intake - tdee
                let barFraction = min(1.0, max(0, intake / tdee))

                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // TDEE (full bar, muted)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.cardBackgroundElevated)
                                .frame(height: 8)
                            // Avg intake (partial fill)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(deficit < 0 ? Theme.calorieBlue : Theme.stepsOrange)
                                .frame(width: max(0, geo.size.width * barFraction), height: 8)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text("\(Int(intake)) avg intake")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(deficit < 0 ? "" : "+")\(Int(deficit)) /day")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(isGoalAligned(deficit) ? Theme.deficit : Theme.surplus)
                    }
                }
            }

            // Row 3: Required vs Current with explainer
            if let goal {
                let required = goal.requiredDailyDeficit
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Text("Required").font(.system(size: 9)).foregroundStyle(.tertiary)
                            Text("\(required < 0 ? "" : "+")\(Int(required))")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(isGoalAligned(required) ? Theme.deficit : Theme.surplus)
                        }
                        if let deficit = viewModel.dailyDeficit {
                            HStack(spacing: 4) {
                                Text("Current").font(.system(size: 9)).foregroundStyle(.tertiary)
                                Text("\(deficit < 0 ? "" : "+")\(Int(deficit))")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(isGoalAligned(deficit) ? Theme.deficit : Theme.surplus)
                            }
                        }
                        Text("kcal/day").font(.system(size: 9)).foregroundStyle(.quaternary)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showDeficitExplainer.toggle() }
                        } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                    }

                    if showDeficitExplainer {
                        let config = WeightTrendCalculator.loadConfig()
                        VStack(alignment: .leading, spacing: 3) {
                            if let rate = viewModel.weeklyRate {
                                Text("Your weight trend: \(String(format: "%+.2f", Preferences.weightUnit.convert(fromKg: rate))) \(Preferences.weightUnit.displayName)/wk")
                                    .font(.caption2).foregroundStyle(.secondary)
                                if let deficit = viewModel.dailyDeficit {
                                    Text("= \(String(format: "%+.0f", rate * config.kcalPerKg / 7)) kcal/day (\(String(format: "%.0f", config.kcalPerKg)) kcal per \(Preferences.weightUnit == .kg ? "kg" : "lb equivalent"))")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Text("Based on \(config.regressionWindowDays)-day weight trend, not activity data.")
                                .font(.caption2).foregroundStyle(.quaternary)
                        }
                        .padding(.top, 2)
                        .transition(.opacity)
                    }
                }
            }

            // Row 4: Data sources
            HStack(spacing: 4) {
                ForEach(est.activeSources, id: \.self) { source in
                    Text(source)
                        .font(.system(size: 9).weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                }
                Spacer()
                if est.confidence == .low {
                    Text("Add data to improve")
                        .font(.system(size: 9)).foregroundStyle(.quaternary)
                }
            }
        }
        .card()
    }

    // MARK: - Calorie Balance + Macros (combined)

    private var hasLoggedFood: Bool { viewModel.todayNutrition.calories > 0 }

    private var calorieBalanceCard: some View {
        VStack(spacing: 10) {
            if hasLoggedFood {
                if let targets = WeightGoal.load()?.macroTargets(currentWeightKg: viewModel.currentWeight) {
                    // With goal: progress bar + remaining
                    let eaten = Int(viewModel.todayNutrition.calories)
                    let target = Int(targets.calorieTarget)
                    let remaining = target - eaten
                    let progress = min(Double(eaten) / Double(target), 1.5)

                    HStack {
                        Text("Nutrition")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("Today").font(.caption).foregroundStyle(.tertiary)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.cardBackgroundElevated)
                                .frame(height: 8)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(remaining >= 0 ? Theme.calorieBlue : Theme.surplus)
                                .frame(width: max(0, geo.size.width * progress), height: 8)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text("\(eaten)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.calorieBlue)
                        Text("/ \(target) kcal")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(remaining >= 0 ? "\(remaining) left" : "\(abs(remaining)) over")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(remaining >= 0 ? Theme.deficit : Theme.surplus)
                    }

                    HStack(spacing: 6) {
                        macroChipWithTarget("P", value: viewModel.todayNutrition.proteinG, target: targets.proteinG, color: Theme.proteinRed)
                        macroChipWithTarget("C", value: viewModel.todayNutrition.carbsG, target: targets.carbsG, color: Theme.carbsGreen)
                        macroChipWithTarget("F", value: viewModel.todayNutrition.fatG, target: targets.fatG, color: Theme.fatYellow)
                    }
                } else {
                    // No goal: just show eaten + macros
                    HStack {
                        Text("Nutrition")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("Today").font(.caption).foregroundStyle(.tertiary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(Int(viewModel.todayNutrition.calories))")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.calorieBlue)
                        Text("kcal eaten").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        macroChip("P", value: viewModel.todayNutrition.proteinG, color: Theme.proteinRed)
                        macroChip("C", value: viewModel.todayNutrition.carbsG, color: Theme.carbsGreen)
                        macroChip("F", value: viewModel.todayNutrition.fatG, color: Theme.fatYellow)
                        macroChip("Fiber", value: viewModel.todayNutrition.fiberG, color: Theme.fiberBrown)
                    }
                }
            } else {
                // Muted state: no food logged
                HStack(spacing: 10) {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No food logged today")
                            .font(.subheadline).foregroundStyle(.tertiary)
                        Text("Log meals to see nutrition and macros")
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                    Spacer()
                }
            }
        }
        .card()
    }

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))g \(label)")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func macroChipWithTarget(_ label: String, value: Double, target: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))/\(Int(target))g \(label)")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(value >= target ? color : .secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Weight + Deficit

    /// Is this deficit/surplus aligned with the user's goal?
    private func isGoalAligned(_ deficit: Double) -> Bool {
        let goal = WeightGoal.load()
        let isLosing = goal.map { $0.totalChangeKg < 0 } ?? true
        return isLosing ? deficit < 0 : deficit > 0
    }

    // MARK: - Macros

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
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
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No weight goal set")
                            .font(.subheadline).foregroundStyle(.tertiary)
                        Text("Set a goal to see calorie targets and track progress")
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                    Spacer()
                }
                .card()
            }
        }
    }

    // MARK: - Supplements

    // MARK: - Sleep & Recovery

    private var sleepRecoveryCard: some View {
        let hasData = viewModel.sleepHours > 0 || viewModel.recoveryScore > 0 || viewModel.hrvMs > 0 || viewModel.restingHR > 0

        return VStack(spacing: 8) {
            if hasData {
                // Recovery + Sleep scores
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery").font(.caption).foregroundStyle(.secondary)
                        Text("\(viewModel.recoveryScore)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.scoreColor(viewModel.recoveryScore))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Theme.cardBackgroundElevated).frame(height: 4)
                                RoundedRectangle(cornerRadius: 2).fill(Theme.scoreColor(viewModel.recoveryScore))
                                    .frame(width: geo.size.width * Double(viewModel.recoveryScore) / 100, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sleep").font(.caption).foregroundStyle(.secondary)
                        Text(viewModel.sleepHours > 0 ? String(format: "%.1fh", viewModel.sleepHours) : "--")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(viewModel.sleepHours > 0 ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    if viewModel.hrvMs > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform.path").font(.system(size: 9)).foregroundStyle(Theme.deficit)
                            Text("\(Int(viewModel.hrvMs))ms").font(.caption2.monospacedDigit())
                        }
                    }
                    if viewModel.restingHR > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill").font(.system(size: 9)).foregroundStyle(Theme.heartRed)
                            Text("\(Int(viewModel.restingHR))bpm").font(.caption2.monospacedDigit())
                        }
                    }
                    Spacer()
                    Text("Last night").font(.caption2).foregroundStyle(.quaternary)
                }
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body Rhythm")
                            .font(.subheadline).foregroundStyle(.tertiary)
                        Text("Sleep, recovery, and vitals from Apple Health")
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                    Spacer()
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasData
            ? "Recovery \(viewModel.recoveryScore) percent, Sleep \(viewModel.sleepHours > 0 ? String(format: "%.1f hours", viewModel.sleepHours) : "no data")"
            : "Body Rhythm: no data from Apple Health")
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
