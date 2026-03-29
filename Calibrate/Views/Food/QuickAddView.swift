import SwiftUI

struct QuickAddView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var selectedMealType: MealType = .lunch

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name (e.g., Homemade dal)", text: $name)
                }

                Section("Macros") {
                    macroField("Calories", value: $calories, unit: "kcal")
                    macroField("Protein", value: $protein, unit: "g")
                    macroField("Carbs", value: $carbs, unit: "g")
                    macroField("Fat", value: $fat, unit: "g")
                    macroField("Fiber", value: $fiber, unit: "g")
                }

                Section("Meal") {
                    Picker("Meal Type", selection: $selectedMealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        viewModel.quickAdd(
                            name: name.isEmpty ? "Quick Add" : name,
                            calories: Double(calories) ?? 0,
                            proteinG: Double(protein) ?? 0,
                            carbsG: Double(carbs) ?? 0,
                            fatG: Double(fat) ?? 0,
                            fiberG: Double(fiber) ?? 0,
                            mealType: selectedMealType
                        )
                        dismiss()
                    }
                    .disabled(calories.isEmpty)
                }
            }
        }
    }

    private func macroField(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 30)
        }
    }
}
