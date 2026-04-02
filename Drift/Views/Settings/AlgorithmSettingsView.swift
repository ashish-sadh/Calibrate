import SwiftUI

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

    // MARK: - Computed (unchanged)

    private var liveTrend: WeightTrendCalculator.WeightTrend? {
        let db = AppDatabase.shared
        guard let entries = try? db.fetchWeightEntries(from: nil), !entries.isEmpty else { return nil }
        return WeightTrendCalculator.calculateTrend(entries: input(entries), config: config)
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
        return Int(max(800, Double(liveTDEE) + goal.requiredDailyDeficit))
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
        .scrollDismissesKeyboard(.interactively)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    // Just dismiss keyboard — don't collapse the section
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
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

            // Target
            if let target = liveCalorieTarget {
                let goal = WeightGoal.load()
                let adj = goal?.requiredDailyDeficit ?? 0
                HStack(spacing: 4) {
                    Text("Target")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("\(target)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                    Text(adj < 0 ? "for weight loss" : adj > 0 ? "to gain" : "maintenance")
                        .font(.caption2).foregroundStyle(.quaternary)
                }
            } else {
                NavigationLink { GoalView() } label: {
                    Text("Set goal for calorie target").font(.caption2).foregroundStyle(Theme.accent)
                }
            }

            // Weight trend subtitle
            if let deficit = liveDeficit, let trend = liveTrend {
                let unit = Preferences.weightUnit
                HStack(spacing: 6) {
                    Text(deficit < 0 ? "Deficit" : "Surplus")
                        .font(.caption2).foregroundStyle(.tertiary)
                    Text("\(deficit) kcal")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(deficit < 0 ? Theme.deficit : Theme.surplus)
                    Text("·").foregroundStyle(.quaternary)
                    Text("\(String(format: "%+.2f", unit.convert(fromKg: trend.weeklyRateKg))) \(unit.displayName)/wk")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }

            // Data source indicators
            HStack(spacing: 10) {
                sourceChip("Weight", active: (try? AppDatabase.shared.fetchWeightEntries(from: nil))?.first != nil)
                sourceChip("Profile", active: tdeeConfig.age != nil || tdeeConfig.heightCm != nil || tdeeConfig.sex != nil)
                sourceChip("Apple Health", active: ahResting > 0)
                sourceChip("Trend", active: liveDeficit != nil)
            }
            .padding(.top, 4)

            // Apple Health breakdown (when available)
            if ahResting > 0 || ahActive > 0 {
                HStack(spacing: 12) {
                    HStack(spacing: 3) {
                        Image(systemName: "bed.double.fill").font(.system(size: 8)).foregroundStyle(Theme.sleepIndigo)
                        Text("\(Int(ahResting))").font(.caption2.weight(.semibold).monospacedDigit())
                        Text("resting").font(.system(size: 8)).foregroundStyle(.quaternary)
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 8)).foregroundStyle(Theme.stepsOrange)
                        Text("\(Int(ahActive))").font(.caption2.weight(.semibold).monospacedDigit())
                        Text("active").font(.system(size: 8)).foregroundStyle(.quaternary)
                    }
                    if ahSteps > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "figure.walk").font(.system(size: 8)).foregroundStyle(Theme.deficit)
                            Text("\(Int(ahSteps))").font(.caption2.weight(.semibold).monospacedDigit())
                            Text("steps").font(.system(size: 8)).foregroundStyle(.quaternary)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
        }
        .card()
    }

    private func sourceChip(_ label: String, active: Bool) -> some View {
        HStack(spacing: 3) {
            Circle().fill(active ? Theme.accent : Color.gray.opacity(0.3)).frame(width: 6, height: 6)
            Text(label).font(.system(size: 9)).foregroundStyle(active ? .secondary : .quaternary)
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
                        howItWorksRow("2", "Profile", "Mifflin-St Jeor from age/height/sex")
                        howItWorksRow("3", "Weight + Food", "Adaptive: intake − weight change")
                        howItWorksRow("4", "Body Weight", "Fallback: 2000 × √(weight/70)")
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
        let profile = HealthKitService.shared.fetchUserProfile()
        var changed = false
        if tdeeConfig.age == nil, let age = profile.age, age > 0 { tdeeConfig.age = age; changed = true }
        if tdeeConfig.heightCm == nil, let h = profile.heightCm, h > 0 { tdeeConfig.heightCm = round(h * 10) / 10; changed = true }
        if tdeeConfig.sex == nil, let s = profile.sex { tdeeConfig.sex = s; changed = true }
        if changed { save() }
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
            Text(num).font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.accent)
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
