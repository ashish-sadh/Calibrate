import SwiftUI
import DriftCore

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
                    .accessibilityLabel("Daily average info")
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
            if let targets = WeightGoal.load()?.macroTargets(currentWeightKg: viewModel.trendWeight) {
                // With goal: macro rings + legend
                HStack {
                    Text("Nutrition")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("Today").font(.caption).foregroundStyle(.tertiary)
                }

                // V6 hero: 3 concentric rings (kcal / protein / fiber)
                v6RingsHero(targets: targets)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)

                // Carbs + fat sit below the hero — the V6 reference uses
                // a 2-up legend row for the macros that aren't on the rings.
                // Colors come from Theme.V6 so the strip below the hero
                // matches the Apple-Fitness palette, not the legacy macros.
                HStack(spacing: 12) {
                    macroLegend("Carb", value: viewModel.todayNutrition.carbsG, target: targets.carbsG, color: Theme.V6.ringCarbs, unit: "g")
                    macroLegend("Fat", value: viewModel.todayNutrition.fatG, target: targets.fatG, color: Theme.V6.ringFat, unit: "g")
                }
            } else {
                // No goal: just show eaten + macros chip row
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
        }
        .card()
    }

    /// V6 Apple-Fitness hero: kcal / protein / fiber concentric rings with the
    /// "kcal eaten" V6 numeral in the center. The ring colors come from
    /// `Theme.V6` so this stays additive to the legacy dark palette until V6
    /// landed end-to-end. Carbs and fat live in the legend row below the hero.
    ///
    /// Track colors are V6 tints at 35% opacity — the raw V6 pastels are
    /// designed for the future light theme; on the current dark
    /// `Theme.cardBackground` they would otherwise read as a second filled
    /// ring and bury the actual fill.
    @ViewBuilder
    func v6RingsHero(targets: WeightGoal.MacroTargets) -> some View {
        let nutrition = viewModel.todayNutrition
        let rings: [V6Ring] = [
            V6Ring(label: "kcal", unit: "",
                   value: nutrition.calories, target: targets.calorieTarget,
                   color: Theme.V6.ringMove, trackColor: Theme.V6.ringMoveBg.opacity(0.35)),
            V6Ring(label: "protein", unit: "g",
                   value: nutrition.proteinG, target: targets.proteinG,
                   color: Theme.V6.ringEx, trackColor: Theme.V6.ringExBg.opacity(0.35)),
            V6Ring(label: "fiber", unit: "g",
                   value: nutrition.fiberG, target: targets.fiberG,
                   color: Theme.V6.ringStand, trackColor: Theme.V6.ringStandBg.opacity(0.35)),
        ]
        let kcal = max(0, Int(nutrition.calories.isFinite ? nutrition.calories : 0))
        // Step font down for 4+ digit kcal so a 4500-kcal day doesn't overflow
        // the inner-ring radius. Comma separator from Locale.current so en-IN
        // users see "1,45,000" not "145,000".
        let kcalFont: Font = kcal >= 10_000
            ? .system(size: 22, weight: .bold, design: .rounded).monospacedDigit()
            : kcal >= 1_000
                ? .system(size: 26, weight: .bold, design: .rounded).monospacedDigit()
                : .system(size: 30, weight: .bold, design: .rounded).monospacedDigit()
        VStack(spacing: 10) {
            V6Rings(
                rings: rings,
                size: 180,
                stroke: 16,
                center: AnyView(
                    VStack(spacing: 2) {
                        Text(kcal, format: .number)
                            .font(kcalFont)
                        Text("KCAL")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(.secondary)
                    }
                )
            )
            V6RingLegend(rings: rings)
        }
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

    // MARK: - V6 Body Tile Row

    /// V6 body strip — 3 tiles (Weight / Sleep / Readiness) under the "Body"
    /// section header. Replaces the legacy full-width Weight+Trend card per
    /// `v6-today.jsx` anatomy step 5. Each tile is a single-tap surface that
    /// routes to the existing detail view; the Weight tile carries a
    /// secondary "+" inline button that opens the entry sheet without
    /// triggering the outer tap.
    var v6BodyTileRow: some View {
        let weightPayload = V6BodyTile.weightPayload(
            weightKg: viewModel.latestWeight ?? viewModel.trendWeight,
            weeklyRateKg: viewModel.weeklyRate,
            isStale: WeightTrendService.shared.isStale
        )
        let sleepPayload = V6BodyTile.sleepPayload(hours: viewModel.sleepHours)
        let readinessPayload = V6BodyTile.readinessPayload(
            recoveryScore: viewModel.recoveryScore,
            hrvMs: viewModel.hrvMs
        )
        return HStack(alignment: .top, spacing: 8) {
            V6BodyTile(
                label: weightPayload.label,
                value: weightPayload.value,
                unit: weightPayload.unit,
                delta: weightPayload.delta,
                deltaLabel: weightPayload.deltaLabel,
                tone: Theme.V6.ringMove,
                onTap: { selectedTab = 1 },
                onAdd: { showingWeightEntry = true }
            )
            V6BodyTile(
                label: sleepPayload.label,
                value: sleepPayload.value,
                unit: sleepPayload.unit,
                delta: sleepPayload.delta,
                deltaLabel: sleepPayload.deltaLabel,
                tone: Theme.V6.ringStand,
                onTap: { showingSleepRecovery = true }
            )
            V6BodyTile(
                label: readinessPayload.label,
                value: readinessPayload.value,
                unit: readinessPayload.unit,
                delta: readinessPayload.delta,
                deltaLabel: readinessPayload.deltaLabel,
                tone: Theme.V6.ringEx,
                onTap: { showingSleepRecovery = true }
            )
        }
    }
}
