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

                // Saved recipes
                if !viewModel.savedRecipes.isEmpty {
                    suggestionSection("RECIPES") {
                        ForEach(viewModel.savedRecipes) { recipe in
                            recipeSuggestionRow(recipe)
                        }
                    }
                }

                // Recent (includes recipes, manual entries, and DB foods)
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
                if viewModel.recentFoods.isEmpty && viewModel.frequentFoods.isEmpty && viewModel.savedRecipes.isEmpty && viewModel.favoriteFoods.isEmpty {
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

    private func recipeSuggestionRow(_ recipe: FavoriteFood) -> some View {
        HStack {
            Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(Theme.accent.opacity(0.7))
            VStack(alignment: .leading, spacing: 1) {
                Text(recipe.name).font(.subheadline).lineLimit(1)
                Text(recipe.macroSummary).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                viewModel.quickAdd(name: recipe.name, calories: recipe.calories,
                                   proteinG: recipe.proteinG, carbsG: recipe.carbsG,
                                   fatG: recipe.fatG, fiberG: recipe.fiberG,
                                   mealType: viewModel.autoMealType)
                viewModel.loadSuggestions()
                loggedCount += 1
                dismiss()
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .contextMenu {
            Button {
                viewModel.quickAdd(name: recipe.name, calories: recipe.calories,
                                   proteinG: recipe.proteinG, carbsG: recipe.carbsG,
                                   fatG: recipe.fatG, fiberG: recipe.fiberG,
                                   mealType: viewModel.autoMealType)
                viewModel.loadSuggestions()
                loggedCount += 1
            } label: { Label("Log", systemImage: "plus.circle") }

            if let id = recipe.id {
                Divider()
                Button(role: .destructive) {
                    try? AppDatabase.shared.deleteFavorite(id: id)
                    viewModel.loadSuggestions()
                } label: { Label("Delete Recipe", systemImage: "trash") }
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
        amount = "1"
        selectedUnitIndex = 0
        // Pre-select grams unit with food's serving size as default amount
        if units.first?.label == "g" && food.servingSize > 0 {
            amount = String(format: "%.0f", food.servingSize)
        }
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
            .background(Theme.background)
            .navigationTitle("Log Food").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selectedFood = nil } }
                ToolbarItem(placement: .principal) {
                    Button {
                        try? AppDatabase.shared.toggleFoodFavorite(name: food.name, foodId: food.id)
                    } label: {
                        let isFav = (try? AppDatabase.shared.isFoodFavorite(name: food.name)) ?? false
                        Image(systemName: isFav ? "star.fill" : "star")
                            .foregroundStyle(isFav ? Theme.fatYellow : .secondary)
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
        NavigationStack {
            Form {
                Section("Food") { TextField("Name", text: $manualName) }
                Section("Nutrition") {
                    macroField("Calories", value: $manualCal, unit: "kcal")
                    macroField("Protein", value: $manualP, unit: "g")
                    macroField("Carbs", value: $manualC, unit: "g")
                    macroField("Fat", value: $manualF, unit: "g")
                    macroField("Fiber", value: $manualFb, unit: "g")
                }
            }
            .navigationTitle("Manual Entry").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingManual = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        viewModel.quickAdd(name: manualName.isEmpty ? "Quick Add" : manualName,
                                           calories: Double(manualCal) ?? 0, proteinG: Double(manualP) ?? 0,
                                           carbsG: Double(manualC) ?? 0, fatG: Double(manualF) ?? 0,
                                           fiberG: Double(manualFb) ?? 0, mealType: viewModel.autoMealType)
                        viewModel.loadSuggestions()
                        loggedCount += 1
                        showingManual = false
                        manualName = ""; manualCal = ""; manualP = ""; manualC = ""; manualF = ""; manualFb = ""
                    }
                    .disabled(manualCal.isEmpty)
                }
            }
        }
    }

    private func popularFoods() -> [Food] {
        let names = ["Rice", "Egg", "Chicken", "Roti", "Dal", "Banana", "Milk", "Oats"]
        var result: [Food] = []
        for name in names {
            if let food = (try? AppDatabase.shared.searchFoods(query: name, limit: 1))?.first {
                result.append(food)
            }
        }
        return result
    }

    private func macroField(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 35)
        }
    }
}
