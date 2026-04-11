import SwiftUI

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
        WeightTrendService.shared.trendWeight
    }
}
