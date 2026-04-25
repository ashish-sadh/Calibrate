import SwiftUI
import DriftCore

// MARK: - Profile Card (sex, age, height, weight form)

extension GoalView {

    var profileCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation { profileExpanded.toggle() }
            } label: {
                HStack {
                    Label("Your Profile", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    if profileComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(Theme.deficit)
                    } else {
                        Text("Improve accuracy")
                            .font(.caption2).foregroundStyle(Theme.fatYellow)
                    }
                    Image(systemName: profileExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if profileExpanded {
                VStack(spacing: 10) {
                    sexPicker
                    agePicker
                    heightInput
                    weightInput
                    saveFeedback
                }
                .padding(.top, 4)
            }
        }
        .card()
        .onAppear {
            tryAutoFillProfile()
            if !profileComplete { profileExpanded = true }
        }
    }

    // MARK: - Profile Fields

    private var sexPicker: some View {
        HStack {
            Text("Sex").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Picker("", selection: Binding(
                get: { tdeeConfig.sex },
                set: { tdeeConfig.sex = $0; saveProfile() }
            )) {
                Text("Male").tag(TDEEEstimator.Sex?.some(.male))
                Text("Female").tag(TDEEEstimator.Sex?.some(.female))
            }
            .pickerStyle(.segmented).frame(width: 160)
        }
    }

    private var agePicker: some View {
        HStack {
            Text("Age").font(.subheadline).foregroundStyle(.secondary)
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
                Text("Height").font(.subheadline).foregroundStyle(.secondary)
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
                    Text("ft").font(.caption).foregroundStyle(.tertiary)
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
                    Text("in").font(.caption).foregroundStyle(.tertiary)
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
                    Text("cm").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var weightInput: some View {
        HStack {
            Text("Weight").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            let unit = Preferences.weightUnit
            TextField("Not set", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
                .focused($weightFocused)
                .onChange(of: weightFocused) { _, focused in
                    if !focused, let val = Double(weightText) {
                        let kg = unit.convertToKg(val)
                        currentWeightKg = kg
                        saveWeight(kg: kg)
                    }
                }
            Text(unit.displayName).font(.caption).foregroundStyle(.tertiary)
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
                    .font(.caption2).foregroundStyle(.quaternary)
            }
        }
    }

    // MARK: - Profile Helpers

    func updateHeightFromFtIn(ft: String?, inches: String?) {
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

    var profileComplete: Bool {
        tdeeConfig.sex != nil && tdeeConfig.age != nil && tdeeConfig.heightCm != nil
    }

    func saveWeight(kg: Double) {
        var entry = WeightEntry(date: DateFormatters.todayString, weightKg: kg)
        WeightServiceAPI.saveWeightEntry(&entry)
        WeightTrendService.shared.refresh()
        currentWeightKg = WeightTrendService.shared.trendWeight
        actualWeeklyRate = WeightTrendService.shared.weeklyRate
        actualDailyDeficit = WeightTrendService.shared.dailyDeficit
        withAnimation { showSaved = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { showSaved = false }
        }
    }

    func saveProfile(showFeedback: Bool = true) {
        TDEEEstimator.saveConfig(tdeeConfig)
        Task { await TDEEEstimator.shared.refresh() }
        if showFeedback {
            withAnimation { showSaved = true }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation { showSaved = false }
            }
        }
    }

    func tryAutoFillProfile() {
        guard !profileComplete else { return }
        Task {
            let profile = await HealthKitService.shared.fetchUserProfile()
            var changed = false
            if tdeeConfig.sex == nil, let sex = profile.sex { tdeeConfig.sex = sex; changed = true }
            if tdeeConfig.age == nil, let age = profile.age { tdeeConfig.age = age; changed = true }
            if tdeeConfig.heightCm == nil, let h = profile.heightCm { tdeeConfig.heightCm = h; changed = true }
            if changed { saveProfile(showFeedback: false) }
        }
    }
}
