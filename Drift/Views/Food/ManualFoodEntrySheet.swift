import SwiftUI
import DriftCore

struct ManualFoodEntrySheet: View {
    @Bindable var viewModel: FoodLogViewModel
    let onLogged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var cal: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber = ""
    @State private var serving = "1"
    @State private var servingUnit = "serving"
    @State private var logTime = Date()

    init(viewModel: FoodLogViewModel, prefill: AIChatViewModel.ManualFoodPrefill? = nil, onLogged: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onLogged = onLogged
        _name = State(initialValue: prefill?.name ?? "")
        _cal = State(initialValue: prefill.map { $0.calories > 0 ? "\($0.calories)" : "" } ?? "")
        _protein = State(initialValue: prefill.map { $0.proteinG > 0 ? "\(Int($0.proteinG))" : "" } ?? "")
        _carbs = State(initialValue: prefill.map { $0.carbsG > 0 ? "\(Int($0.carbsG))" : "" } ?? "")
        _fat = State(initialValue: prefill.map { $0.fatG > 0 ? "\(Int($0.fatG))" : "" } ?? "")
        _fiber = State(initialValue: prefill.map { $0.fiberG > 0 ? "\(Int($0.fiberG))" : "" } ?? "")
    }

    private var macroCalories: Int {
        let p = Double(protein) ?? 0, c = Double(carbs) ?? 0, f = Double(fat) ?? 0
        return Int(p * 4 + c * 4 + f * 9)
    }

    private var enteredCal: Int { Int(Double(cal) ?? 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Name
                    TextField("Food name", text: $name)
                        .font(.body)
                        .padding(12)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))

                    // Calories — hero
                    VStack(spacing: 4) {
                        Text("Calories").font(.caption2).foregroundStyle(.tertiary)
                        TextField("0", text: $cal)
                            .keyboardType(.numberPad)
                            .font(.system(size: 44, weight: .bold).monospacedDigit())
                            .multilineTextAlignment(.center)
                        Text("kcal").font(.caption).foregroundStyle(.secondary)
                        if macroCalories > 0 && !cal.isEmpty && macroCalories != enteredCal {
                            Text("Macros sum to \(macroCalories) kcal")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)

                    // Macros — inline row
                    HStack(spacing: 10) {
                        macroField("Protein", value: $protein, unit: "g", color: Theme.proteinRed)
                        macroField("Carbs", value: $carbs, unit: "g", color: Theme.carbsGreen)
                        macroField("Fat", value: $fat, unit: "g", color: Theme.fatYellow)
                    }

                    // Fiber — optional, smaller
                    HStack {
                        Text("Fiber").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        TextField("0", text: $fiber)
                            .keyboardType(.decimalPad)
                            .font(.subheadline.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))

                    // Serving size — optional
                    VStack(spacing: 8) {
                        HStack {
                            Text("Serving").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            TextField("1", text: $serving)
                                .keyboardType(.decimalPad)
                                .font(.subheadline.monospacedDigit())
                                .multilineTextAlignment(.trailing)
                                .frame(width: 50)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(["serving", "g", "ml", "piece", "cup", "tbsp"], id: \.self) { u in
                                    Button { servingUnit = u } label: {
                                        Text(u)
                                            .font(.caption.weight(servingUnit == u ? .semibold : .medium))
                                            .padding(.horizontal, 12).padding(.vertical, 6)
                                            .background(servingUnit == u ? Theme.accent.opacity(0.25) : Theme.cardBackgroundElevated, in: Capsule())
                                            .foregroundStyle(servingUnit == u ? .white : .secondary)
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))

                    // Log time — defaults to now, user can change
                    DatePicker("Log time", selection: $logTime, displayedComponents: .hourAndMinute)
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Quick Add").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let p = Double(protein) ?? 0, c = Double(carbs) ?? 0, f = Double(fat) ?? 0
                        let totalCal = Double(cal) ?? (macroCalories > 0 ? Double(macroCalories) : 0)
                        let servingVal = Double(serving) ?? 1
                        let servingG: Double = switch servingUnit {
                        case "g": servingVal
                        case "ml": servingVal
                        case "cup": servingVal * 240
                        case "tbsp": servingVal * 15
                        default: 0
                        }
                        let loggedAtStr = ISO8601DateFormatter().string(from: logTime)
                        viewModel.quickAdd(name: name.isEmpty ? "Quick Add" : name,
                                           calories: totalCal, proteinG: p, carbsG: c, fatG: f,
                                           fiberG: Double(fiber) ?? 0, mealType: viewModel.autoMealType,
                                           loggedAt: loggedAtStr, servingSizeG: servingG)
                        viewModel.loadSuggestions()
                        onLogged()
                        dismiss()
                    }
                    .disabled((Double(cal) ?? 0) == 0 && macroCalories == 0)
                }
            }
        }
    }

    private func macroField(_ label: String, value: Binding<String>, unit: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold).monospacedDigit())
                .multilineTextAlignment(.center)
            Text(unit).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.35), lineWidth: 1))
    }
}
