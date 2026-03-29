import SwiftUI

struct FoodSearchView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFood: Food?
    @State private var servings: Double = 1.0
    @State private var selectedMealType: MealType = .lunch

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search for a food", text: $viewModel.searchQuery)
                        .textFieldStyle(.plain)
                        .onChange(of: viewModel.searchQuery) { _, _ in
                            viewModel.search()
                        }
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                            viewModel.searchResults = []
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                // Results
                List {
                    ForEach(viewModel.searchResults) { food in
                        Button {
                            selectedFood = food
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(food.name)
                                        .font(.subheadline)
                                    Text("\(food.macroSummary) - \(Int(food.servingSize))\(food.servingUnit)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(.blue)
                            }
                        }
                        .tint(.primary)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Search Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $selectedFood) { food in
                logFoodSheet(food)
            }
        }
    }

    private func logFoodSheet(_ food: Food) -> some View {
        NavigationStack {
            Form {
                Section {
                    Text(food.name)
                        .font(.headline)
                    Text(food.macroSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Per \(Int(food.servingSize))\(food.servingUnit)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Section("Servings") {
                    HStack {
                        TextField("1.0", value: $servings, format: .number)
                            .keyboardType(.decimalPad)
                        Stepper("", value: $servings, in: 0.25...10, step: 0.25)
                    }
                }

                Section("Meal") {
                    Picker("Meal Type", selection: $selectedMealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Total Nutrition") {
                    macroRow("Calories", value: food.calories * servings)
                    macroRow("Protein", value: food.proteinG * servings, unit: "g")
                    macroRow("Carbs", value: food.carbsG * servings, unit: "g")
                    macroRow("Fat", value: food.fatG * servings, unit: "g")
                    macroRow("Fiber", value: food.fiberG * servings, unit: "g")
                }
            }
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { selectedFood = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        viewModel.logFood(food, servings: servings, mealType: selectedMealType)
                        selectedFood = nil
                        dismiss()
                    }
                }
            }
        }
    }

    private func macroRow(_ label: String, value: Double, unit: String = "kcal") -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(Int(value)) \(unit)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

