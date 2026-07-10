import SwiftUI
import DriftCore

// MARK: - Profile link row (Weight Goal keeps the TDEE connection visible)

extension GoalView {
    /// Compact row replacing the old inline collapsible profile form —
    /// Profile is identity, not goal config, so it lives on its own screen
    /// (operator call 2026-07-09), reachable from More AND from here.
    var profileCard: some View {
        NavigationLink { ProfileView() } label: {
            HStack {
                Label("Your Profile", systemImage: "person.crop.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if profileComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Theme.deficit)
                } else {
                    Text("Improve accuracy")
                        .font(.caption2).foregroundStyle(Theme.fatYellow)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    var profileComplete: Bool {
        (tdeeConfig.sex != nil || tdeeConfig.sexUndisclosed == true)
            && tdeeConfig.age != nil && tdeeConfig.heightCm != nil
    }
}

// MARK: - Profile screen (sex, age, height, weight)

/// Standalone profile editor — pushed from More → Profile and from
/// Weight Goal's profile row. Feeds TDEE (sex/age/height) and the weight
/// log (weight field writes a real WeightEntry).
struct ProfileView: View {
    @State private var tdeeConfig = TDEEEstimator.loadConfig()
    @State private var showSaved = false
    @State private var heightInFeet = false
    @State private var weightUnit: WeightUnit = Preferences.weightUnit
    @State private var weightText = ""
    @State private var currentWeightKg: Double?
    @FocusState private var weightFocused: Bool

    private let ageRanges = ["18-24", "25-34", "35-44", "45-54", "55-64", "65+"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(spacing: 10) {
                    sexPicker
                    agePicker
                    heightInput
                    weightInput
                    saveFeedback
                }
                .card()

                Text("Sex, age and height personalize your calorie targets. Weight entries go to your weight log.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .onAppear {
            let service = WeightTrendService.shared
            currentWeightKg = service.latestWeightKg ?? service.trendWeight
            if let kg = currentWeightKg {
                weightText = String(format: "%.1f", weightUnit.convert(fromKg: kg))
            }
            tryAutoFillProfile()
        }
    }

    private var profileComplete: Bool {
        (tdeeConfig.sex != nil || tdeeConfig.sexUndisclosed == true)
            && tdeeConfig.age != nil && tdeeConfig.heightCm != nil
    }

    // MARK: - Fields

    private var sexPicker: some View {
        HStack {
            Text("Sex").font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: Binding(
                get: { tdeeConfig.sex },
                set: {
                    tdeeConfig.sex = $0
                    // "N/A" is an explicit answer (inclusivity, 2026-07-09):
                    // remember it so HealthKit auto-fill doesn't overwrite it
                    // and the profile counts as answered. TDEE math falls
                    // back to the sex-averaged Mifflin base.
                    tdeeConfig.sexUndisclosed = ($0 == nil)
                    saveProfile()
                }
            )) {
                Text("Male").tag(TDEEEstimator.Sex?.some(.male))
                Text("Female").tag(TDEEEstimator.Sex?.some(.female))
                Text("N/A").tag(TDEEEstimator.Sex?.none)
            }
            .pickerStyle(.segmented).frame(width: 210)
        }
    }

    private var agePicker: some View {
        HStack {
            Text("Age").font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Picker("", selection: Binding(
                get: { tdeeConfig.age != nil ? rangeFromAge(tdeeConfig.age) : "" },
                set: {
                    if $0.isEmpty { tdeeConfig.age = nil }
                    else { tdeeConfig.age = ageFromRange($0) }
                    saveProfile()
                }
            )) {
                Text("Not set").tag("")
                ForEach(ageRanges, id: \.self) { range in
                    Text(range).tag(range)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var heightInput: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Height").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                Picker("", selection: $heightInFeet) {
                    Text("cm").tag(false)
                    Text("ft/in").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
            }
            HStack {
                Spacer()
                if heightInFeet {
                    TextField("ft", text: Binding(
                        get: {
                            guard let cm = tdeeConfig.heightCm else { return "" }
                            return "\(Int(cm / 2.54) / 12)"
                        },
                        set: { ft in updateHeightFromFtIn(ft: ft, inches: nil) }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 35)
                    Text("ft").font(.caption).foregroundStyle(Theme.textTertiary)
                    TextField("in", text: Binding(
                        get: {
                            guard let cm = tdeeConfig.heightCm else { return "" }
                            return "\(Int(cm / 2.54) % 12)"
                        },
                        set: { inches in updateHeightFromFtIn(ft: nil, inches: inches) }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 35)
                    Text("in").font(.caption).foregroundStyle(Theme.textTertiary)
                } else {
                    TextField("Not set", text: Binding(
                        get: { tdeeConfig.heightCm.map { "\(Int($0))" } ?? "" },
                        set: { newValue in
                            if newValue.isEmpty { tdeeConfig.heightCm = nil }
                            else if let cm = Double(newValue), cm >= 50, cm <= 300 { tdeeConfig.heightCm = cm }
                            saveProfile(showFeedback: false)
                        }
                    ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                    Text("cm").font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private var weightInput: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Weight").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Spacer()
                Picker("", selection: $weightUnit) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lbs").tag(WeightUnit.lbs)
                }
                .pickerStyle(.segmented)
                .frame(width: 110)
                .onChange(of: weightUnit) { oldUnit, newUnit in
                    Preferences.weightUnit = newUnit
                    // Reconvert whatever is currently shown — using the text field as
                    // source of truth so it works mid-edit (currentWeightKg only
                    // updates on focus loss).
                    if let shown = Double(weightText) {
                        let kg = oldUnit.convertToKg(shown)
                        currentWeightKg = kg
                        weightText = String(format: "%.1f", newUnit.convert(fromKg: kg))
                    } else if let kg = currentWeightKg {
                        weightText = String(format: "%.1f", newUnit.convert(fromKg: kg))
                    }
                }
            }
            HStack {
                Spacer()
                TextField("Not set", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .focused($weightFocused)
                    .onChange(of: weightFocused) { _, focused in
                        if !focused, let val = Double(weightText) {
                            let kg = weightUnit.convertToKg(val)
                            currentWeightKg = kg
                            saveWeight(kg: kg)
                        }
                    }
                Text(weightUnit.displayName).font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private var saveFeedback: some View {
        HStack {
            Spacer()
            if showSaved {
                Label("Saved", systemImage: "checkmark")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.deficit)
                    .transition(.opacity)
            } else {
                Text("Changes save automatically")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    // MARK: - Helpers

    private func ageFromRange(_ range: String) -> Int {
        switch range {
        case "18-24": return 21
        case "25-34": return 30
        case "35-44": return 40
        case "45-54": return 50
        case "55-64": return 60
        default: return 70
        }
    }

    private func rangeFromAge(_ age: Int?) -> String {
        switch age ?? 0 {
        case 18...24: return "18-24"
        case 25...34: return "25-34"
        case 35...44: return "35-44"
        case 45...54: return "45-54"
        case 55...64: return "55-64"
        default: return "65+"
        }
    }

    private func updateHeightFromFtIn(ft: String?, inches: String?) {
        let currentCm = tdeeConfig.heightCm ?? 170
        let totalInches = Int(currentCm / 2.54)
        let currentFt = totalInches / 12
        let currentIn = totalInches % 12
        let newFt = ft.flatMap { Int($0) } ?? currentFt
        let newIn = inches.flatMap { Int($0) } ?? currentIn
        let cm = Double(newFt * 12 + newIn) * 2.54
        if cm >= 50, cm <= 300 {
            tdeeConfig.heightCm = cm
            saveProfile(showFeedback: false)
        }
    }

    private func saveWeight(kg: Double) {
        var entry = WeightEntry(date: DateFormatters.todayString, weightKg: kg)
        WeightServiceAPI.saveWeightEntry(&entry)
        WeightTrendService.shared.refresh()
        currentWeightKg = WeightTrendService.shared.trendWeight
        flashSaved()
    }

    private func saveProfile(showFeedback: Bool = true) {
        TDEEEstimator.saveConfig(tdeeConfig)
        Task { await TDEEEstimator.shared.refresh() }
        if showFeedback { flashSaved() }
    }

    private func flashSaved() {
        withAnimation { showSaved = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSaved = false }
        }
    }

    private func tryAutoFillProfile() {
        guard !profileComplete else { return }
        Task {
            let profile = await HealthKitService.shared.fetchUserProfile()
            var changed = false
            // Never auto-fill sex over an explicit "N/A".
            if tdeeConfig.sex == nil, tdeeConfig.sexUndisclosed != true,
               let sex = profile.sex { tdeeConfig.sex = sex; changed = true }
            if tdeeConfig.age == nil, let age = profile.age { tdeeConfig.age = age; changed = true }
            if tdeeConfig.heightCm == nil, let h = profile.heightCm { tdeeConfig.heightCm = h; changed = true }
            if changed { saveProfile(showFeedback: false) }
        }
    }
}
