import SwiftUI

struct QuickAddView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var mode: AddMode = .manual
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var selectedMealType: MealType = .lunch
    // Ingredient mode
    @State private var selectedIngredient: RawIngredient?
    @State private var amount = ""
    @State private var selectedUnit: ServingUnit = .grams

    enum AddMode: String, CaseIterable {
        case manual = "Manual"
        case ingredient = "Ingredient"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Mode picker
                Picker("Mode", selection: $mode) {
                    ForEach(AddMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if mode == .ingredient {
                    ingredientSection
                } else {
                    manualSection
                }

                Section("Meal") {
                    Picker("", selection: $selectedMealType) {
                        ForEach(MealType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                // Preview
                if estimatedCalories > 0 {
                    Section("Estimated") {
                        HStack {
                            Text("\(Int(estimatedCalories)) cal").font(.headline.monospacedDigit())
                            Spacer()
                            Text("\(Int(estimatedProtein))P \(Int(estimatedCarbs))C \(Int(estimatedFat))F")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Quick Add").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { logFood() }
                        .disabled(estimatedCalories == 0 && calories.isEmpty)
                }
            }
        }
    }

    // MARK: - Manual Entry

    private var manualSection: some View {
        Group {
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
        }
    }

    // MARK: - Ingredient Mode

    private var ingredientSection: some View {
        Group {
            Section("Ingredient") {
                Picker("Select", selection: $selectedIngredient) {
                    Text("Choose...").tag(nil as RawIngredient?)
                    ForEach(RawIngredient.allCases) { ing in
                        Text(ing.name).tag(ing as RawIngredient?)
                    }
                }
            }

            if selectedIngredient != nil {
                Section("Amount") {
                    HStack {
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title3.monospacedDigit())
                        Picker("Unit", selection: $selectedUnit) {
                            ForEach(ServingUnit.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.menu)
                    }

                    // Quick amount buttons
                    HStack(spacing: 8) {
                        ForEach(quickAmounts, id: \.label) { qa in
                            Button(qa.label) { amount = qa.value; selectedUnit = qa.unit }
                                .font(.caption).buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var quickAmounts: [(label: String, value: String, unit: ServingUnit)] {
        guard let ing = selectedIngredient else { return [] }
        switch ing.typicalUnit {
        case .grams: return [("50g", "50", .grams), ("100g", "100", .grams), ("200g", "200", .grams)]
        case .cups: return [("½ cup", "0.5", .cups), ("1 cup", "1", .cups), ("2 cups", "2", .cups)]
        case .tablespoons: return [("1 tbsp", "1", .tablespoons), ("2 tbsp", "2", .tablespoons)]
        case .pieces: return [("1", "1", .pieces), ("2", "2", .pieces), ("3", "3", .pieces)]
        default: return [("50g", "50", .grams), ("100g", "100", .grams)]
        }
    }

    // MARK: - Calculations

    private var estimatedCalories: Double {
        if mode == .manual { return Double(calories) ?? 0 }
        guard let ing = selectedIngredient, let amt = Double(amount), amt > 0 else { return 0 }
        let grams = selectedUnit.toGrams(amt, ingredient: ing)
        return ing.caloriesPer100g * grams / 100
    }

    private var estimatedProtein: Double {
        if mode == .manual { return Double(protein) ?? 0 }
        guard let ing = selectedIngredient, let amt = Double(amount), amt > 0 else { return 0 }
        return ing.proteinPer100g * selectedUnit.toGrams(amt, ingredient: ing) / 100
    }

    private var estimatedCarbs: Double {
        if mode == .manual { return Double(carbs) ?? 0 }
        guard let ing = selectedIngredient, let amt = Double(amount), amt > 0 else { return 0 }
        return ing.carbsPer100g * selectedUnit.toGrams(amt, ingredient: ing) / 100
    }

    private var estimatedFat: Double {
        if mode == .manual { return Double(fat) ?? 0 }
        guard let ing = selectedIngredient, let amt = Double(amount), amt > 0 else { return 0 }
        return ing.fatPer100g * selectedUnit.toGrams(amt, ingredient: ing) / 100
    }

    // MARK: - Log

    private func logFood() {
        if mode == .ingredient, let ing = selectedIngredient {
            let grams = selectedUnit.toGrams(Double(amount) ?? 0, ingredient: ing)
            viewModel.quickAdd(
                name: "\(ing.name) (\(amount) \(selectedUnit.label))",
                calories: ing.caloriesPer100g * grams / 100,
                proteinG: ing.proteinPer100g * grams / 100,
                carbsG: ing.carbsPer100g * grams / 100,
                fatG: ing.fatPer100g * grams / 100,
                fiberG: ing.fiberPer100g * grams / 100,
                mealType: selectedMealType
            )
        } else {
            viewModel.quickAdd(
                name: name.isEmpty ? "Quick Add" : name,
                calories: Double(calories) ?? 0,
                proteinG: Double(protein) ?? 0,
                carbsG: Double(carbs) ?? 0,
                fatG: Double(fat) ?? 0,
                fiberG: Double(fiber) ?? 0,
                mealType: selectedMealType
            )
        }
        dismiss()
    }

    private func macroField(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 35)
        }
    }
}

// MARK: - Serving Units

enum ServingUnit: String, CaseIterable, Sendable {
    case grams, cups, tablespoons, teaspoons, pieces, ml

    var label: String {
        switch self {
        case .grams: "g"
        case .cups: "cup"
        case .tablespoons: "tbsp"
        case .teaspoons: "tsp"
        case .pieces: "pc"
        case .ml: "ml"
        }
    }

    /// Convert to grams based on ingredient density.
    func toGrams(_ amount: Double, ingredient: RawIngredient) -> Double {
        switch self {
        case .grams: return amount
        case .cups: return amount * ingredient.gramsPerCup
        case .tablespoons: return amount * ingredient.gramsPerCup / 16
        case .teaspoons: return amount * ingredient.gramsPerCup / 48
        case .pieces: return amount * ingredient.gramsPerPiece
        case .ml: return amount // approximate 1ml = 1g for liquids
        }
    }
}

// MARK: - Raw Ingredients (common cooking items with per-100g macros)

enum RawIngredient: String, CaseIterable, Identifiable, Sendable {
    case rice, wheat_flour, oats, sugar, oil, butter, ghee, milk,
         chicken_raw, egg, paneer, tofu, lentils, chickpeas,
         potato, onion, tomato, spinach, banana, apple,
         peanuts, almonds, cashews, coconut, honey

    var id: String { rawValue }

    var name: String {
        switch self {
        case .rice: "Rice (raw)"
        case .wheat_flour: "Wheat Flour (atta)"
        case .oats: "Oats (dry)"
        case .sugar: "Sugar"
        case .oil: "Oil (any)"
        case .butter: "Butter"
        case .ghee: "Ghee"
        case .milk: "Milk (whole)"
        case .chicken_raw: "Chicken (raw)"
        case .egg: "Egg"
        case .paneer: "Paneer"
        case .tofu: "Tofu"
        case .lentils: "Lentils/Dal (dry)"
        case .chickpeas: "Chickpeas (dry)"
        case .potato: "Potato"
        case .onion: "Onion"
        case .tomato: "Tomato"
        case .spinach: "Spinach"
        case .banana: "Banana"
        case .apple: "Apple"
        case .peanuts: "Peanuts"
        case .almonds: "Almonds"
        case .cashews: "Cashews"
        case .coconut: "Coconut (fresh)"
        case .honey: "Honey"
        }
    }

    var caloriesPer100g: Double {
        switch self {
        case .rice: 360; case .wheat_flour: 340; case .oats: 389; case .sugar: 387
        case .oil: 884; case .butter: 717; case .ghee: 900; case .milk: 62
        case .chicken_raw: 120; case .egg: 155; case .paneer: 265; case .tofu: 144
        case .lentils: 353; case .chickpeas: 364; case .potato: 77; case .onion: 40
        case .tomato: 18; case .spinach: 23; case .banana: 89; case .apple: 52
        case .peanuts: 567; case .almonds: 579; case .cashews: 553; case .coconut: 354
        case .honey: 304
        }
    }

    var proteinPer100g: Double {
        switch self {
        case .rice: 7; case .wheat_flour: 13; case .oats: 17; case .sugar: 0
        case .oil: 0; case .butter: 0.9; case .ghee: 0; case .milk: 3.2
        case .chicken_raw: 23; case .egg: 13; case .paneer: 18; case .tofu: 15
        case .lentils: 25; case .chickpeas: 19; case .potato: 2; case .onion: 1.1
        case .tomato: 0.9; case .spinach: 2.9; case .banana: 1.1; case .apple: 0.3
        case .peanuts: 26; case .almonds: 21; case .cashews: 18; case .coconut: 3.3
        case .honey: 0.3
        }
    }

    var carbsPer100g: Double {
        switch self {
        case .rice: 80; case .wheat_flour: 72; case .oats: 66; case .sugar: 100
        case .oil: 0; case .butter: 0.1; case .ghee: 0; case .milk: 4.8
        case .chicken_raw: 0; case .egg: 1.1; case .paneer: 3; case .tofu: 3
        case .lentils: 60; case .chickpeas: 61; case .potato: 17; case .onion: 9
        case .tomato: 3.9; case .spinach: 3.6; case .banana: 23; case .apple: 14
        case .peanuts: 16; case .almonds: 22; case .cashews: 30; case .coconut: 15
        case .honey: 82
        }
    }

    var fatPer100g: Double {
        switch self {
        case .rice: 0.7; case .wheat_flour: 1.5; case .oats: 7; case .sugar: 0
        case .oil: 100; case .butter: 81; case .ghee: 100; case .milk: 3.3
        case .chicken_raw: 3.6; case .egg: 11; case .paneer: 21; case .tofu: 8
        case .lentils: 1; case .chickpeas: 6; case .potato: 0.1; case .onion: 0.1
        case .tomato: 0.2; case .spinach: 0.4; case .banana: 0.3; case .apple: 0.2
        case .peanuts: 49; case .almonds: 50; case .cashews: 44; case .coconut: 33
        case .honey: 0
        }
    }

    var fiberPer100g: Double {
        switch self {
        case .rice: 1.3; case .wheat_flour: 11; case .oats: 11; case .sugar: 0
        case .oil: 0; case .butter: 0; case .ghee: 0; case .milk: 0
        case .chicken_raw: 0; case .egg: 0; case .paneer: 0; case .tofu: 1
        case .lentils: 11; case .chickpeas: 12; case .potato: 2.2; case .onion: 1.7
        case .tomato: 1.2; case .spinach: 2.2; case .banana: 2.6; case .apple: 2.4
        case .peanuts: 8.5; case .almonds: 12; case .cashews: 3; case .coconut: 9
        case .honey: 0.2
        }
    }

    /// Grams per cup (approximate).
    var gramsPerCup: Double {
        switch self {
        case .rice: 185; case .wheat_flour: 120; case .oats: 80; case .sugar: 200
        case .oil: 218; case .butter: 227; case .ghee: 218; case .milk: 244
        case .chicken_raw: 140; case .egg: 243; case .paneer: 150; case .tofu: 126
        case .lentils: 190; case .chickpeas: 164; case .potato: 150; case .onion: 160
        case .tomato: 180; case .spinach: 30; case .banana: 150; case .apple: 125
        case .peanuts: 146; case .almonds: 143; case .cashews: 137; case .coconut: 80
        case .honey: 340
        }
    }

    /// Grams per piece (for countable items).
    var gramsPerPiece: Double {
        switch self {
        case .egg: 50; case .banana: 120; case .apple: 180; case .potato: 150
        case .onion: 110; case .tomato: 120
        default: 100
        }
    }

    var typicalUnit: ServingUnit {
        switch self {
        case .egg, .banana, .apple: .pieces
        case .oil, .butter, .ghee, .honey: .tablespoons
        case .milk: .ml
        default: .grams
        }
    }
}
