import SwiftUI
import DriftCore

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
    @State private var customProtein: String = ""
    @State private var customCarbs: String = ""
    @State private var customFat: String = ""

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

                if dietPref == .custom {
                    Section {
                        HStack {
                            Text("Protein")
                            Spacer()
                            TextField("auto", text: $customProtein)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("g").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Carbs")
                            Spacer()
                            TextField("auto", text: $customCarbs)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("g").font(.caption).foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Fat")
                            Spacer()
                            TextField("auto", text: $customFat)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 60)
                            Text("g").font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Custom Macros")
                    } footer: {
                        let p = Double(customProtein) ?? 0
                        let c = Double(customCarbs) ?? 0
                        let f = Double(customFat) ?? 0
                        let hasAnyEntry = p > 0 || c > 0 || f > 0
                        let weightForCompute = getCurrentWeight() ?? existingGoal?.startWeightKg ?? 70
                        let targetKg = Double(targetWeight).map { unit.convertToKg($0) } ?? weightForCompute
                        // Use macroTargets() to get accurate auto-computed values for all blank fields
                        let tempGoal = WeightGoal(
                            targetWeightKg: targetKg, monthsToAchieve: months,
                            startDate: DateFormatters.todayString, startWeightKg: weightForCompute,
                            proteinTargetG: p > 0 ? p : nil,
                            carbsTargetG: c > 0 ? c : nil,
                            fatTargetG: f > 0 ? f : nil,
                            dietPreference: dietPref,
                            calorieTargetOverride: Double(calorieTarget)
                        )
                        let computed = tempGoal.macroTargets(currentWeightKg: weightForCompute)
                        VStack(alignment: .leading, spacing: 2) {
                            if hasAnyEntry, let m = computed {
                                let enteredKcal = p * 4 + c * 4 + f * 9
                                let autoParts = [c == 0 ? "carbs ~\(Int(m.carbsG))g" : nil,
                                                 f == 0 ? "fat ~\(Int(m.fatG))g" : nil].compactMap { $0 }
                                if autoParts.isEmpty {
                                    Text("Total: \(Int(m.calorieTarget)) kcal/day. Blank fields auto-compute within your calorie target.")
                                } else {
                                    Text("Entered: \(Int(enteredKcal)) kcal + auto \(autoParts.joined(separator: " + ")) = ~\(Int(m.calorieTarget)) kcal/day. Blank fields auto-compute within your calorie target.")
                                }
                                if m.fatWasClamped {
                                    Text("Fat raised to safe minimum (\(Int(m.fatG))g).")
                                        .foregroundStyle(Theme.surplus)
                                }
                            } else {
                                Text("Enter grams to override. Blank fields auto-compute within your calorie target.")
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Daily calories")
                        Spacer()
                        let allMacrosSet = dietPref == .custom
                            && !customProtein.isEmpty && !customCarbs.isEmpty && !customFat.isEmpty
                        let impliedCal = (Double(customProtein) ?? 0) * 4
                            + (Double(customCarbs) ?? 0) * 4
                            + (Double(customFat) ?? 0) * 9
                        if allMacrosSet {
                            Text("\(Int(impliedCal))").foregroundStyle(.secondary)
                        } else {
                            TextField("auto", text: $calorieTarget)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                        Text("kcal").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calorie Target")
                } footer: {
                    let allMacrosSet = dietPref == .custom
                        && !customProtein.isEmpty && !customCarbs.isEmpty && !customFat.isEmpty
                    if allMacrosSet {
                        let implied = (Double(customProtein) ?? 0) * 4
                            + (Double(customCarbs) ?? 0) * 4
                            + (Double(customFat) ?? 0) * 9
                        Text("Set by your macros (\(Int(implied)) kcal/day). To set calories independently, clear a macro field.")
                    } else {
                        Text("Leave blank to estimate from Apple Health activity data. Set a number if you know your daily intake target.")
                    }
                }

                Section("Timeline") {
                    Stepper("\(months) month\(months == 1 ? "" : "s")", value: $months, in: 1...24)

                    if let target = Double(targetWeight) {
                        let targetKg = unit.convertToKg(target)
                        let currentKg = getCurrentWeight()
                        if let current = currentKg {
                            let calOverride = Double(calorieTarget)
                            let previewGoal = WeightGoal(
                                targetWeightKg: targetKg, monthsToAchieve: months,
                                startDate: DateFormatters.todayString,
                                startWeightKg: current,
                                proteinTargetG: dietPref == .custom ? Double(customProtein) : nil,
                                carbsTargetG: dietPref == .custom ? Double(customCarbs) : nil,
                                fatTargetG: dietPref == .custom ? Double(customFat) : nil,
                                dietPreference: dietPref,
                                calorieTargetOverride: calOverride
                            )
                            let macros = previewGoal.macroTargets(currentWeightKg: current)
                            let hasAnyCustomMacro = dietPref == .custom &&
                                (!customProtein.isEmpty || !customCarbs.isEmpty || !customFat.isEmpty)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("This means:")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                                if hasAnyCustomMacro, let m = macros {
                                    // Honest macro-based projection: what will actually happen vs TDEE
                                    let tdee = TDEEEstimator.shared.cachedOrSync().tdee
                                    let config = WeightTrendCalculator.loadConfig()
                                    let dailySurplus = m.calorieTarget - tdee
                                    let weeklyRateFromMacros = dailySurplus / config.kcalPerKg * 7
                                    let rateAbs = abs(unit.convert(fromKg: weeklyRateFromMacros))
                                    let rateLabel = rateAbs < 0.01 ? "stable weight"
                                        : "\(String(format: "%.2f", rateAbs)) \(unit.displayName)/week \(weeklyRateFromMacros > 0 ? "gaining" : "losing")"
                                    let diffLabel = dailySurplus >= 0
                                        ? "+\(Int(dailySurplus)) kcal/day surplus"
                                        : "\u{2212}\(Int(abs(dailySurplus))) kcal/day deficit"

                                    Text("\u{2022} Your intake: \(Int(m.calorieTarget)) kcal/day").font(.caption)
                                    Text("\u{2022} vs TDEE (~\(Int(tdee)) kcal): \(diffLabel)").font(.caption)
                                    Text("\u{2022} \(rateLabel)").font(.caption).foregroundStyle(Theme.accent)

                                    let goalIsLosing = targetKg < current
                                    if weeklyRateFromMacros > 0.05 && goalIsLosing {
                                        Text("These macros exceed your TDEE — you'll gain weight. Reduce to reach your goal.")
                                            .font(.caption).foregroundStyle(Theme.surplus)
                                    } else if weeklyRateFromMacros < -0.05 && !goalIsLosing {
                                        Text("These macros are below your TDEE — you'll lose weight. Increase to reach your goal.")
                                            .font(.caption).foregroundStyle(Theme.surplus)
                                    }
                                    if m.fatWasClamped {
                                        Text("Fat raised to safe minimum (\(Int(m.fatG))g).")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text("\u{2022} \(Int(m.proteinG))g protein \u{00B7} \(Int(m.carbsG))g carbs \u{00B7} \(Int(m.fatG))g fat")
                                        .font(.caption).foregroundStyle(Theme.accent)
                                } else {
                                    // Geometric bullets: fully auto mode (no macro overrides)
                                    let change = targetKg - current
                                    let weeks = Double(months) * 4.33
                                    let weeklyRate = change / weeks
                                    let config = WeightTrendCalculator.loadConfig()
                                    let dailyDeficit = weeklyRate * config.kcalPerKg / 7
                                    Text("\u{2022} \(String(format: "%.2f", unit.convert(fromKg: weeklyRate))) \(unit.displayName)/week")
                                        .font(.caption)
                                    Text("\u{2022} \(String(format: "%+.0f", dailyDeficit)) kcal/day \(dailyDeficit < 0 ? "deficit" : "surplus")")
                                        .font(.caption)
                                    if let m = macros {
                                        Text("\u{2022} \(Int(m.calorieTarget)) kcal/day target").font(.caption)
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
                        guard let currentKg = getCurrentWeight() ?? existingGoal?.startWeightKg else {
                            // No weight data at all — need at least one weight entry
                            return
                        }

                        let calOverride = Double(calorieTarget)
                        let goal = WeightGoal(
                            targetWeightKg: targetKg,
                            monthsToAchieve: months,
                            startDate: DateFormatters.todayString,
                            startWeightKg: existingGoal?.startWeightKg ?? currentKg,
                            proteinTargetG: dietPref == .custom ? Double(customProtein) : nil,
                            carbsTargetG: dietPref == .custom ? Double(customCarbs) : nil,
                            fatTargetG: dietPref == .custom ? Double(customFat) : nil,
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
                    if let p = g.proteinTargetG { customProtein = "\(Int(p))" }
                    if let c = g.carbsTargetG { customCarbs = "\(Int(c))" }
                    if let f = g.fatTargetG { customFat = "\(Int(f))" }
                }
            }
        }
    }

    private func getCurrentWeight() -> Double? {
        WeightTrendService.shared.trendWeight
    }
}
