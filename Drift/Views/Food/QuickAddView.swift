import SwiftUI

struct QuickAddView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode = .ingredient
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var selectedMealType: MealType = .lunch
    // Ingredient mode
    @State private var ingredientSearch = ""
    @State private var selectedIngredient: RawIngredient?
    @State private var amount = ""
    @State private var selectedUnit: ServingUnit = .grams

    enum AddMode: String, CaseIterable {
        case ingredient = "Ingredient"
        case manual = "Manual"
    }

    private var filteredIngredients: [RawIngredient] {
        if ingredientSearch.isEmpty { return RawIngredient.allCases.map { $0 } }
        return RawIngredient.allCases.filter { $0.name.localizedCaseInsensitiveContains(ingredientSearch) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mode picker
                Picker("Mode", selection: $mode) {
                    ForEach(AddMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 8)

                if mode == .ingredient {
                    ingredientView
                } else {
                    manualView
                }
            }
            .background(Theme.background)
            .navigationTitle("Quick Add").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    // MARK: - Ingredient Mode (search-based)

    private var ingredientView: some View {
        VStack(spacing: 0) {
            if selectedIngredient == nil {
                // Search for ingredient
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search ingredient (rice, oil, egg...)", text: $ingredientSearch)
                        .textFieldStyle(.plain).autocorrectionDisabled()
                }
                .padding().background(.ultraThinMaterial)

                List {
                    ForEach(filteredIngredients) { ing in
                        Button {
                            selectedIngredient = ing
                            selectedUnit = ing.typicalUnit
                            amount = ""
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ing.name).font(.subheadline)
                                Text("\(Int(ing.caloriesPer100g))cal \(Int(ing.proteinPer100g))P \(Int(ing.carbsPer100g))C \(Int(ing.fatPer100g))F per 100g")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                    }
                }
                .listStyle(.plain)
            } else {
                // Amount entry for selected ingredient
                ingredientAmountView
            }
        }
    }

    private var ingredientAmountView: some View {
        let ing = selectedIngredient!
        let amountNum = Double(amount) ?? 0
        let grams = selectedUnit.toGrams(amountNum, ingredient: ing)
        let cal = ing.caloriesPer100g * grams / 100

        return ScrollView {
            VStack(spacing: 14) {
                // Selected ingredient header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ing.name).font(.headline)
                        Text("\(Int(ing.caloriesPer100g))cal per 100g").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Change") { selectedIngredient = nil }
                        .font(.caption).foregroundStyle(Theme.accent)
                }
                .card()

                // Amount + unit
                VStack(spacing: 10) {
                    HStack {
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title2.monospacedDigit())
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(ServingUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }

                    // Quick amounts
                    HStack(spacing: 6) {
                        ForEach(quickAmounts(for: ing), id: \.label) { qa in
                            Button(qa.label) { amount = qa.value; selectedUnit = qa.unit }
                                .font(.caption).buttonStyle(.bordered)
                        }
                    }
                }
                .card()

                // Live preview
                if amountNum > 0 {
                    VStack(spacing: 6) {
                        Text("\(Int(cal)) cal").font(.title2.weight(.bold).monospacedDigit())
                        HStack(spacing: 12) {
                            macroChip("P", value: ing.proteinPer100g * grams / 100, color: Theme.proteinRed)
                            macroChip("C", value: ing.carbsPer100g * grams / 100, color: Theme.carbsGreen)
                            macroChip("F", value: ing.fatPer100g * grams / 100, color: Theme.fatYellow)
                            macroChip("Fiber", value: ing.fiberPer100g * grams / 100, color: Theme.fiberBrown)
                        }
                        if selectedUnit != .grams {
                            Text("= \(Int(grams))g").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .card()
                }

                // Meal type
                Picker("", selection: $selectedMealType) {
                    ForEach(MealType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented).padding(.horizontal, 4)

                // Log button
                Button {
                    viewModel.quickAdd(
                        name: "\(ing.name) (\(amount) \(selectedUnit.label))",
                        calories: ing.caloriesPer100g * grams / 100,
                        proteinG: ing.proteinPer100g * grams / 100,
                        carbsG: ing.carbsPer100g * grams / 100,
                        fatG: ing.fatPer100g * grams / 100,
                        fiberG: ing.fiberPer100g * grams / 100,
                        mealType: selectedMealType
                    )
                    dismiss()
                } label: {
                    Label("Log Food", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(amountNum == 0)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
    }

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))g \(label)").font(.caption2.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }

    private func quickAmounts(for ing: RawIngredient) -> [(label: String, value: String, unit: ServingUnit)] {
        switch ing.typicalUnit {
        case .grams: return [("50g", "50", .grams), ("100g", "100", .grams), ("200g", "200", .grams), ("500g", "500", .grams)]
        case .cups: return [("½ cup", "0.5", .cups), ("1 cup", "1", .cups), ("2 cups", "2", .cups)]
        case .tablespoons: return [("1 tbsp", "1", .tablespoons), ("2 tbsp", "2", .tablespoons), ("1 cup", "1", .cups)]
        case .pieces: return [("1", "1", .pieces), ("2", "2", .pieces), ("3", "3", .pieces)]
        case .ml: return [("100ml", "100", .ml), ("200ml", "200", .ml), ("1 cup", "1", .cups)]
        default: return [("50g", "50", .grams), ("100g", "100", .grams)]
        }
    }

    // MARK: - Manual Mode

    private var manualView: some View {
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
                Picker("", selection: $selectedMealType) {
                    ForEach(MealType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Button {
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
                } label: {
                    Label("Log Food", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
                .disabled(calories.isEmpty)
            }
        }
    }

    private func macroField(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 35)
        }
    }
}
