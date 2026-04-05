import SwiftUI

struct DashboardView: View {
    @Binding var syncComplete: Bool
    @Binding var selectedTab: Int
    @State private var viewModel = DashboardViewModel()
    @State private var showDeficitExplainer = false
    @AppStorage("drift_ai_enabled") private var aiEnabled = false

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

                    // Apple Health Workouts — show if any today
                    if !viewModel.todayWorkouts.isEmpty {
                        Button { selectedTab = 3 } label: { workoutCard }.buttonStyle(.plain)
                    }

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
                ToolbarItem(placement: .navigationBarTrailing) {
                    Toggle(isOn: $aiEnabled) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .scaleEffect(0.6)
                    .tint(Theme.accent)
                    .frame(width: 44)
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

        let deficit = viewModel.dailyDeficit ?? 0
        let tdee = est.tdee
        let trendIntake = tdee + deficit
        let consistency = viewModel.foodLogConsistency
        let loggedIntake = viewModel.avgDailyIntake
        let useFoodLogs = consistency >= 0.5 && loggedIntake > 500
            && abs(loggedIntake - trendIntake) < trendIntake * 0.4
        let intake = viewModel.dailyDeficit != nil ? (useFoodLogs ? loggedIntake : trendIntake) : 0
        let ringFraction = intake > 0 ? min(1.0, max(0, intake / max(1, tdee))) : 0
        let deficitLabel = deficit < -5 ? "deficit" : deficit > 5 ? "surplus" : "balanced"

        return VStack(spacing: 12) {
            // Section header
            HStack {
                Text("Daily Average").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("14-day").font(.caption2).foregroundStyle(.tertiary)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showDeficitExplainer.toggle() }
                    } label: {
                        Image(systemName: "info.circle").font(.caption).foregroundStyle(.tertiary)
                    }
                }
            }

            // Centered ring: eating / deficit / burning (or just TDEE if no trend)
            if viewModel.dailyDeficit == nil {
                // No weight trend — just show TDEE estimate
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(tdee))")
                            .font(.title.weight(.bold).monospacedDigit())
                        Text("kcal/day").font(.caption).foregroundStyle(.tertiary)
                    }
                    Text("Est. Expenditure").font(.caption).foregroundStyle(.secondary)
                    Text("Log weight to see energy balance").font(.caption2).foregroundStyle(.quaternary)
                }
                .padding(.vertical, 8)
            } else if viewModel.dailyDeficit != nil {
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("~\(Int(intake))")
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("eating")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)

                    ZStack {
                        Circle()
                            .stroke(Theme.cardBackgroundElevated, lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: ringFraction)
                            .stroke(isGoalAligned(deficit) ? Theme.deficit : Theme.surplus,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text("\(Int(abs(deficit)))")
                                .font(.title3.weight(.bold).monospacedDigit())
                            Text(deficitLabel)
                                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                            Text("/day")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: 88, height: 88)

                    VStack(spacing: 2) {
                        Text("\(Int(tdee))")
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text("burning")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Target line
            if let t = target, let goal {
                let remaining = abs(unit.convert(fromKg: goal.totalChangeKg))
                let isLosing = goal.totalChangeKg < 0
                Text("Target: eat \(Int(t.calorieTarget)) kcal to \(isLosing ? "lose" : "gain") \(String(format: "%.1f", remaining)) \(unit.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Expandable detail (only when we have actual data to explain)
            if showDeficitExplainer, (goal != nil || viewModel.weeklyRate != nil) {
                VStack(alignment: .leading, spacing: 6) {
                    if let goal {
                        let required = goal.requiredDailyDeficit
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text("Required").font(.caption2).foregroundStyle(.tertiary)
                                Text("\(required < 0 ? "" : "+")\(Int(required))")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(isGoalAligned(required) ? Theme.deficit : Theme.surplus)
                            }
                            VStack(spacing: 2) {
                                Text("Current").font(.caption2).foregroundStyle(.tertiary)
                                Text("\(deficit < 0 ? "" : "+")\(Int(deficit))")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(isGoalAligned(deficit) ? Theme.deficit : Theme.surplus)
                            }
                            Text("kcal/day").font(.caption2).foregroundStyle(.quaternary)
                        }
                    }
                    if let rate = viewModel.weeklyRate {
                        let config = WeightTrendCalculator.loadConfig()
                        Text("Trend: \(String(format: "%+.2f", Preferences.weightUnit.convert(fromKg: rate))) \(Preferences.weightUnit.displayName)/wk → \(String(format: "%+.0f", deficit)) kcal/day")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Text("Based on \(config.regressionWindowDays)-day weight trend.")
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                }
                .transition(.opacity)
            }

            // Data sources
            HStack(spacing: 4) {
                ForEach(est.activeSources, id: \.self) { source in
                    Text(source)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                }
                Spacer()
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

    // MARK: - Apple Health Workouts

    private var workoutCard: some View {
        let workouts = viewModel.todayWorkouts
        let totalCal = Int(workouts.reduce(0) { $0 + $1.calories })
        let latest = workouts.first

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.circle.fill").foregroundStyle(Theme.stepsOrange)
                Text("Workouts").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.stepsOrange)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }

            if let w = latest {
                Text("You burned \(totalCal) calories during \(workouts.count == 1 ? "your last workout" : "\(workouts.count) workouts").")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(workouts.prefix(3)) { w in
                    HStack(spacing: 10) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title3).foregroundStyle(Theme.stepsOrange)
                            .frame(width: 36, height: 36)
                            .background(Theme.stepsOrange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.type).font(.caption.weight(.semibold))
                            HStack(spacing: 8) {
                                Text(w.durationDisplay).font(.caption2.monospacedDigit())
                                Text("\(Int(w.calories)) cal").font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .card()
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
                            Image(systemName: "waveform.path").font(.caption).foregroundStyle(Theme.deficit)
                            Text("\(Int(viewModel.hrvMs))ms").font(.caption2.monospacedDigit())
                        }
                    }
                    if viewModel.restingHR > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.heartRed)
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
