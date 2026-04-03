import SwiftUI

struct FoodSearchView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFood: Food?
    @State private var amount = "1"
    @State private var selectedUnitIndex = 0
    @State private var query = ""
    @State private var results: [Food] = []
    @State private var matchingRecipes: [FavoriteFood] = []
    @State private var showingManual = false
    @State private var manualName = ""
    @State private var manualCal = ""
    @State private var manualP = ""
    @State private var manualC = ""
    @State private var manualF = ""
    @State private var manualFb = ""
    @State private var loggedCount = 0
    @State private var showingRecipeBuilder = false
    @State private var showingScanner = false
    @State private var editingRecipe: FavoriteFood?
    @State private var isFoodFavorite = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search food or recipe", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .focused($searchFocused)
                        .onChange(of: query) { _, q in
                            results = q.isEmpty ? [] : ((try? AppDatabase.shared.searchFoodsRanked(query: q)) ?? [])
                            matchingRecipes = q.isEmpty ? [] : ((try? AppDatabase.shared.searchRecipes(query: q)) ?? [])
                        }
                    if !query.isEmpty {
                        Button { query = ""; results = []; matchingRecipes = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)

                if query.isEmpty {
                    suggestionsView
                } else if results.isEmpty && matchingRecipes.isEmpty {
                    noResultsView
                } else {
                    searchResultsList
                }
            }
            .navigationTitle(loggedCount > 0 ? "Add Food (\(loggedCount) logged)" : "Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $selectedFood) { food in logFoodSheet(food) }
            .sheet(isPresented: $showingManual) { manualEntrySheet }
            .sheet(isPresented: $showingRecipeBuilder) { QuickAddView(viewModel: viewModel) }
            .fullScreenCover(isPresented: $showingScanner) { BarcodeLookupView(viewModel: viewModel) }
            .onChange(of: showingRecipeBuilder) { _, showing in if !showing { viewModel.loadSuggestions() } }
            .onChange(of: showingScanner) { _, showing in if !showing { viewModel.loadSuggestions() } }
            .sheet(item: $editingRecipe) { recipe in
                EditRecipeSheet(recipe: recipe) { viewModel.loadSuggestions(); refreshSearch() }
            }
            .onAppear {
                viewModel.loadSuggestions()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { searchFocused = true }
            }
        }
    }

    // MARK: - Suggestions (empty search)

    private var suggestionsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Quick actions
                HStack(spacing: 8) {
                    Button { showingScanner = true } label: {
                        Label("Scan", systemImage: "barcode.viewfinder").font(.caption)
                    }.buttonStyle(.bordered).tint(Theme.accent)

                    Button { showingRecipeBuilder = true } label: {
                        Label("Recipe", systemImage: "fork.knife").font(.caption)
                    }.buttonStyle(.bordered).tint(Theme.accent)

                    Button { showingManual = true } label: {
                        Label("Manual", systemImage: "pencil").font(.caption)
                    }.buttonStyle(.bordered).tint(Theme.accent)
                }
                .padding(.horizontal, 16)

                // User favorites (starred items)
                if !viewModel.favoriteFoods.isEmpty {
                    suggestionSection("\u{2B50} FAVORITES") {
                        ForEach(viewModel.favoriteFoods) { entry in
                            recentEntryRow(entry)
                        }
                    }
                }

                // Recent — everything you've logged (foods + recipes)
                if !viewModel.recentEntries.isEmpty {
                    suggestionSection("RECENT") {
                        ForEach(viewModel.recentEntries) { entry in
                            recentEntryRow(entry)
                        }
                    }
                }

                // Frequent foods
                if !viewModel.frequentFoods.isEmpty {
                    suggestionSection("FREQUENTLY USED") {
                        ForEach(viewModel.frequentFoods) { food in
                            foodSuggestionRow(food)
                        }
                    }
                }

                // First-time empty state
                if viewModel.recentEntries.isEmpty && viewModel.frequentFoods.isEmpty && viewModel.favoriteFoods.isEmpty {
                    suggestionSection("POPULAR FOODS") {
                        let starters = popularFoods()
                        ForEach(starters) { food in
                            foodSuggestionRow(food)
                        }
                    }
                }
            }
            .padding(.top, 12)
        }
        .background(Theme.background)
    }

    private func suggestionSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            content()
        }
    }

    private func foodSuggestionRow(_ food: Food) -> some View {
        HStack {
            Button { selectFood(food) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(food.name).font(.subheadline).lineLimit(1)
                        Text(food.macroSummary).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(food.calories))").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                    Text("cal").font(.caption2).foregroundStyle(.tertiary)
                }
            }.buttonStyle(.plain)

            Button {
                viewModel.quickLogFood(food)
                viewModel.loadSuggestions()
                loggedCount += 1
                dismiss()
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
            }.buttonStyle(.plain).padding(.leading, 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .contextMenu {
            Button {
                try? AppDatabase.shared.toggleFoodFavorite(name: food.name, foodId: food.id)
                viewModel.loadSuggestions()
            } label: {
                let isFav = (try? AppDatabase.shared.isFoodFavorite(name: food.name)) ?? false
                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
            }
        }
    }

    private func recentEntryRow(_ entry: RecentEntry) -> some View {
        HStack {
            if entry.isDBFood {
                // DB food — tap opens log sheet with serving picker
                Button {
                    let foods = (try? AppDatabase.shared.searchFoods(query: entry.name, limit: 5)) ?? []
                    // Prefer exact match, fall back to first result
                    if let food = foods.first(where: { $0.name == entry.name }) ?? foods.first {
                        selectFood(food)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).font(.subheadline).lineLimit(1)
                            Text(entry.macroSummary).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(entry.calories))").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                        Text("cal").font(.caption2).foregroundStyle(.tertiary)
                    }
                }.buttonStyle(.plain)
            } else {
                // Recipe/manual — show with bookmark icon, tap quick-logs
                HStack {
                    Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(Theme.accent.opacity(0.7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).font(.subheadline).lineLimit(1)
                        Text(entry.macroSummary).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(entry.calories))").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(.secondary)
                    Text("cal").font(.caption2).foregroundStyle(.tertiary)
                }
            }

            Button {
                if entry.isDBFood, let food = (try? AppDatabase.shared.searchFoods(query: entry.name, limit: 1))?.first {
                    viewModel.quickLogFood(food)
                } else {
                    viewModel.quickAdd(name: entry.name, calories: entry.calories,
                                       proteinG: entry.proteinG, carbsG: entry.carbsG,
                                       fatG: entry.fatG, fiberG: 0,
                                       mealType: viewModel.autoMealType)
                }
                viewModel.loadSuggestions()
                loggedCount += 1
                dismiss()
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
            }.buttonStyle(.plain).padding(.leading, 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .contextMenu {
            Button {
                try? AppDatabase.shared.toggleFoodFavorite(name: entry.name, foodId: entry.foodId)
                viewModel.loadSuggestions()
            } label: {
                let isFav = (try? AppDatabase.shared.isFoodFavorite(name: entry.name)) ?? false
                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
            }
        }
    }

    private func refreshSearch() {
        if !query.isEmpty {
            results = (try? AppDatabase.shared.searchFoodsRanked(query: query)) ?? []
            matchingRecipes = (try? AppDatabase.shared.searchRecipes(query: query)) ?? []
        }
    }

    private func selectFood(_ food: Food) {
        let units = FoodUnit.smartUnits(for: food)
        selectedUnitIndex = 0

        // Smart default: use last-used serving size if available
        let lastUsed = viewModel.recentEntries.first(where: { $0.name == food.name })?.lastServings
        if let last = lastUsed, last > 0 {
            // Convert last servings (which is a multiplier) to the primary unit amount
            let primaryUnit = units.first ?? FoodUnit(label: "g", gramsEquivalent: 1)
            let totalG = food.servingSize * last
            let inPrimary = primaryUnit.gramsEquivalent > 0 ? totalG / primaryUnit.gramsEquivalent : last
            amount = inPrimary == Double(Int(inPrimary)) ? "\(Int(inPrimary))" : String(format: "%.1f", inPrimary)
        } else if units.first?.label == "g" && food.servingSize > 0 {
            amount = String(format: "%.0f", food.servingSize)
        } else {
            amount = "1"
        }

        isFoodFavorite = (try? AppDatabase.shared.isFoodFavorite(name: food.name)) ?? false
        selectedFood = food
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.tertiary)
            Text("No results for \"\(query)\"").font(.subheadline).foregroundStyle(.secondary)
            Button { showingManual = true } label: {
                Label("Enter manually", systemImage: "pencil").font(.subheadline)
            }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Search Results

    private var searchResultsList: some View {
        List {
            // Matching recipes
            if !matchingRecipes.isEmpty {
                Section("Your Recipes") {
                    ForEach(matchingRecipes) { recipe in
                        Button {
                            viewModel.quickAdd(name: recipe.name, calories: recipe.calories,
                                               proteinG: recipe.proteinG, carbsG: recipe.carbsG,
                                               fatG: recipe.fatG, fiberG: recipe.fiberG,
                                               mealType: viewModel.autoMealType)
                            viewModel.loadSuggestions()
                            loggedCount += 1
                        } label: {
                            HStack {
                                Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(Theme.accent.opacity(0.7))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recipe.name).font(.subheadline)
                                    Text(recipe.macroSummary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }.tint(.primary)
                        .swipeActions(edge: .trailing) {
                            if let id = recipe.id {
                                Button(role: .destructive) {
                                    try? AppDatabase.shared.deleteFavorite(id: id)
                                    matchingRecipes.removeAll { $0.id == id }
                                    viewModel.loadSuggestions()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }

            // Food results
            if !results.isEmpty {
                Section("Foods") {
                    ForEach(results) { food in
                        Button { selectFood(food) } label: {
                            let primaryUnit = FoodUnit.smartUnits(for: food).first?.label ?? "serving"
                            let unitInfo = primaryUnit == "g" || primaryUnit == "ml"
                                ? "\(Int(food.servingSize))\(food.servingUnit)"
                                : "1 \(primaryUnit)"
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name).font(.subheadline)
                                Text("\(food.macroSummary) \u{00B7} \(unitInfo)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tint(.primary)
                        .swipeActions(edge: .leading) {
                            Button {
                                try? AppDatabase.shared.toggleFoodFavorite(name: food.name, foodId: food.id)
                                viewModel.loadSuggestions()
                            } label: {
                                Label("Favorite", systemImage: "star")
                            }.tint(Theme.fatYellow)
                        }
                        .swipeActions(edge: .trailing) {
                            // Only allow deleting user-added foods (Scanned category)
                            if food.category == "Scanned", let fid = food.id {
                                Button(role: .destructive) {
                                    try? AppDatabase.shared.writer.write { db in
                                        _ = try Food.deleteOne(db, id: fid)
                                        // Clean up food_usage reference
                                        try db.execute(sql: "DELETE FROM food_usage WHERE food_name = ?", arguments: [food.name])
                                    }
                                    viewModel.loadSuggestions()
                                    refreshSearch()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Log Food Sheet

    private func logFoodSheet(_ food: Food) -> some View {
        let units = FoodUnit.smartUnits(for: food)
        let safeIndex = min(selectedUnitIndex, max(units.count - 1, 0))
        let unit = units.isEmpty ? FoodUnit(label: "g", gramsEquivalent: 1) : units[safeIndex]
        let amountNum = Double(amount) ?? 0
        let totalGrams = amountNum * unit.gramsEquivalent
        let multiplier = food.servingSize > 0 ? totalGrams / food.servingSize : amountNum

        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Food header
                    VStack(spacing: 4) {
                        Text(food.name).font(.title3.weight(.semibold))
                        let primaryLabel = units.first?.label ?? "serving"
                        let perText = primaryLabel == "g" || primaryLabel == "ml"
                            ? "\(food.macroSummary) per \(Int(food.servingSize))\(food.servingUnit)"
                            : "\(food.macroSummary) per 1 \(primaryLabel) (\(Int(food.servingSize))g)"
                        Text(perText).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    // Amount + unit picker (no "Unit" label)
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
                            // Auto-convert amount when switching units
                            guard oldIdx < units.count, newIdx < units.count else { return }
                            let oldUnit = units[oldIdx]
                            let newUnit = units[newIdx]
                            let currentAmount = Double(amount) ?? 0
                            let grams = currentAmount * oldUnit.gramsEquivalent
                            let converted = newUnit.gramsEquivalent > 0 ? grams / newUnit.gramsEquivalent : currentAmount
                            if converted == Double(Int(converted)) {
                                amount = "\(Int(converted))"
                            } else {
                                amount = String(format: "%.1f", converted)
                            }
                        }
                    }

                    // Quick amount buttons
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

                    // Total nutrition
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(food.calories * multiplier))")
                                .font(.title.weight(.bold).monospacedDigit())
                            Text("cal").font(.subheadline).foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            macroChip("P", value: food.proteinG * multiplier, color: Theme.proteinRed)
                            macroChip("C", value: food.carbsG * multiplier, color: Theme.carbsGreen)
                            macroChip("F", value: food.fatG * multiplier, color: Theme.fatYellow)
                        }

                        if food.fiberG > 0 {
                            Text("\(Int(food.fiberG * multiplier))g fiber")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .card()
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Log Food").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selectedFood = nil } }
                ToolbarItem(placement: .principal) {
                    Button {
                        try? AppDatabase.shared.toggleFoodFavorite(name: food.name, foodId: food.id)
                        isFoodFavorite.toggle()
                    } label: {
                        Image(systemName: isFoodFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFoodFavorite ? Theme.fatYellow : .secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        viewModel.logFood(food, servings: multiplier, mealType: viewModel.autoMealType)
                        viewModel.loadSuggestions()
                        refreshSearch()
                        loggedCount += 1
                        selectedFood = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.65), .large])
        .presentationBackground(Theme.background)
        .presentationCornerRadius(20)
    }

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))g \(label)").font(.caption2.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Manual Entry Sheet

    private var manualEntrySheet: some View {
        let p = Double(manualP) ?? 0, c = Double(manualC) ?? 0, f = Double(manualF) ?? 0
        let macroCalories = Int(p * 4 + c * 4 + f * 9)
        let enteredCal = Int(Double(manualCal) ?? 0)

        return NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Name
                    TextField("Food name (optional)", text: $manualName)
                        .font(.body)
                        .padding(12)
                        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))

                    // Calories — hero
                    VStack(spacing: 4) {
                        Text("Calories").font(.caption2).foregroundStyle(.tertiary)
                        TextField("0", text: $manualCal)
                            .keyboardType(.numberPad)
                            .font(.system(size: 44, weight: .bold).monospacedDigit())
                            .multilineTextAlignment(.center)
                        Text("kcal").font(.caption).foregroundStyle(.secondary)
                        if macroCalories > 0 && !manualCal.isEmpty && macroCalories != enteredCal {
                            Text("Macros sum to \(macroCalories) kcal")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)

                    // Macros — inline row
                    HStack(spacing: 10) {
                        manualMacroField("Protein", value: $manualP, unit: "g", color: Theme.proteinRed)
                        manualMacroField("Carbs", value: $manualC, unit: "g", color: Theme.carbsGreen)
                        manualMacroField("Fat", value: $manualF, unit: "g", color: Theme.fatYellow)
                    }

                    // Fiber — optional, smaller
                    HStack {
                        Text("Fiber").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        TextField("0", text: $manualFb)
                            .keyboardType(.decimalPad)
                            .font(.subheadline.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("g").font(.caption).foregroundStyle(.tertiary)
                    }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingManual = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let cal = Double(manualCal) ?? (macroCalories > 0 ? Double(macroCalories) : 0)
                        viewModel.quickAdd(name: manualName.isEmpty ? "Quick Add" : manualName,
                                           calories: cal, proteinG: p, carbsG: c, fatG: f,
                                           fiberG: Double(manualFb) ?? 0, mealType: viewModel.autoMealType)
                        viewModel.loadSuggestions()
                        loggedCount += 1
                        showingManual = false
                        manualName = ""; manualCal = ""; manualP = ""; manualC = ""; manualF = ""; manualFb = ""
                    }
                    .disabled((Double(manualCal) ?? 0) == 0 && macroCalories == 0)
                }
            }
        }
    }

    private func manualMacroField(_ label: String, value: Binding<String>, unit: String, color: Color) -> some View {
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
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.25), lineWidth: 1))
    }

    private func popularFoods() -> [Food] {
        let names = ["Egg", "Milk", "Bread", "Almonds", "Greek Yogurt",
                     "Banana", "Chicken", "Rice", "Oats", "Avocado"]
        var result: [Food] = []
        for name in names {
            if let food = (try? AppDatabase.shared.searchFoods(query: name, limit: 1))?.first {
                result.append(food)
            }
        }
        return result
    }

}

// MARK: - Edit Recipe Sheet

private struct EditRecipeSheet: View {
    let recipe: FavoriteFood
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber: String

    init(recipe: FavoriteFood, onSave: @escaping () -> Void) {
        self.recipe = recipe; self.onSave = onSave
        _name = State(initialValue: recipe.name)
        _calories = State(initialValue: "\(Int(recipe.calories))")
        _protein = State(initialValue: "\(Int(recipe.proteinG))")
        _carbs = State(initialValue: "\(Int(recipe.carbsG))")
        _fat = State(initialValue: "\(Int(recipe.fatG))")
        _fiber = State(initialValue: "\(Int(recipe.fiberG))")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Recipe name", text: $name) }
                Section("Nutrition (per serving)") {
                    field("Calories", $calories, "kcal")
                    field("Protein", $protein, "g")
                    field("Carbs", $carbs, "g")
                    field("Fat", $fat, "g")
                    field("Fiber", $fiber, "g")
                }
            }
            .navigationTitle("Edit Recipe").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let id = recipe.id {
                            try? AppDatabase.shared.writer.write { db in
                                try db.execute(sql: """
                                    UPDATE favorite_food SET name = ?, calories = ?, protein_g = ?,
                                    carbs_g = ?, fat_g = ?, fiber_g = ? WHERE id = ?
                                    """, arguments: [name, Double(calories) ?? 0, Double(protein) ?? 0,
                                                     Double(carbs) ?? 0, Double(fat) ?? 0, Double(fiber) ?? 0, id])
                            }
                        }
                        onSave(); dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }

    private func field(_ label: String, _ value: Binding<String>, _ unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 35)
        }
    }
}

extension FoodSearchView {
    func macroField(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 35)
        }
    }
}
