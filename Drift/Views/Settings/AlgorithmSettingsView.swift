import SwiftUI

struct AlgorithmSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = WeightTrendCalculator.loadConfig()
    @State private var tdeeConfig = TDEEEstimator.loadConfig()
    @State private var refreshKey = 0

    /// Live weight trend recomputed with current config.
    private var liveTrend: WeightTrendCalculator.WeightTrend? {
        let db = AppDatabase.shared
        guard let entries = try? db.fetchWeightEntries(from: nil), !entries.isEmpty else { return nil }
        let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
        return WeightTrendCalculator.calculateTrend(entries: input, config: config)
    }

    /// Live TDEE — reads from the shared estimator (same source as all other views).
    /// Falls back to live formula when cache is stale from slider changes.
    private var liveTDEE: Int {
        let _ = refreshKey
        let cached = TDEEEstimator.shared.cachedOrSync()
        // If source is bodyWeight, recompute with current slider values for instant feedback
        if cached.source == .bodyWeight {
            let db = AppDatabase.shared
            let weight = (try? db.fetchWeightEntries(from: nil))?.first?.weightKg ?? 75
            return Int(max(800, 200 + weight * tdeeConfig.activityMultiplier + tdeeConfig.manualAdjustment))
        }
        return Int(cached.tdee)
    }

    /// Live calorie target based on goal + live TDEE.
    private var liveCalorieTarget: Int? {
        guard let goal = WeightGoal.load() else { return nil }
        if goal.calorieTargetOverride != nil { return Int(goal.calorieTargetOverride!) }
        return Int(max(800, Double(liveTDEE) + goal.requiredDailyDeficit))
    }

    /// Live estimated deficit from weight trend + current energy density config.
    private var liveDeficit: Int? {
        guard let trend = liveTrend else { return nil }
        return Int(trend.estimatedDailyDeficit)
    }

    private var activePreset: String? {
        if isPreset(.conservative) { return "conservative" }
        if isPreset(.default) { return "balanced" }
        if isPreset(.responsive) { return "responsive" }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // TDEE
                VStack(spacing: 6) {
                    Text("Your TDEE").font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(liveTDEE)")
                            .font(.system(size: 36, weight: .bold).monospacedDigit())
                        Text("kcal/day").font(.caption).foregroundStyle(.tertiary)
                    }

                    if let target = liveCalorieTarget {
                        let goal = WeightGoal.load()
                        let adj = goal?.requiredDailyDeficit ?? 0
                        VStack(spacing: 4) {
                            HStack(spacing: 4) {
                                Text("Calorie target:")
                                    .font(.caption2).foregroundStyle(.tertiary)
                                Text("\(target) kcal")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Theme.accent)
                                Text(adj < 0
                                     ? "(TDEE \u{2212} \(Int(abs(adj))) for weight loss)"
                                     : adj > 0 ? "(TDEE + \(Int(adj)) to gain)" : "(maintenance)")
                                    .font(.caption2).foregroundStyle(.quaternary)
                            }
                            NavigationLink { GoalView() } label: {
                                Text("Update goal").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                    } else {
                        NavigationLink { GoalView() } label: {
                            Text("Set a weight goal to see calorie target")
                                .font(.caption2).foregroundStyle(Theme.accent)
                        }
                    }
                }
                .card()

                // Weight trend info
                if let deficit = liveDeficit, let trend = liveTrend {
                    let unit = Preferences.weightUnit
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weight Trend").font(.caption2).foregroundStyle(.tertiary)
                            HStack(spacing: 4) {
                                Text(deficit < 0 ? "Est. Deficit" : "Est. Surplus")
                                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                Text("\(deficit) kcal/day")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(deficit < 0 ? Theme.deficit : Theme.surplus)
                            }
                        }
                        Spacer()
                        Text("\(String(format: "%+.2f", unit.convert(fromKg: trend.weeklyRateKg))) \(unit.displayName)/wk")
                            .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                }

                // Activity Level
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Activity Level").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(tdeeConfig.activityLabel)
                            .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                    }
                    Slider(value: $tdeeConfig.activityMultiplier, in: 22...36, step: 1)
                        .tint(Theme.accent)
                    HStack {
                        Text("Sedentary").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        if tdeeConfig.activityMultiplier != 29 {
                            Button { tdeeConfig.activityMultiplier = 29 } label: {
                                Text("Reset").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        Spacer()
                        Text("Athlete").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text("Blended into your TDEE (15% when Apple Health data exists, 100% without). As Apple Health collects more resting energy and step data, this matters less.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .card()

                // Manual adjustment
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("TDEE Adjustment").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(tdeeConfig.manualAdjustment >= 0
                             ? "+\(Int(tdeeConfig.manualAdjustment))"
                             : "\(Int(tdeeConfig.manualAdjustment))")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(tdeeConfig.manualAdjustment != 0 ? Theme.accent : .secondary)
                    }
                    Slider(value: $tdeeConfig.manualAdjustment, in: -500...500, step: 25)
                        .tint(Theme.accent)
                    HStack {
                        Text("-500").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        if tdeeConfig.manualAdjustment != 0 {
                            Button {
                                tdeeConfig.manualAdjustment = 0
                            } label: {
                                Text("Reset").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        Spacer()
                        Text("+500").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text("Applies on top of all sources. Use if your TDEE doesn't match other tools or expected burn rate.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .card()

                // Estimation Style presets
                VStack(alignment: .leading, spacing: 10) {
                    Text("Estimation Style").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

                    presetRow("Conservative",
                              detail: "Smoother trend, cautious estimates.",
                              isSelected: activePreset == "conservative") {
                        config = .conservative; tdeeConfig.appleHealthTrust = 1.0
                    }
                    presetRow("Balanced",
                              detail: "Good for most. Reacts in 2–3 weeks.",
                              isSelected: activePreset == "balanced") {
                        config = .default; tdeeConfig.appleHealthTrust = 1.0
                    }
                    presetRow("Responsive",
                              detail: "Fastest reaction. Best with daily weighing.",
                              isSelected: activePreset == "responsive") {
                        config = .responsive; tdeeConfig.appleHealthTrust = 1.0
                    }
                }
                .card()

                // Reset all
                if tdeeConfig.activityMultiplier != 29 || tdeeConfig.manualAdjustment != 0
                    || activePreset != "balanced" {
                    Button {
                        config = .default
                        tdeeConfig = .default
                        save()
                    } label: {
                        Text("Reset All to Defaults")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.surplus.opacity(0.7))
                    }
                }

                // How it works
                VStack(alignment: .leading, spacing: 8) {
                    Text("How it works").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Drift estimates your Total Daily Energy Expenditure (TDEE) from three sources, blended by availability:")
                        .font(.caption2).foregroundStyle(.tertiary)
                    howItWorksRow("1", "Apple Health", "Resting + active energy (7-day avg). More accurate with Apple Watch. iPhone alone may underestimate.")
                    howItWorksRow("2", "Weight + Food", "Adaptive: intake − weight change. Most accurate with consistent logging.")
                    howItWorksRow("3", "Body Weight", "Fallback: weight × activity level")
                    Text("Your calorie target = TDEE + goal deficit/surplus. Energy density auto-adjusts for diet duration.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.top, 2)
                }
                .card()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Algorithm")
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .onChange(of: tdeeConfig.activityMultiplier) { _, _ in save() }
        .onChange(of: tdeeConfig.manualAdjustment) { _, _ in save() }
        .onChange(of: tdeeConfig.appleHealthTrust) { _, _ in save() }
        .onChange(of: config.emaAlpha) { _, _ in save() }
    }

    // MARK: - Auto-save

    private func save() {
        WeightTrendCalculator.saveConfig(config)
        TDEEEstimator.saveConfig(tdeeConfig) // clears cached estimate
        _ = TDEEEstimator.shared.cachedOrSync() // immediate recompute (trend + fallback)
        refreshKey += 1
        // Also trigger async refresh for Apple Health blend
        Task {
            await TDEEEstimator.shared.refresh()
            refreshKey += 1
        }
    }

    // MARK: - Components

    private func presetRow(_ name: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            save()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isSelected ? Theme.accent : Color.gray.opacity(0.4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).font(.subheadline.weight(.medium))
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func howItWorksRow(_ num: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.caption2.weight(.bold)).foregroundStyle(Theme.accent)
                .frame(width: 16, height: 16)
                .background(Theme.accent.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func isPreset(_ preset: WeightTrendCalculator.AlgorithmConfig) -> Bool {
        abs(config.emaAlpha - preset.emaAlpha) < 0.001 &&
        config.regressionWindowDays == preset.regressionWindowDays &&
        abs(config.kcalPerKg - preset.kcalPerKg) < 1
    }
}
