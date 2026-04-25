import SwiftUI
import DriftCore

struct AlgorithmSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var config = WeightTrendCalculator.loadConfig()
    @State private var tdeeConfig = TDEEEstimator.loadConfig()
    @State private var refreshKey = 0
    @State private var expandedSection: String?
    @State private var showAdvanced = false
    @State private var ahResting: Double = 0
    @State private var ahActive: Double = 0
    @State private var ahSteps: Double = 0
    @FocusState private var isFieldFocused: Bool

    // MARK: - Computed (unchanged)

    private var liveTrend: WeightTrendCalculator.WeightTrend? {
        WeightTrendService.shared.trendForRange(days: 90, config: config)
    }

    private func input(_ entries: [WeightEntry]) -> [(date: String, weightKg: Double)] {
        entries.map { (date: $0.date, weightKg: $0.weightKg) }
    }

    /// Always reads from the shared estimator — same number as Dashboard.
    /// save() clears the cache, cachedOrSync() recomputes, refreshKey triggers re-render.
    private var liveTDEE: Int {
        let _ = refreshKey
        return Int(TDEEEstimator.shared.cachedOrSync().tdee)
    }

    private var liveCalorieTarget: Int? {
        guard let goal = WeightGoal.load() else { return nil }
        if goal.calorieTargetOverride != nil { return Int(goal.calorieTargetOverride!) }
        let currentKg = WeightTrendService.shared.latestWeightKg ?? goal.startWeightKg
        return Int(max(800, TDEEEstimator.shared.cachedOrSync().tdee + goal.requiredDailyDeficit(currentWeightKg: currentKg)))
    }

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

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // 1. TDEE Hero
                heroCard

                // 2. Compact expandable controls
                VStack(spacing: 0) {
                    accordionRow(id: "activity", icon: "figure.run", label: "Activity Level",
                                 value: tdeeConfig.activityLabel) { activityContent }
                    Divider().overlay(Color.white.opacity(0.05))
                    accordionRow(id: "profile", icon: "person.crop.circle", label: "Profile",
                                 value: profileSummary) { profileContent }
                    Divider().overlay(Color.white.opacity(0.05))
                    accordionRow(id: "finetune", icon: "slider.horizontal.3", label: "Fine-tune",
                                 value: tdeeConfig.manualAdjustment == 0 ? "0" : "\(tdeeConfig.manualAdjustment > 0 ? "+" : "")\(Int(tdeeConfig.manualAdjustment))") { finetuneContent }
                }
                .card()

                // 3. Advanced (collapsed)
                advancedSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .onTapGesture { isFieldFocused = false }
        // Keep profile section open while editing fields
        .onChange(of: tdeeConfig.age) { _, _ in
            expandedSection = "profile" // prevent collapse
            save()
        }
        .onChange(of: tdeeConfig.heightCm) { _, _ in
            expandedSection = "profile"
            save()
        }
        .navigationTitle("Algorithm")
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
                }
            }
        }
        .onAppear { prefillFromAppleHealth() }
        .task { await loadAppleHealthData() }
        .onChange(of: tdeeConfig.activityMultiplier) { _, _ in save() }
        .onChange(of: tdeeConfig.manualAdjustment) { _, _ in save() }
        .onChange(of: tdeeConfig.appleHealthTrust) { _, _ in save() }
        .onChange(of: tdeeConfig.sex) { _, _ in save() }
        .onChange(of: config.emaAlpha) { _, _ in save() }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        VStack(spacing: 8) {
            Text("Your TDEE").font(.caption).foregroundStyle(.secondary)
            Text("\(liveTDEE)")
                .font(.system(size: 48, weight: .bold).monospacedDigit())
            Text("kcal/day").font(.caption).foregroundStyle(.tertiary)

            // Target + goal context
            if let target = liveCalorieTarget, let goal = WeightGoal.load() {
                let unit = Preferences.weightUnit
                let cKg = WeightTrendService.shared.latestWeightKg ?? goal.startWeightKg
                let remaining = abs(unit.convert(fromKg: goal.remainingKg(currentWeightKg: cKg)))
                let isLosing = goal.isLosing(currentWeightKg: cKg)
                let requiredDeficit = goal.requiredDailyDeficit(currentWeightKg: cKg)

                HStack(spacing: 4) {
                    Text("Target \(target)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Text("to \(isLosing ? "lose" : "gain") \(String(format: "%.1f", remaining)) \(unit.displayName)")
                        .font(.caption2).foregroundStyle(.quaternary)
                }

                // Required vs actual deficit/surplus
                Divider().frame(width: 40).overlay(Color.white.opacity(0.1))
                HStack(spacing: 12) {
                    VStack(spacing: 1) {
                        Text("Required").font(.caption).foregroundStyle(.tertiary)
                        Text("\(requiredDeficit < 0 ? "" : "+")\(Int(requiredDeficit))")
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(isLosing ? (requiredDeficit < 0 ? Theme.deficit : Theme.surplus) : (requiredDeficit > 0 ? Theme.deficit : Theme.surplus))
                    }
                    if let deficit = liveDeficit {
                        VStack(spacing: 1) {
                            Text("Current").font(.caption).foregroundStyle(.tertiary)
                            Text("\(deficit < 0 ? "" : "+")\(Int(deficit))")
                                .font(.caption2.weight(.bold).monospacedDigit())
                                .foregroundStyle(isLosing ? (deficit < 0 ? Theme.deficit : Theme.surplus) : (deficit > 0 ? Theme.deficit : Theme.surplus))
                        }
                    }
                    Text("kcal/day").font(.caption).foregroundStyle(.quaternary)
                }
            } else if liveCalorieTarget != nil {
                // Has TDEE target but no goal
                HStack(spacing: 4) {
                    Text("Target \(liveCalorieTarget!)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            } else {
                NavigationLink { GoalView() } label: {
                    Text("Set goal for calorie target").font(.caption2).foregroundStyle(Theme.accent)
                }
            }
        }
        .card()
    }

    private func sourceChip(_ label: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Circle().fill(active ? Theme.accent : Color.gray.opacity(0.3)).frame(width: 6, height: 6)
            Text(label).font(.caption).foregroundStyle(active ? .secondary : .quaternary)
        }
    }

    // MARK: - Accordion Row

    private func accordionRow<Content: View>(id: String, icon: String, label: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSection = expandedSection == id ? nil : id
                }
            } label: {
                HStack {
                    Image(systemName: icon).font(.caption).foregroundStyle(Theme.accent).frame(width: 20)
                    Text(label).font(.subheadline)
                    Spacer()
                    Text(value)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expandedSection == id ? 0 : -90))
                }
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if expandedSection == id {
                content()
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Activity Content

    private var activityContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: $tdeeConfig.activityMultiplier, in: 22...36, step: 1).tint(Theme.accent)
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
            Text("Sets your baseline. Refined by profile and Apple Health as data arrives.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Profile Content

    private var profileSummary: String {
        var parts: [String] = []
        if let s = tdeeConfig.sex { parts.append(s == .male ? "M" : "F") }
        if let a = tdeeConfig.age { parts.append("\(a)") }
        if let h = tdeeConfig.heightCm {
            let totalInches = h / 2.54
            parts.append("\(Int(totalInches / 12))'\(Int(totalInches.truncatingRemainder(dividingBy: 12)))\"")
        }
        return parts.isEmpty ? "Not set" : parts.joined(separator: " · ")
    }

    private var profileContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("More data = more accurate. Auto-filled from Apple Health.")
                .font(.caption2).foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sex").font(.caption2).foregroundStyle(.secondary)
                    Picker("", selection: Binding(
                        get: { tdeeConfig.sex },
                        set: { tdeeConfig.sex = $0 }
                    )) {
                        Text("—").tag(nil as TDEEEstimator.Sex?)
                        Text("Male").tag(TDEEEstimator.Sex.male as TDEEEstimator.Sex?)
                        Text("Female").tag(TDEEEstimator.Sex.female as TDEEEstimator.Sex?)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Age").font(.caption2).foregroundStyle(.secondary)
                    TextField("—", value: $tdeeConfig.age, format: .number)
                        .keyboardType(.numberPad)
                        .focused($isFieldFocused)
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 6)
                        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8))
                }
                .frame(width: 60)
            }

            HStack(spacing: 8) {
                Text("Height").font(.caption2).foregroundStyle(.secondary)
                TextField("cm", value: $tdeeConfig.heightCm, format: .number)
                    .keyboardType(.decimalPad)
                    .focused($isFieldFocused)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 6)
                    .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 8))
                    .frame(width: 80)
                Text("cm").font(.caption2).foregroundStyle(.tertiary)
                if let h = tdeeConfig.heightCm {
                    let totalInches = h / 2.54
                    Text("(\(Int(totalInches / 12))'\(Int(totalInches.truncatingRemainder(dividingBy: 12)))\")")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Fine-tune Content

    private var finetuneContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Slider(value: $tdeeConfig.manualAdjustment, in: -500...500, step: 25).tint(Theme.accent)
            HStack {
                Text("-500").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                if tdeeConfig.manualAdjustment != 0 {
                    Button { tdeeConfig.manualAdjustment = 0 } label: {
                        Text("Reset").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
                Text("+500").font(.caption2).foregroundStyle(.tertiary)
            }
            Text("Adjust if your TDEE doesn't match other tools.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Advanced Section

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showAdvanced.toggle() }
            } label: {
                HStack {
                    Text("Advanced").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showAdvanced ? 0 : -90))
                }
            }
            .buttonStyle(.plain)

            if showAdvanced {
                VStack(spacing: 10) {
                    // Data sources — from the shared TDEE estimator (same as Dashboard)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Active Data Sources").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        HStack(spacing: 10) {
                            let est = TDEEEstimator.shared.cachedOrSync()
                            ForEach(est.activeSources, id: \.self) { source in
                                sourceChip(source, active: true)
                            }
                        }

                        if ahResting > 0 || ahActive > 0 {
                            HStack(spacing: 10) {
                                HStack(spacing: 3) {
                                    Image(systemName: "bed.double.fill").font(.caption2).foregroundStyle(Theme.sleepIndigo)
                                    Text("\(Int(ahResting)) resting").font(.caption2.monospacedDigit())
                                }
                                HStack(spacing: 3) {
                                    Image(systemName: "flame.fill").font(.caption2).foregroundStyle(Theme.stepsOrange)
                                    Text("\(Int(ahActive)) active").font(.caption2.monospacedDigit())
                                }
                                if ahSteps > 0 {
                                    HStack(spacing: 3) {
                                        Image(systemName: "figure.walk").font(.caption2).foregroundStyle(Theme.deficit)
                                        Text("\(Int(ahSteps)) steps").font(.caption2.monospacedDigit())
                                    }
                                }
                            }
                            .foregroundStyle(.tertiary)
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.05))

                    // Presets
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Estimation Style").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        presetRow("Conservative", detail: "Smoother, cautious", isSelected: activePreset == "conservative") {
                            config = .conservative; tdeeConfig.appleHealthTrust = 1.0
                        }
                        presetRow("Balanced", detail: "Default for most", isSelected: activePreset == "balanced") {
                            config = .default; tdeeConfig.appleHealthTrust = 1.0
                        }
                        presetRow("Responsive", detail: "Fast reaction", isSelected: activePreset == "responsive") {
                            config = .responsive; tdeeConfig.appleHealthTrust = 1.0
                        }
                    }

                    Divider().overlay(Color.white.opacity(0.05))

                    // How it works
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How it works").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        howItWorksRow("1", "Apple Health", "Resting + active energy (7-day avg)")
                        howItWorksRow("2", "Profile", "Age, height, sex (Mifflin-St Jeor)")
                        howItWorksRow("3", "Food Log", "Your intake vs weight change")
                        howItWorksRow("4", "Body Weight", "Baseline from weight + activity")
                        Text("Each source refines the estimate. More data = more accurate.")
                            .font(.caption2).foregroundStyle(.quaternary)
                    }

                    // Reset
                    if tdeeConfig.activityMultiplier != 29 || tdeeConfig.manualAdjustment != 0 || activePreset != "balanced" {
                        Button {
                            config = .default; tdeeConfig = .default; save()
                        } label: {
                            Text("Reset All to Defaults").font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.surplus.opacity(0.7))
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .card()
    }

    // MARK: - Auto-save

    private func save() {
        WeightTrendCalculator.saveConfig(config)
        TDEEEstimator.saveConfig(tdeeConfig)
        _ = TDEEEstimator.shared.cachedOrSync()
        refreshKey += 1
        Task { await TDEEEstimator.shared.refresh(); refreshKey += 1 }
    }

    private func prefillFromAppleHealth() {
        #if !targetEnvironment(simulator)
        Task {
            let profile = await HealthKitService.shared.fetchUserProfile()
            var changed = false
            if tdeeConfig.age == nil, let age = profile.age, age > 0 { tdeeConfig.age = age; changed = true }
            if tdeeConfig.heightCm == nil, let h = profile.heightCm, h > 0 { tdeeConfig.heightCm = round(h * 10) / 10; changed = true }
            if tdeeConfig.sex == nil, let s = profile.sex { tdeeConfig.sex = s; changed = true }
            if changed { save() }
        }
        #endif
    }

    private func loadAppleHealthData() async {
        #if !targetEnvironment(simulator)
        let hk = HealthKitService.shared
        if let cal = try? await hk.fetchCaloriesBurned(for: Date()) {
            ahResting = cal.basal
            ahActive = cal.active
        }
        ahSteps = (try? await hk.fetchSteps(for: Date())) ?? 0
        #endif
    }

    // MARK: - Components

    private func presetRow(_ name: String, detail: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button { action(); save() } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.caption).foregroundStyle(isSelected ? Theme.accent : Color.gray.opacity(0.4))
                Text(name).font(.caption)
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    private func howItWorksRow(_ num: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(num).font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                .frame(width: 14, height: 14).background(Theme.accent.opacity(0.15), in: Circle())
            Text("\(title): ").font(.caption2.weight(.semibold)) + Text(detail).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func isPreset(_ preset: WeightTrendCalculator.AlgorithmConfig) -> Bool {
        abs(config.emaAlpha - preset.emaAlpha) < 0.001 &&
        config.regressionWindowDays == preset.regressionWindowDays &&
        abs(config.kcalPerKg - preset.kcalPerKg) < 1
    }
}
