import SwiftUI

// MARK: - Recipe Builder (was Quick Add)

struct QuickAddView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var recipeName = ""
    @State private var items: [RecipeItem] = []
    @State private var showingIngredientPicker = false
    @State private var editingIndex: Int?
    private let db = AppDatabase.shared

    struct RecipeItem: Identifiable {
        let id = UUID()
        var name: String
        var portionText: String
        var calories: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
        var fiberG: Double
    }

    private var total: (cal: Double, p: Double, c: Double, f: Double, fb: Double) {
        (items.reduce(0) { $0 + $1.calories },
         items.reduce(0) { $0 + $1.proteinG },
         items.reduce(0) { $0 + $1.carbsG },
         items.reduce(0) { $0 + $1.fatG },
         items.reduce(0) { $0 + $1.fiberG })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Recipe name (show after first ingredient added)
                    if !items.isEmpty {
                        TextField("Recipe name", text: $recipeName)
                            .font(.headline)
                            .padding(12)
                            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 12))
                    }

                    // Ingredients
                    VStack(alignment: .leading, spacing: 0) {
                        Text("INGREDIENTS").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                            .padding(.bottom, 8)

                        if items.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "fork.knife").font(.title2).foregroundStyle(Theme.accent.opacity(0.4))
                                Text("Add ingredients to build your recipe")
                                    .font(.subheadline).foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                        }

                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name).font(.subheadline).lineLimit(1)
                                    HStack(spacing: 4) {
                                        if !item.portionText.isEmpty {
                                            Text(item.portionText).font(.caption2).foregroundStyle(.tertiary)
                                            Text("\u{00B7}").font(.caption2).foregroundStyle(.quaternary)
                                        }
                                        Text("\(Int(item.calories)) cal")
                                            .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button { items.remove(at: i) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.tertiary)
                                }.buttonStyle(.plain)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .onTapGesture { editingIndex = i }
                            if i < items.count - 1 { Divider() }
                        }

                        Divider().padding(.vertical, 4)

                        Button { showingIngredientPicker = true } label: {
                            Label("Add ingredient", systemImage: "plus.circle")
                                .font(.subheadline).foregroundStyle(Theme.accent)
                        }.buttonStyle(.plain)
                    }
                    .card()

                    // Total + actions
                    if !items.isEmpty {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Total").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(total.cal)) cal").font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            HStack(spacing: 8) {
                                macroChip("P", value: total.p, color: Theme.proteinRed)
                                macroChip("C", value: total.c, color: Theme.carbsGreen)
                                macroChip("F", value: total.f, color: Theme.fatYellow)
                            }
                        }
                        .card()

                        Button {
                            saveAndLogRecipe()
                            dismiss()
                        } label: {
                            Text("Log").font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showingIngredientPicker) {
                IngredientPickerView { item in items.append(item) }
            }
            .sheet(item: editingIndexBinding) { idx in
                IngredientPickerView { replacement in
                    if idx.value < items.count {
                        items[idx.value] = replacement
                    }
                }
            }
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

    private var editingIndexBinding: Binding<IdentifiableInt?> {
        Binding(
            get: { editingIndex.map { IdentifiableInt(value: $0) } },
            set: { editingIndex = $0?.value }
        )
    }

    private func saveAndLogRecipe() {
        let t = total
        let name = recipeName.isEmpty ? (items.count == 1 ? items[0].name : "Recipe") : recipeName
        var fav = FavoriteFood(name: name, calories: t.cal, proteinG: t.p, carbsG: t.c,
                               fatG: t.f, fiberG: t.fb, isRecipe: items.count > 1)
        try? db.saveFavorite(&fav)
        viewModel.quickAdd(name: name, calories: t.cal, proteinG: t.p, carbsG: t.c,
                           fatG: t.f, fiberG: t.fb, mealType: viewModel.autoMealType)
    }
}

struct IdentifiableInt: Identifiable {
    let id = UUID()
    let value: Int
}

// MARK: - Ingredient Picker (search + serving picker)

private struct IngredientPickerView: View {
    let onAdd: (QuickAddView.RecipeItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Food] = []
    @State private var selectedFood: Food?
    @State private var amount = "1"
    @State private var selectedUnitIndex = 0
    @State private var showingManual = false
    @State private var manualName = ""
    @State private var manualCal = ""
    @State private var manualP = ""
    @State private var manualC = ""
    @State private var manualF = ""
    @State private var manualFb = ""
    @FocusState private var searchFocused: Bool

    private var ingredientResults: [RawIngredient] {
        if query.isEmpty { return [] }
        return RawIngredient.allCases.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search ingredient", text: $query)
                        .textFieldStyle(.plain).autocorrectionDisabled()
                        .focused($searchFocused)
                        .onChange(of: query) { _, q in
                            results = q.isEmpty ? [] : ((try? AppDatabase.shared.searchFoodsRanked(query: q)) ?? [])
                        }
                    if !query.isEmpty {
                        Button { query = ""; results = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                if let food = selectedFood {
                    servingPicker(food)
                } else {
                    ingredientList
                }
            }
            .navigationTitle("Add Ingredient").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingManual) { manualIngredientSheet }
            .onAppear {
                recentIngredients = (try? AppDatabase.shared.fetchRecentFoods(limit: 5)) ?? []
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchFocused = true }
            }
        }
    }

    @State private var recentIngredients: [Food] = []

    // MARK: - Ingredient List

    private var ingredientList: some View {
        List {
            Button { showingManual = true } label: {
                Label("Enter manually", systemImage: "pencil")
                    .font(.subheadline).foregroundStyle(Theme.accent)
            }

            if query.isEmpty && !recentIngredients.isEmpty {
                Section("Recent") {
                    ForEach(recentIngredients) { food in
                        Button {
                            amount = "1"
                            selectedUnitIndex = 0
                            selectedFood = food
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name).font(.subheadline)
                                Text(food.macroSummary).font(.caption).foregroundStyle(.secondary)
                            }
                        }.tint(.primary)
                    }
                }
            }

            if !results.isEmpty {
                Section("Foods") {
                    ForEach(results) { food in
                        Button {
                            amount = "1"
                            selectedUnitIndex = 0
                            selectedFood = food
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name).font(.subheadline)
                                Text(food.macroSummary).font(.caption).foregroundStyle(.secondary)
                            }
                        }.tint(.primary)
                    }
                }
            }

            if !ingredientResults.isEmpty {
                Section("Raw Ingredients") {
                    ForEach(ingredientResults) { ing in
                        Button {
                            let gpp = ing.gramsPerPiece
                            let scale = gpp / 100.0
                            let food = Food(name: ing.name, category: "Ingredient",
                                            servingSize: gpp, servingUnit: "g",
                                            calories: ing.caloriesPer100g * scale,
                                            proteinG: ing.proteinPer100g * scale,
                                            carbsG: ing.carbsPer100g * scale,
                                            fatG: ing.fatPer100g * scale,
                                            fiberG: ing.fiberPer100g * scale)
                            amount = "1"
                            selectedUnitIndex = 0
                            selectedFood = food
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ing.name).font(.subheadline)
                                Text("\(Int(ing.caloriesPer100g)) cal/100g").font(.caption).foregroundStyle(.secondary)
                            }
                        }.tint(.primary)
                    }
                }
            }
        }.listStyle(.plain)
    }

    // MARK: - Serving Picker

    private func servingPicker(_ food: Food) -> some View {
        let units = FoodUnit.smartUnits(for: food)
        let safeIndex = min(selectedUnitIndex, max(units.count - 1, 0))
        let unit = units.isEmpty ? FoodUnit(label: "g", gramsEquivalent: 1) : units[safeIndex]
        let amountNum = Double(amount) ?? 0
        let totalGrams = amountNum * unit.gramsEquivalent
        let multiplier = food.servingSize > 0 ? totalGrams / food.servingSize : amountNum

        return ScrollView {
            VStack(spacing: 16) {
                // Back to search
                HStack {
                    Button { selectedFood = nil } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.caption).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                }

                // Food info
                VStack(spacing: 4) {
                    Text(food.name).font(.headline)
                    Text("\(food.macroSummary) per \(Int(food.servingSize))\(food.servingUnit)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // Amount + unit
                HStack(spacing: 12) {
                    TextField("1", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.medium).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .frame(width: 80)
                        .padding(.vertical, 10)
                        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))

                    Picker("", selection: $selectedUnitIndex) {
                        ForEach(0..<units.count, id: \.self) { i in
                            Text(units[i].label).tag(i)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .padding(.vertical, 10).padding(.horizontal, 16)
                    .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: selectedUnitIndex) { oldIdx, newIdx in
                        guard oldIdx < units.count, newIdx < units.count else { return }
                        let oldUnit = units[oldIdx]
                        let newUnit = units[newIdx]
                        let currentAmount = Double(amount) ?? 0
                        let grams = currentAmount * oldUnit.gramsEquivalent
                        let converted = newUnit.gramsEquivalent > 0 ? grams / newUnit.gramsEquivalent : currentAmount
                        amount = converted == Double(Int(converted)) ? "\(Int(converted))" : String(format: "%.1f", converted)
                    }
                }

                // Quick buttons
                HStack(spacing: 6) {
                    ForEach([0.5, 1.0, 1.5, 2.0], id: \.self) { mult in
                        Button {
                            if unit.label == "g" {
                                amount = String(format: "%.0f", food.servingSize * mult)
                            } else {
                                amount = mult == Double(Int(mult)) ? "\(Int(mult))" : String(format: "%.1f", mult)
                            }
                        } label: {
                            Text(mult == 0.5 ? "\u{00BD}" : (mult == 1.5 ? "1\u{00BD}" : "\(Int(mult))x"))
                                .font(.caption.weight(.medium))
                        }.buttonStyle(.bordered)
                    }
                }

                // Nutrition preview
                VStack(spacing: 4) {
                    Text("\(Int(food.calories * multiplier)) cal")
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text("\(Int(food.proteinG * multiplier))P \u{00B7} \(Int(food.carbsG * multiplier))C \u{00B7} \(Int(food.fatG * multiplier))F")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)

                // Add button
                Button {
                    let portionText = formatPortion(amount: amount, unitLabel: unit.label)
                    onAdd(QuickAddView.RecipeItem(
                        name: food.name, portionText: portionText,
                        calories: food.calories * multiplier,
                        proteinG: food.proteinG * multiplier,
                        carbsG: food.carbsG * multiplier,
                        fatG: food.fatG * multiplier,
                        fiberG: food.fiberG * multiplier
                    ))
                    dismiss()
                } label: {
                    Text("Add to Recipe").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            .padding(16)
        }
        .background(Theme.background)
    }

    private func formatPortion(amount: String, unitLabel: String) -> String {
        let num = Double(amount) ?? 0
        if num == Double(Int(num)) {
            return "\(Int(num)) \(unitLabel)"
        }
        return "\(amount) \(unitLabel)"
    }

    // MARK: - Manual Ingredient Sheet

    private var manualIngredientSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $manualName)
                HStack { Text("Calories"); Spacer(); TextField("0", text: $manualCal).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Protein (g)"); Spacer(); TextField("0", text: $manualP).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Carbs (g)"); Spacer(); TextField("0", text: $manualC).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Fat (g)"); Spacer(); TextField("0", text: $manualF).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                HStack { Text("Fiber (g)"); Spacer(); TextField("0", text: $manualFb).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
            }
            .navigationTitle("Manual Entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingManual = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(QuickAddView.RecipeItem(
                            name: manualName.isEmpty ? "Item" : manualName,
                            portionText: "",
                            calories: Double(manualCal) ?? 0,
                            proteinG: Double(manualP) ?? 0,
                            carbsG: Double(manualC) ?? 0,
                            fatG: Double(manualF) ?? 0,
                            fiberG: Double(manualFb) ?? 0
                        ))
                        showingManual = false
                        dismiss()
                    }
                    .disabled(manualCal.isEmpty)
                }
            }
        }
    }
}
