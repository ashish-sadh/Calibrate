import SwiftUI
import DriftCore

// MARK: - Recipe Builder (was Quick Add)

struct QuickAddView: View {
    @Bindable var viewModel: FoodLogViewModel
    var initialItems: [RecipeItem] = []   // pre-populated ingredients (from AI chat)
    var initialName: String = ""          // pre-set recipe name (e.g., "Lunch")
    /// When set, the sheet is editing an existing recipe row in-place (#192)
    /// rather than creating a new one. Save updates the row and dismisses —
    /// no new food-log entry is written.
    var editingRecipeID: Int64? = nil
    /// Initial expandOnLog value when editing (#190) — propagates existing state.
    var initialExpandOnLog: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var recipeName = ""
    @State private var items: [RecipeItem] = []
    @State private var showingIngredientPicker = false
    @State private var editingIndex: Int?
    @State private var recipeLogTime = Date()
    @State private var recipeMealType: MealType = .snack
    @State private var recipeMealResolved = false
    @State private var recipeServings = "1"
    @State private var expandOnLog = false
    @State private var showingDeleteConfirm = false

    /// Top-level type lives in DriftCore so AppDatabase + ConversationState can persist it.
    typealias RecipeItem = DriftCore.RecipeItem

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
                    // Past-day target must be visible on the committing
                    // surface itself (2026-07-09 field ask).
                    if !viewModel.isToday {
                        PastDayLogBadge(date: viewModel.selectedDate)
                    }
                    // Recipe name (show after first ingredient added)
                    if !items.isEmpty {
                        TextField("Meal name", text: $recipeName)
                            .font(.headline)
                            .padding(12)
                            .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }

                    // Ingredients
                    VStack(alignment: .leading, spacing: 0) {
                        Text("FOOD ITEMS").font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            .padding(.bottom, 8)

                        if items.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "fork.knife").font(.title2).foregroundStyle(Theme.accent.opacity(0.4))
                                Text("Add food items to build your meal")
                                    .font(.subheadline).foregroundStyle(Theme.textTertiary)
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
                                            Text(item.portionText).font(.caption2).foregroundStyle(Theme.textTertiary)
                                            Text("\u{00B7}").font(.caption2).foregroundStyle(Theme.textTertiary)
                                        }
                                        Text("\(Int(item.calories)) cal")
                                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer()
                                Button { items.remove(at: i) } label: {
                                    Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(Theme.textTertiary)
                                }
                                .accessibilityLabel("Remove food item")
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                            .onTapGesture { editingIndex = i }
                            if i < items.count - 1 { Divider() }
                        }

                        Divider().padding(.vertical, 4)

                        Button { showingIngredientPicker = true } label: {
                            Label("Add food item", systemImage: "plus.circle")
                                .font(.subheadline).foregroundStyle(Theme.accent)
                        }.buttonStyle(.plain)
                    }
                    .card()

                    // Total + actions
                    if !items.isEmpty {
                        VStack(spacing: 6) {
                            HStack {
                                Text("Total").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
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

                        // Servings
                        HStack {
                            Text("Servings").font(.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            TextField("1", text: $recipeServings)
                                .keyboardType(.decimalPad)
                                .font(.subheadline.monospacedDigit())
                                .multilineTextAlignment(.trailing)
                                .frame(width: 50)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusChip))

                        // Expand on log toggle (#190) — enabled only for multi-item recipes.
                        // When on, re-logging this recipe inserts one FoodEntry per
                        // ingredient instead of a single aggregated entry.
                        if items.count > 1 {
                            Toggle(isOn: $expandOnLog) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Log items individually").font(.subheadline)
                                    Text("Adds each ingredient as a separate entry")
                                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .tint(Theme.accent)
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
                        }

                        MealTimePicker(time: $recipeLogTime, mealType: $recipeMealType)

                        Button {
                            saveAndLogRecipe()
                            dismiss()
                        } label: {
                            Text(editingRecipeID == nil ? "Log" : "Save Changes")
                                .font(.headline).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Build a Meal").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if editingRecipeID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { showingDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .alert("Delete meal?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteCombo() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This meal will be permanently deleted.")
            }
            .onAppear {
                if items.isEmpty && !initialItems.isEmpty {
                    items = initialItems
                    recipeName = initialName
                }
                // Same one-shot default as FoodLogSheet — don't clobber a
                // user-picked meal on body refreshes.
                if !recipeMealResolved {
                    recipeMealType = MealType.resolve(now: Date(), recentEntries: viewModel.todayEntries)
                    recipeMealResolved = true
                }
                // For NEW multi-item logs (from AI chat), default to expanding
                // each ingredient into its own diary entry — matches
                // ComboLogSheet behaviour and prevents the "logged breakfast
                // with 2 items, only saw one in diary" surprise. Editing a
                // saved recipe uses whatever `initialExpandOnLog` passed in.
                if editingRecipeID != nil {
                    expandOnLog = initialExpandOnLog
                } else {
                    expandOnLog = initialExpandOnLog || initialItems.count > 1
                }
            }
            .sheet(isPresented: $showingIngredientPicker) {
                IngredientPickerView { item in items.append(item) }
            }
            .sheet(item: editingIndexBinding) { idx in
                IngredientPickerView(
                    onAdd: { replacement in
                        if idx.value < items.count {
                            items[idx.value] = replacement
                        }
                    },
                    editingItem: idx.value < items.count ? items[idx.value] : nil
                )
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

    private func deleteCombo() {
        guard let id = editingRecipeID else { return }
        try? AppDatabase.shared.writer.write { db in try Food.deleteOne(db, key: id) }
        viewModel.loadSuggestions()
        dismiss()
    }

    private func saveAndLogRecipe() {
        let servings = max(Double(recipeServings) ?? 1, 0.1)
        let name = recipeName.isEmpty ? (items.count == 1 ? items[0].name : "Meal") : recipeName
        let effectiveExpand = items.count > 1 && expandOnLog

        // Edit mode (#192): update the existing recipe row in place and
        // dismiss — the user is modifying, not re-logging.
        if let editingID = editingRecipeID {
            FoodService.updateRecipe(id: editingID, name: name, items: items, servings: servings, expandOnLog: effectiveExpand)
            return
        }

        // Create mode: new recipe + log it.
        let t = total
        // Store full ingredient data as JSON for recipe rebuilding
        let ingredientsJson = (try? JSONEncoder().encode(items))
            .flatMap { String(data: $0, encoding: .utf8) }
        // Save recipe with per-serving macros
        let perServingCal = t.cal / servings
        let perServingP = t.p / servings
        let perServingC = t.c / servings
        let perServingF = t.f / servings
        let perServingFb = t.fb / servings
        var fav = SavedFood(name: name, calories: perServingCal, proteinG: perServingP,
                               carbsG: perServingC, fatG: perServingF, fiberG: perServingFb,
                               isRecipe: items.count > 1, ingredients: ingredientsJson,
                               expandOnLog: effectiveExpand)
        FoodService.saveRecipe(&fav)
        let totalServing = items.reduce(0.0) { $0 + $1.servingSizeG }
        let loggedAtStr = ISO8601DateFormatter().string(from: recipeLogTime)

        // If expandOnLog: insert one entry per ingredient × servings —
        // same helper ComboLogSheet uses, so the diary rows match across
        // entry points. Otherwise: aggregated single entry.
        if effectiveExpand {
            viewModel.logRecipeItems(items,
                                     recipeServings: servings,
                                     mealType: recipeMealType,
                                     loggedAt: loggedAtStr)
        } else {
            viewModel.quickAdd(name: name, calories: perServingCal, proteinG: perServingP,
                               carbsG: perServingC, fatG: perServingF, fiberG: perServingFb,
                               mealType: recipeMealType, loggedAt: loggedAtStr,
                               servingSizeG: totalServing / servings, servings: servings)
        }
    }
}

// MARK: - Ingredient Picker (search + serving picker)

private struct IngredientPickerView: View {
    let onAdd: (QuickAddView.RecipeItem) -> Void
    var editingItem: QuickAddView.RecipeItem? = nil  // non-nil = edit mode (pre-populate)
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Food] = []
    @State private var searchDebounceTask: Task<Void, Never>?
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
    @State private var manualServing = "1"
    @State private var manualServingUnit = "serving"
    @FocusState private var searchFocused: Bool
    @State private var addedCount = 0
    @State private var addedCal = 0.0

    private var ingredientResults: [RawIngredient] {
        if query.isEmpty { return [] }
        return RawIngredient.allCases.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search food", text: $query)
                        .textFieldStyle(.plain).autocorrectionDisabled()
                        .focused($searchFocused)
                        .onChange(of: query) { _, q in
                            // Debounce + off-main (#946): don't run the 5,460-food
                            // Levenshtein + LIKE scans on the main thread per keystroke.
                            searchDebounceTask?.cancel()
                            if q.isEmpty { results = []; return }
                            searchDebounceTask = Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                guard !Task.isCancelled else { return }
                                let found = await Task.detached { FoodService.searchFood(query: q) }.value
                                guard !Task.isCancelled else { return }
                                results = found
                            }
                        }
                    if !query.isEmpty {
                        Button { query = ""; results = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding()
                .background(Theme.cardBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5)
                }

                if let food = selectedFood {
                    servingPicker(food)
                } else {
                    ingredientList
                }
            }
            .navigationTitle(editingItem != nil ? "Edit Food Item" : "Add Food Item").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editingItem != nil ? "Cancel" : "Done") { dismiss() }
                }
                if addedCount > 0 {
                    ToolbarItem(placement: .principal) {
                        Text("\(addedCount) added \u{00B7} \(Int(addedCal)) cal")
                            .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editingItem != nil ? "Save" : "Add") { addSelectedIngredient() }
                        .fontWeight(.semibold)
                        .disabled(!canAddSelected)
                }
            }
            .sheet(isPresented: $showingManual) { manualIngredientSheet }
            .onAppear {
                recentIngredients = FoodService.fetchRecentFoods(limit: 5)
                if let item = editingItem {
                    // Edit mode: pre-fill search and auto-select the food
                    query = item.name
                    results = FoodService.searchFood(query: item.name)
                    if let food = results.first, food.name.lowercased() == item.name.lowercased() {
                        selectedFood = food
                        // #1034: `amount` is interpreted in the unit at `selectedUnitIndex`, which
                        // stays at 0 (= smartUnits.first). Compute it in THAT unit's grams, not in
                        // "servings" — otherwise a gram-serving food (unit[0] = "g", gramsEquivalent
                        // 1) reads "1 serving" as "1 gram" and Save collapses the item to ~0 cal.
                        // Derive the item's real grams first (servingSizeG, or calories for older
                        // entries), then divide by the default unit's grams.
                        let itemGrams: Double
                        if item.servingSizeG > 0 {
                            itemGrams = item.servingSizeG
                        } else if food.calories > 0 && food.servingSize > 0 {
                            itemGrams = (item.calories / food.calories) * food.servingSize
                        } else {
                            itemGrams = food.servingSize
                        }
                        let unitGrams = FoodUnit.smartUnits(for: food).first?.gramsEquivalent ?? 1
                        let amt = unitGrams > 0 ? itemGrams / unitGrams : 1
                        amount = amt == Double(Int(amt)) ? "\(Int(amt))" : String(format: "%.1f", amt)
                    }
                } else {
                    // #premium-polish: next-runloop focus instead of a 300ms
                    // dead gap — keyboard rises with the sheet.
                    Task { @MainActor in searchFocused = true }
                }
            }
        }
    }

    @State private var recentIngredients: [Food] = []
    @State private var selectedCategory: String? = nil
    private let categories = ["Vegetables", "Fruits", "Proteins", "Grains & Cereals", "Nuts & Seeds", "Dairy"]

    private var filteredRecent: [Food] {
        guard let cat = selectedCategory else { return recentIngredients }
        return recentIngredients.filter { $0.category.localizedCaseInsensitiveContains(cat) }
    }

    // MARK: - Ingredient List

    private var ingredientList: some View {
        List {
            Button { showingManual = true } label: {
                Label("Enter manually", systemImage: "pencil")
                    .font(.subheadline).foregroundStyle(Theme.accent)
            }

            // Category filter chips — always visible when no search
            if query.isEmpty {
                Section("Browse") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            // All chip
                            Button {
                                selectedCategory = nil
                                results = []
                            } label: {
                                Text("All")
                                    .font(.caption.weight(selectedCategory == nil ? .semibold : .medium))
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(selectedCategory == nil ? Theme.ink : Theme.cardBackgroundElevated, in: Capsule())
                                    .foregroundStyle(selectedCategory == nil ? .white : .secondary)
                            }.buttonStyle(.plain)

                            ForEach(categories, id: \.self) { cat in
                                Button {
                                    selectedCategory = cat
                                    results = FoodService.fetchFoodsByCategory(cat)
                                } label: {
                                    Text(cat == "Grains & Cereals" ? "Grains" : cat)
                                        .font(.caption.weight(selectedCategory == cat ? .semibold : .medium))
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(selectedCategory == cat ? Theme.ink : Theme.cardBackgroundElevated, in: Capsule())
                                        .foregroundStyle(selectedCategory == cat ? .white : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 4)
                    }
                }
            }

            if query.isEmpty && !filteredRecent.isEmpty {
                Section("Recent") {
                    ForEach(filteredRecent) { food in
                        HStack {
                            Button {
                                amount = FoodUnit.defaultAmount(for: food)
                                selectedUnitIndex = 0
                                selectedFood = food
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).font(.subheadline)
                                    Text(food.macroSummary).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }.tint(.primary)
                            Spacer()
                            Button { quickAdd(food) } label: {
                                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                            }.buttonStyle(.plain).accessibilityLabel("Add \(food.name)")
                        }
                    }
                }
            }

            if !results.isEmpty {
                Section("Foods") {
                    ForEach(results) { food in
                        HStack {
                            Button {
                                amount = FoodUnit.defaultAmount(for: food)
                                selectedUnitIndex = 0
                                selectedFood = food
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).font(.subheadline)
                                    Text(food.macroSummary).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }.tint(.primary)
                            Spacer()
                            Button { quickAdd(food) } label: {
                                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                            }.buttonStyle(.plain).accessibilityLabel("Add \(food.name)")
                        }
                    }
                }
            }

            if !ingredientResults.isEmpty {
                Section("Raw Ingredients") {
                    ForEach(ingredientResults) { ing in
                        HStack {
                            Button {
                                let food = ingredientFood(ing)
                                amount = FoodUnit.defaultAmount(for: food)
                                selectedUnitIndex = 0
                                selectedFood = food
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ing.name).font(.subheadline)
                                    Text("\(Int(ing.caloriesPer100g)) cal/100g").font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }.tint(.primary)
                            Spacer()
                            Button { quickAdd(ingredientFood(ing)) } label: {
                                Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                            }.buttonStyle(.plain).accessibilityLabel("Add \(ing.name)")
                        }
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
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }

                // Shared serving input
                ServingInputView(amount: $amount, selectedUnitIndex: $selectedUnitIndex,
                                 units: units, servingSize: food.servingSize)

                // Nutrition preview
                VStack(spacing: 4) {
                    Text("\((food.calories * multiplier).safeInt) cal")
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text("\((food.proteinG * multiplier).safeInt)P \u{00B7} \((food.carbsG * multiplier).safeInt)C \u{00B7} \((food.fatG * multiplier).safeInt)F")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                }
                .padding(.vertical, 12)

                // Add button
                Button {
                    addSelectedIngredient()
                } label: {
                    Text(editingItem != nil ? "Save Changes" : "Add to meal").font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
    }

    private func formatPortion(amount: String, unitLabel: String) -> String {
        let num = Double(amount) ?? 0
        if num == Double(Int(num)) {
            return "\(Int(num)) \(unitLabel)"
        }
        return "\(amount) \(unitLabel)"
    }

    private var canAddSelected: Bool {
        selectedFood != nil && (Double(amount) ?? 0) > 0
    }


    private func makeItem(from food: Food, amount: String, unitIndex: Int) -> QuickAddView.RecipeItem {
        let units = FoodUnit.smartUnits(for: food)
        let safeIndex = min(unitIndex, max(units.count - 1, 0))
        let unit = units.isEmpty ? FoodUnit(label: "g", gramsEquivalent: 1) : units[safeIndex]
        let amountNum = Double(amount) ?? 0
        let totalGrams = amountNum * unit.gramsEquivalent
        let multiplier = food.servingSize > 0 ? totalGrams / food.servingSize : amountNum
        return QuickAddView.RecipeItem(
            name: food.name,
            portionText: formatPortion(amount: amount, unitLabel: unit.label),
            calories: food.calories * multiplier,
            proteinG: food.proteinG * multiplier,
            carbsG: food.carbsG * multiplier,
            fatG: food.fatG * multiplier,
            fiberG: food.fiberG * multiplier,
            servingSizeG: totalGrams
        )
    }

    /// #1019: commit an item and STAY OPEN — reset to the search list and refocus so the
    /// next ingredient is one tap away, instead of dismissing after every single add.
    /// Edit mode (a single item) still dismisses, preserving its behavior.
    private func commit(_ item: QuickAddView.RecipeItem) {
        onAdd(item)
        if editingItem != nil { dismiss(); return }
        addedCount += 1
        addedCal += item.calories
        selectedFood = nil
        query = ""
        results = []
        amount = "1"
        selectedUnitIndex = 0
        searchFocused = true
    }

    private func addSelectedIngredient() {
        guard let food = selectedFood else { return }
        commit(makeItem(from: food, amount: amount, unitIndex: selectedUnitIndex))
    }

    /// #1019: one-tap add at the food's default serving, skipping the serving picker.
    private func quickAdd(_ food: Food) {
        commit(makeItem(from: food, amount: FoodUnit.defaultAmount(for: food), unitIndex: 0))
    }

    private func ingredientFood(_ ing: RawIngredient) -> Food {
        let gpp = ing.gramsPerPiece
        let scale = gpp / 100.0
        return Food(name: ing.name, category: "Ingredient",
                    servingSize: gpp, servingUnit: "g",
                    calories: ing.caloriesPer100g * scale,
                    proteinG: ing.proteinPer100g * scale,
                    carbsG: ing.carbsPer100g * scale,
                    fatG: ing.fatPer100g * scale,
                    fiberG: ing.fiberPer100g * scale)
    }

    // MARK: - Manual Ingredient Sheet

    private var manualIngredientSheet: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $manualName)
                VStack(spacing: 8) {
                    HStack {
                        Text("Serving")
                        Spacer()
                        TextField("1", text: $manualServing)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 60)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(["serving", "g", "ml", "piece", "cup", "tbsp", "tsp", "scoop"], id: \.self) { u in
                                Button { manualServingUnit = u } label: {
                                    Text(u)
                                        .font(.caption.weight(manualServingUnit == u ? .semibold : .medium))
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(manualServingUnit == u ? Theme.ink : Theme.cardBackgroundElevated, in: Capsule())
                                        .foregroundStyle(manualServingUnit == u ? .white : .secondary)
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
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
                        let servingVal = Double(manualServing) ?? 1
                        let servingG: Double
                        switch manualServingUnit {
                        case "g": servingG = servingVal
                        case "ml": servingG = servingVal
                        case "cup": servingG = servingVal * 240
                        case "tbsp": servingG = servingVal * 15
                        case "tsp": servingG = servingVal * 5
                        case "scoop": servingG = servingVal * 30
                        default: servingG = servingVal > 0 ? servingVal : 0 // serving/piece — use as-is or 0
                        }
                        let portionText = servingVal > 0 && manualServingUnit != "serving"
                            ? "\(Int(servingVal)) \(manualServingUnit)" : ""
                        onAdd(QuickAddView.RecipeItem(
                            name: manualName.isEmpty ? "Item" : manualName,
                            portionText: portionText,
                            calories: Double(manualCal) ?? 0,
                            proteinG: Double(manualP) ?? 0,
                            carbsG: Double(manualC) ?? 0,
                            fatG: Double(manualF) ?? 0,
                            fiberG: Double(manualFb) ?? 0,
                            servingSizeG: servingG
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
