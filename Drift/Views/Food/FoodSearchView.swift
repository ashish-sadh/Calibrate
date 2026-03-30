import SwiftUI

struct FoodSearchView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFood: Food?
    @State private var showingLogSheet = false
    @State private var amount: String = "1"
    @State private var selectedUnit: ServingUnit = .grams
    @State private var selectedMealType: MealType = .lunch
    @State private var query = ""
    @State private var results: [Food] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search for a food", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .onChange(of: query) { _, q in
                            results = q.isEmpty ? [] : ((try? AppDatabase.shared.searchFoods(query: q)) ?? [])
                        }
                    if !query.isEmpty {
                        Button { query = ""; results = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                if results.isEmpty && !query.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.tertiary)
                        Text("No results for \"\(query)\"")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Try a different spelling or use Quick Add")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                } else if results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "fork.knife").font(.title2).foregroundStyle(Theme.accent.opacity(0.5))
                        Text("Search the food database")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Type to search 128+ foods")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                } else {
                    List {
                        ForEach(results) { food in
                            Button {
                                selectedFood = food
                                // Set default amount based on food's serving
                                amount = String(format: "%.0f", food.servingSize)
                                selectedUnit = food.servingUnit == "ml" ? .ml : .grams
                                showingLogSheet = true
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).font(.subheadline)
                                    Text("\(food.macroSummary) · \(Int(food.servingSize))\(food.servingUnit)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .tint(.primary)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search Food").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showingLogSheet) {
                if let food = selectedFood {
                    logFoodSheet(food)
                }
            }
        }
    }

    // MARK: - Log Food Sheet with amount + units

    private func logFoodSheet(_ food: Food) -> some View {
        let amountNum = Double(amount) ?? 0
        let grams = selectedUnit.toGrams(amountNum, foodServingSize: food.servingSize)
        let multiplier = food.servingSize > 0 ? grams / food.servingSize : 1

        return NavigationStack {
            Form {
                Section {
                    Text(food.name).font(.headline)
                    Text("\(food.macroSummary) per \(Int(food.servingSize))\(food.servingUnit)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Amount") {
                    HStack {
                        TextField("0", text: $amount)
                            .keyboardType(.decimalPad)
                            .font(.title3.monospacedDigit())
                        Picker("Unit", selection: $selectedUnit) {
                            Text("g").tag(ServingUnit.grams)
                            Text("serving").tag(ServingUnit.pieces)
                            Text("cup").tag(ServingUnit.cups)
                            Text("tbsp").tag(ServingUnit.tablespoons)
                        }
                        .pickerStyle(.menu)
                    }

                    // Quick amount buttons
                    HStack(spacing: 6) {
                        quickBtn("½", value: String(format: "%.0f", food.servingSize * 0.5), unit: .grams)
                        quickBtn("1x", value: String(format: "%.0f", food.servingSize), unit: .grams)
                        quickBtn("1.5x", value: String(format: "%.0f", food.servingSize * 1.5), unit: .grams)
                        quickBtn("2x", value: String(format: "%.0f", food.servingSize * 2), unit: .grams)
                        quickBtn("1 cup", value: "1", unit: .cups)
                    }
                }

                Section("Meal") {
                    Picker("", selection: $selectedMealType) {
                        ForEach(MealType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Total Nutrition") {
                    macroRow("Calories", value: food.calories * multiplier)
                    macroRow("Protein", value: food.proteinG * multiplier, unit: "g")
                    macroRow("Carbs", value: food.carbsG * multiplier, unit: "g")
                    macroRow("Fat", value: food.fatG * multiplier, unit: "g")
                    macroRow("Fiber", value: food.fiberG * multiplier, unit: "g")
                }
            }
            .navigationTitle("Log Food").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingLogSheet = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        viewModel.logFood(food, servings: multiplier, mealType: selectedMealType)
                        showingLogSheet = false
                        dismiss()
                    }
                }
            }
        }
    }

    private func quickBtn(_ label: String, value: String, unit: ServingUnit) -> some View {
        Button {
            amount = value
            selectedUnit = unit
        } label: {
            Text(label).font(.caption)
        }
        .buttonStyle(.bordered)
    }

    private func macroRow(_ label: String, value: Double, unit: String = "kcal") -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value)) \(unit)").monospacedDigit().foregroundStyle(.secondary)
        }
    }
}

// MARK: - ServingUnit extension for food-relative conversion

extension ServingUnit {
    /// Convert amount to grams, using the food's serving size as reference for "pieces" (servings).
    func toGrams(_ amount: Double, foodServingSize: Double) -> Double {
        switch self {
        case .grams: return amount
        case .pieces: return amount * foodServingSize // 1 serving = food's serving size
        case .cups: return amount * 240 // generic cup = 240g
        case .tablespoons: return amount * 15
        case .teaspoons: return amount * 5
        case .ml: return amount
        }
    }
}
