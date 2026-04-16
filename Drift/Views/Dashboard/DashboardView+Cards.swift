import SwiftUI

// MARK: - TDEE Card + Calorie Balance Card

extension DashboardView {

    // MARK: - TDEE Card

    var tdeeCard: some View {
        let est = TDEEEstimator.shared.cachedOrSync()
        let goal = WeightGoal.load()
        let target = goal?.macroTargets(currentWeightKg: viewModel.trendWeight)
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

            // Target line — uses latest weight to match goal card display
            if let t = target, let goal, let cw = viewModel.latestWeight ?? viewModel.trendWeight {
                let remainingAbs = abs(unit.convert(fromKg: goal.remainingKg(currentWeightKg: cw)))
                let losing = goal.isLosing(currentWeightKg: cw)
                let hasCustomMacros = goal.proteinTargetG != nil || goal.carbsTargetG != nil || goal.fatTargetG != nil
                // When custom macros are set, calorie target is user-chosen — don't imply it directly causes the weight change
                let targetText = hasCustomMacros
                    ? "Target: \(Int(t.calorieTarget)) kcal/day · \(String(format: "%.1f", remainingAbs)) \(unit.displayName) to \(losing ? "lose" : "gain")"
                    : "Target: eat \(Int(t.calorieTarget)) kcal/day to \(losing ? "lose" : "gain") \(String(format: "%.1f", remainingAbs)) \(unit.displayName)"
                Text(targetText)
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Expandable detail (only when we have actual data to explain)
            if showDeficitExplainer, (goal != nil || viewModel.weeklyRate != nil) {
                VStack(alignment: .leading, spacing: 6) {
                    if let goal {
                        let currentKg = viewModel.trendWeight ?? goal.startWeightKg
                        let required = goal.requiredDailyDeficit(currentWeightKg: currentKg)
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

    var hasLoggedFood: Bool { viewModel.todayNutrition.calories > 0 }

    var calorieBalanceCard: some View {
        VStack(spacing: 10) {
            if hasLoggedFood {
                if let targets = WeightGoal.load()?.macroTargets(currentWeightKg: viewModel.trendWeight) {
                    // With goal: macro rings + legend
                    HStack {
                        Text("Nutrition")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text("Today").font(.caption).foregroundStyle(.tertiary)
                    }

                    // Macro rings hero
                    MacroRingsView(
                        calories: viewModel.todayNutrition.calories,
                        calorieTarget: targets.calorieTarget,
                        protein: viewModel.todayNutrition.proteinG,
                        proteinTarget: targets.proteinG,
                        carbs: viewModel.todayNutrition.carbsG,
                        carbsTarget: targets.carbsG,
                        fat: viewModel.todayNutrition.fatG,
                        fatTarget: targets.fatG
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                    // Ring legend
                    HStack(spacing: 12) {
                        macroLegend("Cal", value: viewModel.todayNutrition.calories, target: targets.calorieTarget, color: Theme.calorieBlue, unit: "")
                        macroLegend("Pro", value: viewModel.todayNutrition.proteinG, target: targets.proteinG, color: Theme.proteinRed, unit: "g")
                        macroLegend("Carb", value: viewModel.todayNutrition.carbsG, target: targets.carbsG, color: Theme.carbsGreen, unit: "g")
                        macroLegend("Fat", value: viewModel.todayNutrition.fatG, target: targets.fatG, color: Theme.fatYellow, unit: "g")
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

    private func macroLegend(_ label: String, value: Double, target: Double, color: Color, unit: String) -> some View {
        VStack(spacing: 2) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(Int(value))\(unit)")
                .font(.caption2.weight(.bold).monospacedDigit())
                .foregroundStyle(value >= target ? color : .primary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }

    func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))g \(label)")
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    func macroChipWithTarget(_ label: String, value: Double, target: Double, color: Color) -> some View {
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
    /// Uses CURRENT weight vs target for direction — not stale startWeightKg.
    func isGoalAligned(_ deficit: Double) -> Bool {
        guard let goal = WeightGoal.load() else { return deficit < 0 }
        let currentKg = viewModel.trendWeight ?? goal.startWeightKg
        let losing = goal.isLosing(currentWeightKg: currentKg)
        return losing ? deficit < 0 : deficit > 0
    }

    func macroPill(_ label: String, value: Double, color: Color) -> some View {
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
}
