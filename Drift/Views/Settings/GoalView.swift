import SwiftUI
import Charts

struct GoalView: View {
    @State private var goal: WeightGoal? = WeightGoal.load()
    @State private var showingSetup = false
    @State private var currentWeightKg: Double?
    @State private var actualWeeklyRate: Double?
    @State private var actualDailyDeficit: Double?
    private let database = AppDatabase.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let goal {
                    goalProgressCard(goal)
                    macroTargetsCard(goal)
                    paceCard(goal)
                    deficitCard(goal)
                    projectionCard(goal)

                    Button {
                        WeightGoal.clear()
                        self.goal = nil
                    } label: {
                        Text("Clear Goal")
                            .font(.caption)
                            .foregroundStyle(Theme.surplus.opacity(0.7))
                    }
                    .padding(.top, 8)
                } else {
                    emptyState
                }

                Button { showingSetup = true } label: {
                    Label(goal == nil ? "Set Weight Goal" : "Update Goal", systemImage: "target")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Weight Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showingSetup) {
            GoalSetupView(existingGoal: goal) { newGoal in
                newGoal.save()
                goal = newGoal
            }
        }
        .onAppear {
            goal = WeightGoal.load()
            loadCurrentData()
        }
    }

    // MARK: - Progress

    private func goalProgressCard(_ goal: WeightGoal) -> some View {
        let progress = currentWeightKg.map { goal.progress(currentWeightKg: $0) } ?? 0
        let unit = Preferences.weightUnit

        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Goal").font(.caption).foregroundStyle(.secondary)
                    Text("\(String(format: "%.1f", unit.convert(fromKg: goal.targetWeightKg))) \(unit.displayName)")
                        .font(.title2.weight(.bold).monospacedDigit())
                }
                Spacer()
                if let days = goal.daysRemaining {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(days)").font(.title2.weight(.bold).monospacedDigit())
                        Text("days left").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.cardBackgroundElevated)
                            .frame(height: 8)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.accent)
                            .frame(width: max(0, geo.size.width * progress), height: 8)
                    }
                }
                .frame(height: 8)

                HStack {
                    Text("\(String(format: "%.1f", unit.convert(fromKg: goal.startWeightKg)))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(Theme.accent)
                    Spacer()
                    Text("\(String(format: "%.1f", unit.convert(fromKg: goal.targetWeightKg)))")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }

            if let current = currentWeightKg {
                let remaining = goal.remainingKg(currentWeightKg: current)
                Text("\(String(format: "%.1f", abs(unit.convert(fromKg: remaining)))) \(unit.displayName) to go")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: - Macro Targets

    private func macroTargetsCard(_ goal: WeightGoal) -> some View {
        let targets = goal.macroTargets(currentWeightKg: currentWeightKg, actualTDEE: estimatedTDEE())
        let pref = goal.dietPreference ?? .balanced
        let weight = currentWeightKg ?? goal.startWeightKg

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Daily Targets").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(pref.displayName).font(.caption.weight(.medium)).foregroundStyle(Theme.accent)
            }

            if let t = targets {
                HStack(spacing: 8) {
                    targetPill("\(Int(t.calorieTarget))", label: "kcal", color: Theme.accent)
                    targetPill("\(Int(t.proteinG))g", label: "Protein", color: Theme.proteinRed)
                    targetPill("\(Int(t.carbsG))g", label: "Carbs", color: Theme.carbsGreen)
                    targetPill("\(Int(t.fatG))g", label: "Fat", color: Theme.fatYellow)
                }
                let fatMin = WeightGoal.minimumFatG(bodyweightKg: weight, calorieTarget: t.calorieTarget)
                if t.fatG <= fatMin + 3 {
                    Text("Fat at minimum (\(Int(fatMin))g) for hormonal health")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                Text("Set a calorie target or log weight + food to see macro targets")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    private func targetPill(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Pace

    private func paceCard(_ goal: WeightGoal) -> some View {
        let unit = Preferences.weightUnit
        let status = actualWeeklyRate.map { goal.isOnTrack(actualWeeklyRateKg: $0) } ?? .onTrack
        let statusColor: Color = status == .behind ? Theme.surplus : Theme.deficit

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pace").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(status.label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(statusColor)
            }

            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    Text("Required")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text(String(format: "%.2f", unit.convert(fromKg: goal.requiredWeeklyRateKg)))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text("\(unit.displayName)/wk")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()

                VStack(spacing: 3) {
                    Text("Actual")
                        .font(.caption2).foregroundStyle(.tertiary)
                    if let rate = actualWeeklyRate {
                        Text(String(format: "%.2f", unit.convert(fromKg: rate)))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(statusColor)
                    } else {
                        Text("--").font(.subheadline.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    Text("\(unit.displayName)/wk")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()
            }
        }
    }

    // MARK: - Deficit

    private func deficitCard(_ goal: WeightGoal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Target").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(spacing: 3) {
                    Text("Target").font(.caption2).foregroundStyle(.tertiary)
                    Text(String(format: "%+.0f", goal.requiredDailyDeficit))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(goal.requiredDailyDeficit < 0 ? Theme.deficit : Theme.surplus)
                    Text("kcal/day").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()

                VStack(spacing: 3) {
                    Text("Actual").font(.caption2).foregroundStyle(.tertiary)
                    if let deficit = actualDailyDeficit {
                        Text(String(format: "%+.0f", deficit))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                            .foregroundStyle(deficit < 0 ? Theme.deficit : Theme.surplus)
                    } else {
                        Text("--").font(.subheadline.weight(.bold)).foregroundStyle(.tertiary)
                    }
                    Text("kcal/day").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()
            }
        }
    }

    // MARK: - Projection

    private func projectionCard(_ goal: WeightGoal) -> some View {
        let unit = Preferences.weightUnit

        return VStack(alignment: .leading, spacing: 8) {
            Text("Projection").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            if let rate = actualWeeklyRate, let current = currentWeightKg, abs(rate) > 0.01 {
                let weeksToGoal = abs(goal.remainingKg(currentWeightKg: current) / rate)
                let projectedDate = Calendar.current.date(byAdding: .day, value: Int(weeksToGoal * 7), to: Date())

                HStack(spacing: 12) {
                    VStack(spacing: 3) {
                        Text("At current pace").font(.caption2).foregroundStyle(.tertiary)
                        if let date = projectedDate {
                            Text(DateFormatters.shortDisplay.string(from: date))
                                .font(.subheadline.weight(.bold))
                        }
                        Text("\(Int(weeksToGoal)) weeks").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity).card()

                    VStack(spacing: 3) {
                        Text("Goal date").font(.caption2).foregroundStyle(.tertiary)
                        if let date = goal.targetDate {
                            Text(DateFormatters.shortDisplay.string(from: date))
                                .font(.subheadline.weight(.bold))
                        }
                        if let weeks = goal.weeksRemaining {
                            Text("\(Int(weeks)) weeks").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity).card()
                }

                if let projected = projectedDate, let target = goal.targetDate {
                    let diff = Calendar.current.dateComponents([.day], from: target, to: projected).day ?? 0
                    if diff < -7 {
                        Text("You'll reach your goal \(abs(diff)) days early at this pace")
                            .font(.caption).foregroundStyle(Theme.deficit)
                    } else if diff > 7 {
                        Text("You're \(diff) days behind schedule — increase deficit or extend timeline")
                            .font(.caption).foregroundStyle(Theme.surplus)
                    } else {
                        Text("Right on schedule")
                            .font(.caption).foregroundStyle(Theme.deficit)
                    }
                }
            } else {
                Text("Need more weight data to project")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "target")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.5))
            Text("No Goal Set").font(.headline)
            Text("Set a target weight and timeline to track your deficit and see if you're on pace.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.top, 40)
    }

    private func estimatedTDEE() -> Double? {
        // Prefer actual burn from Apple Health if available
        // For goal view, use the daily deficit from trend as a proxy:
        // TDEE ≈ intake - deficit (if we have both)
        // Fallback: use calorie override if set
        if let goal = goal, let override = goal.calorieTargetOverride {
            return override - goal.requiredDailyDeficit
        }
        return nil
    }

    private func loadCurrentData() {
        do {
            let entries = try database.fetchWeightEntries()
            let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
            if let trend = WeightTrendCalculator.calculateTrend(entries: input) {
                currentWeightKg = trend.currentEMA
                actualWeeklyRate = trend.weeklyRateKg
                actualDailyDeficit = trend.estimatedDailyDeficit
            }
        } catch {
            Log.app.error("Failed to load weight data for goal: \(error.localizedDescription)")
        }
    }
}

// MARK: - Goal Setup Sheet

struct GoalSetupView: View {
    let existingGoal: WeightGoal?
    let onSave: (WeightGoal) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var targetWeight: String = ""
    @State private var months: Int = 3
    @State private var unit: WeightUnit = Preferences.weightUnit
    @State private var dietPref: DietPreference = .balanced
    @State private var calorieTarget: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Target Weight") {
                    HStack {
                        TextField("0.0", text: $targetWeight)
                            .keyboardType(.decimalPad)
                            .font(.title2.monospacedDigit())
                        Picker("", selection: $unit) {
                            Text("kg").tag(WeightUnit.kg)
                            Text("lbs").tag(WeightUnit.lbs)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                }

                Section("Diet Style") {
                    ForEach(DietPreference.allCases, id: \.self) { pref in
                        Button {
                            dietPref = pref
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pref.displayName).font(.subheadline)
                                    Text(pref.subtitle).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if pref == dietPref {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }.tint(.primary)
                    }
                }

                Section {
                    HStack {
                        Text("Daily calories")
                        Spacer()
                        TextField("auto", text: $calorieTarget)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("kcal").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calorie Target")
                } footer: {
                    Text("Leave blank to estimate from Apple Health activity data. Set a number if you know your daily intake target.")
                }

                Section("Timeline") {
                    Stepper("\(months) month\(months == 1 ? "" : "s")", value: $months, in: 1...24)

                    if let target = Double(targetWeight) {
                        let targetKg = unit.convertToKg(target)
                        let currentKg = getCurrentWeight()
                        if let current = currentKg {
                            let change = targetKg - current
                            let weeks = Double(months) * 4.33
                            let weeklyRate = change / weeks
                            let config = WeightTrendCalculator.loadConfig()
                            let dailyDeficit = weeklyRate * config.kcalPerKg / 7

                            let calOverride = Double(calorieTarget)
                            let previewGoal = WeightGoal(targetWeightKg: targetKg, monthsToAchieve: months,
                                                        startDate: DateFormatters.todayString,
                                                        startWeightKg: current, dietPreference: dietPref,
                                                        calorieTargetOverride: calOverride)
                            let macros = previewGoal.macroTargets(currentWeightKg: current)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("This means:")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                Text("\u{2022} \(String(format: "%.2f", unit.convert(fromKg: weeklyRate))) \(unit.displayName)/week")
                                    .font(.caption)
                                Text("\u{2022} \(String(format: "%+.0f", dailyDeficit)) kcal/day \(dailyDeficit < 0 ? "deficit" : "surplus")")
                                    .font(.caption)
                                if let m = macros {
                                    Text("\u{2022} \(Int(m.calorieTarget)) kcal/day target")
                                        .font(.caption)
                                    Text("\u{2022} \(Int(m.proteinG))g protein \u{00B7} \(Int(m.carbsG))g carbs \u{00B7} \(Int(m.fatG))g fat")
                                        .font(.caption).foregroundStyle(Theme.accent)
                                } else {
                                    Text("\u{2022} Set a calorie target above to see macro breakdown")
                                        .font(.caption).foregroundStyle(.tertiary)
                                }
                                if abs(dailyDeficit) > 1000 {
                                    Text("Aggressive — consider extending the timeline")
                                        .font(.caption).foregroundStyle(Theme.surplus)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Set Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let target = Double(targetWeight) else { return }
                        let targetKg = unit.convertToKg(target)
                        let currentKg = getCurrentWeight() ?? targetKg

                        let calOverride = Double(calorieTarget)
                        let goal = WeightGoal(
                            targetWeightKg: targetKg,
                            monthsToAchieve: months,
                            startDate: DateFormatters.todayString,
                            startWeightKg: existingGoal?.startWeightKg ?? currentKg,
                            dietPreference: dietPref,
                            calorieTargetOverride: calOverride
                        )
                        onSave(goal)
                        dismiss()
                    }
                    .disabled(Double(targetWeight) == nil)
                }
            }
            .onAppear {
                if let g = existingGoal {
                    targetWeight = String(format: "%.1f", unit.convert(fromKg: g.targetWeightKg))
                    months = g.monthsToAchieve
                    dietPref = g.dietPreference ?? .balanced
                    if let cal = g.calorieTargetOverride { calorieTarget = "\(Int(cal))" }
                }
            }
        }
    }

    private func getCurrentWeight() -> Double? {
        let entries = try? AppDatabase.shared.fetchWeightEntries()
        let input = (entries ?? []).map { (date: $0.date, weightKg: $0.weightKg) }
        return WeightTrendCalculator.calculateTrend(entries: input)?.currentEMA
    }
}
