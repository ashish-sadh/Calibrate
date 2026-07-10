import SwiftUI
import DriftCore

struct FoodSearchView: View {
    @Bindable var viewModel: FoodLogViewModel
    var initialQuery: String = ""
    var initialServings: Double? = nil
    var initialMealType: MealType? = nil
    /// Exact food name the caller already resolved (Coach preview card) — the
    /// sheet pre-selects this row instead of its own top search hit, so the
    /// preview and the confirm sheet can't disagree (#930: "Egg" card opened
    /// a sheet pre-selected to "Egg Curry").
    var initialSelection: String? = nil
    var initialSelectionId: Int64? = nil  // #978: prefer id over name to disambiguate same-named rows
    /// When embedded in a host sheet that already supplies nav chrome
    /// (LogMealSheet's NavigationStack + Done), drop our own NavigationStack +
    /// toolbar so the user doesn't see two "Done" buttons (field bug 2026-05-29).
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFood: Food?
    @State private var amount = "1"
    @State private var selectedUnitIndex = 0
    @State private var query = ""
    @State private var results: [Food] = []
    @State private var matchingRecipes: [SavedFood] = []
    @State private var showingManual = false
    @State private var showingCombos = false
    @State private var logTime = Date()
    @State private var selectedMealType: MealType? = nil
    @State private var loggedCount = 0
    @State private var justLoggedText: String?   // #1025: transient "Added X" confirmation
    @State private var toastToken = 0
    @State private var showingRecipeBuilder = false
    @State private var showingScanner = false
    @State private var editingRecipe: SavedFood?
    @State private var rebuildingRecipe: SavedFood?
    @State private var isFoodFavorite = false
    @State private var comboToLog: Food? = nil
    @State private var onlineResults: [Food] = []
    @State private var isSearchingOnline = false
    @State private var onlineSearchTask: Task<Void, Never>?
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var recentlyLoggedFoods: [Food] = []
    @State private var yourFoods: [Food] = []
    @FocusState private var searchFocused: Bool

    private var effectiveMealType: MealType { initialMealType ?? viewModel.autoMealType }
    private var logMealType: MealType { selectedMealType ?? effectiveMealType }

    var body: some View {
        if embedded {
            searchContent
                .overlay(alignment: .top) { loggedToast }
                .animation(.spring(duration: 0.3), value: justLoggedText)
        } else {
            NavigationStack {
                // Standalone mode (diary meal-section "+" / search icon):
                // surface the past-day target here — embedded mode gets the
                // badge from LogMealSheet's header (2026-07-09 field ask).
                searchContent
                    .pastDayLogBadge(for: viewModel)
                    .overlay(alignment: .top) { loggedToast }
                    .animation(.spring(duration: 0.3), value: justLoggedText)
                    .navigationTitle(loggedCount > 0 ? "Add Food (\(loggedCount) logged)" : "Add Food")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(loggedCount > 0 ? "Done" : "Cancel") { dismiss() }
                        }
                    }
            }
        }
    }

    /// #1025: every add-to-diary action fires a haptic + a transient toast, so a tap is
    /// always visibly acknowledged (previously silent → users double-logged), including in
    /// embedded mode where the "(N logged)" nav chrome is hidden.
    private func confirmLog(_ name: String, calories: Double) {
        loggedCount += 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        justLoggedText = "Added \(name) · \(Int(calories.rounded())) cal"
        toastToken += 1
        let mine = toastToken
        Task {
            try? await Task.sleep(for: .milliseconds(1500))
            if toastToken == mine { justLoggedText = nil }
        }
    }

    @ViewBuilder private var loggedToast: some View {
        if let text = justLoggedText {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                Text(text).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Theme.accent, in: Capsule())   // neutral confirmation — not a goal-aware good/bad signal
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var searchContent: some View {
        VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search food or recipe", text: $query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onChange(of: query) { _, q in
                            // Debounce + off-main (#946): each keystroke used to run
                            // Levenshtein over 5,460 foods + full-table LIKE scans
                            // synchronously on the main thread. Now cancel the
                            // in-flight search, wait for a typing pause, run the heavy
                            // local search OFF the main thread, and publish on main.
                            searchDebounceTask?.cancel()
                            onlineSearchTask?.cancel()
                            if q.isEmpty {
                                results = []; matchingRecipes = []; onlineResults = []
                                return
                            }
                            searchDebounceTask = Task {
                                try? await Task.sleep(for: .milliseconds(200))
                                guard !Task.isCancelled else { return }
                                let localResults = await Task.detached { () -> [Food] in
                                    var r = FoodService.searchFood(query: q)
                                    // Fuzzy fallback: if no results, try dropping last char
                                    if r.isEmpty && q.count >= 4 {
                                        r = FoodService.searchFood(query: String(q.dropLast()))
                                    }
                                    return r
                                }.value
                                guard !Task.isCancelled else { return }
                                results = localResults
                                matchingRecipes = FoodService.searchRecipes(query: q)
                                onlineResults = []
                                // Smart trigger: search online when local results are insufficient (opt-in only)
                                if Preferences.onlineFoodSearchEnabled && q.count >= 3 && results.count < 5 {
                                    onlineSearchTask = Task {
                                        try? await Task.sleep(for: .milliseconds(500))
                                        guard !Task.isCancelled else { return }
                                        await searchOnline(query: q)
                                    }
                                }
                            }
                        }
                    if !query.isEmpty {
                        Button { query = ""; results = []; matchingRecipes = [] } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding()
                // V7 light theme — .ultraThinMaterial rendered as a
                // washed-out blur on the light surface. Solid card +
                // hairline divider matches the rest of V7 chrome.
                .background(Theme.cardBackground)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.separator).frame(height: 0.5)
                }

                if query.isEmpty {
                    suggestionsView
                } else if results.isEmpty && matchingRecipes.isEmpty && onlineResults.isEmpty {
                    if isSearchingOnline {
                        VStack(spacing: 12) {
                            ProgressView().tint(.secondary)
                            Text("Searching online...").font(.caption).foregroundStyle(Theme.textTertiary)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        noResultsView
                    }
                } else {
                    searchResultsList
                }
            }
            .sheet(item: $selectedFood) { food in
                logFoodSheet(food).onDisappear { selectedMealType = nil }
            }
            .sheet(isPresented: $showingManual) {
                ManualFoodEntrySheet(viewModel: viewModel) { loggedCount += 1 }
            }
            .sheet(isPresented: $showingRecipeBuilder, onDismiss: { viewModel.loadSuggestions() }) {
                QuickAddView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingCombos, onDismiss: { viewModel.loadSuggestions() }) {
                CombosView(viewModel: viewModel)
            }
            .sheet(item: $comboToLog) { combo in
                ComboLogSheet(combo: combo, viewModel: viewModel) {
                    viewModel.loadSuggestions()
                    dismiss()
                }
            }
            .fullScreenCover(isPresented: $showingScanner, onDismiss: { viewModel.loadSuggestions() }) {
                BarcodeLookupView(viewModel: viewModel)
            }
            .sheet(item: $editingRecipe) { recipe in
                EditRecipeSheet(recipe: recipe) { viewModel.loadSuggestions(); refreshSearch() }
            }
            .sheet(item: $rebuildingRecipe) { recipe in
                QuickAddView(viewModel: viewModel,
                             initialItems: recipe.recipeItems ?? [],
                             initialName: recipe.name,
                             editingRecipeID: recipe.id,
                             initialExpandOnLog: recipe.expandOnLog)
            }
            .onAppear {
                viewModel.loadSuggestions()
                recentlyLoggedFoods = FoodService.recentFoods(limit: 8)
                // Frequency-then-recency blend for the personalized empty
                // state — the foods the user actually taps, one section, no
                // duplicates (operator 2026-07-10: "Popular" is wrong there).
                var seen = Set<String>()
                yourFoods = (FoodService.frequentFoods(limit: 8) + recentlyLoggedFoods)
                    .filter { seen.insert($0.name.lowercased()).inserted }
                    .prefix(8).map { $0 }
                if !initialQuery.isEmpty {
                    query = initialQuery
                    results = FoodService.searchFood(query: initialQuery)
                    // Auto-select the caller's already-resolved food when given
                    // (single source of truth, #930); else the top search hit.
                    // #978: prefer an exact food-id match (the card was built from THIS
                    // row); a name-only match can land on a different same-named row.
                    let resolved = initialSelectionId.flatMap { id in results.first(where: { $0.id == id }) }
                        ?? initialSelection.flatMap { sel in results.first(where: { $0.name == sel }) }
                    if let bestMatch = resolved ?? results.first {
                        if let servings = initialServings {
                            // Pre-fill with specified servings
                            let units = FoodUnit.smartUnits(for: bestMatch)
                            selectedUnitIndex = 0
                            let primaryUnit = units.first ?? FoodUnit(label: "g", gramsEquivalent: 1)
                            let totalG = bestMatch.servingSize * servings
                            let inPrimary = primaryUnit.gramsEquivalent > 0 ? totalG / primaryUnit.gramsEquivalent : servings
                            amount = inPrimary == Double(Int(inPrimary)) ? "\(Int(inPrimary))" : String(format: "%.1f", inPrimary)
                            isFoodFavorite = FoodService.isFavorite(name: bestMatch.name)
                            selectedFood = bestMatch
                        } else {
                            selectFood(bestMatch)
                        }
                        return // Don't focus search — sheet is already open
                    }
                }
                // #premium-polish: was a hardcoded 300ms dead gap before the
                // keyboard rose — the core search path felt sluggish on every
                // open. Defer one runloop tick instead (lets the sheet's
                // presentation transaction commit) so the keyboard comes up
                // with the sheet, not a third-second later.
                Task { @MainActor in searchFocused = true }
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

                    Button { showingCombos = true } label: {
                        Label("Combos", systemImage: "fork.knife").font(.caption)
                    }.buttonStyle(.bordered).tint(Theme.accent)

                    Button { showingRecipeBuilder = true } label: {
                        Label("Build", systemImage: "list.bullet.rectangle").font(.caption)
                    }.buttonStyle(.bordered).tint(Theme.accent)

                    Button { showingManual = true } label: {
                        Label("Manual", systemImage: "pencil").font(.caption)
                    }.buttonStyle(.bordered).tint(Theme.accent)
                }
                .padding(.horizontal, 16)

                // Recent foods — from actual logged entries, shown first for 1-tap re-logging.
                // Hidden when embedded in LogMealSheet: the sheet's Recent tab
                // already owns recents/combos/favorites/frequent — stacking
                // them again under Search made the tab a confusing wall
                // (operator field report 2026-07-09). Embedded Search = search
                // field + method chips + POPULAR browse fodder only.
                if !embedded, !recentlyLoggedFoods.isEmpty {
                    suggestionSection("RECENT") {
                        ForEach(recentlyLoggedFoods) { food in
                            foodSuggestionRow(food)
                        }
                    }
                }

                // Combos & recipes
                if !embedded, !viewModel.combos.isEmpty {
                    suggestionSection("COMBOS") {
                        ForEach(viewModel.combos) { combo in
                            let totalCal = combo.recipeItems?.reduce(0) { $0 + $1.calories } ?? combo.calories
                            let itemCount = combo.recipeItems?.count ?? 0
                            Button { comboToLog = combo } label: {
                                HStack {
                                    Image(systemName: "fork.knife").font(.caption).foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(combo.name).font(.subheadline.weight(.medium))
                                        Text(itemCount > 0 ? "\(itemCount) items · \(Int(totalCal)) cal" : "\(Int(totalCal)) cal")
                                            .font(.caption).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // User favorites (starred items)
                if !embedded, !viewModel.favoriteFoods.isEmpty {
                    suggestionSection("\u{2B50} FAVORITES") {
                        ForEach(viewModel.favoriteFoods) { entry in
                            recentEntryRow(entry)
                        }
                    }
                }

                // Frequent foods
                if !embedded, !viewModel.frequentFoods.isEmpty {
                    suggestionSection("FREQUENTLY USED") {
                        ForEach(viewModel.frequentFoods) { food in
                            foodSuggestionRow(food)
                        }
                    }
                }

                // Embedded (Log-a-meal Search tab): ONE personalized section —
                // the foods the user actually logs, frequency-then-recency.
                // Keeps the 2026-07-09 de-clutter rule (the Recent tab owns the
                // full recents/combos/favorites stack) while killing the junk
                // "Popular" default (operator field report 2026-07-10).
                if embedded, !yourFoods.isEmpty {
                    suggestionSection("YOUR FOODS") {
                        ForEach(yourFoods) { food in
                            foodSuggestionRow(food)
                        }
                    }
                }

                // Popular foods — cold-start browse fodder only. Hidden in the
                // embedded sheet once the user has any history of their own.
                if !embedded || yourFoods.isEmpty {
                    suggestionSection("POPULAR") {
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
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
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
                        Text(food.macroSummary).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text("\(Int(food.calories))").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Text("cal").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }.buttonStyle(.plain)

            Button {
                let lastUsed = viewModel.recentEntries.first(where: { $0.name == food.name })?.lastServings ?? 1
                viewModel.logFood(food, servings: lastUsed, mealType: effectiveMealType)
                viewModel.loadSuggestions()
                confirmLog(food.name, calories: food.calories * lastUsed)
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Log food")
            .buttonStyle(.plain).padding(.leading, 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .contextMenu {
            Button {
                FoodService.toggleFavorite(name: food.name, foodId: food.id)
                viewModel.loadSuggestions()
            } label: {
                let isFav = FoodService.isFavorite(name: food.name)
                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
            }
        }
    }

    private func recentEntryRow(_ entry: RecentEntry) -> some View {
        HStack {
            if entry.isDBFood {
                // DB food — tap opens log sheet with serving picker
                Button {
                    let foods = FoodService.searchFood(query: entry.name).prefix(5)
                    // Prefer exact match, fall back to first result
                    if let food = foods.first(where: { $0.name == entry.name }) ?? foods.first {
                        selectFood(food)
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name).font(.subheadline).lineLimit(1)
                            Text(entry.macroSummary).font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Text("\(Int(entry.calories))").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                        Text("cal").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }.buttonStyle(.plain)
            } else {
                // Recipe/manual — show with bookmark icon, tap quick-logs
                HStack {
                    Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(Theme.accent.opacity(0.7))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name).font(.subheadline).lineLimit(1)
                        Text(entry.macroSummary).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    Text("\(Int(entry.calories))").font(.caption.weight(.medium).monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Text("cal").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }

            Button {
                if entry.isDBFood, let food = FoodService.findByName(entry.name) {
                    viewModel.quickLogFood(food)
                } else {
                    viewModel.quickAdd(name: entry.name, calories: entry.calories,
                                       proteinG: entry.proteinG, carbsG: entry.carbsG,
                                       fatG: entry.fatG, fiberG: entry.fiberG,
                                       mealType: effectiveMealType)
                }
                viewModel.loadSuggestions()
                confirmLog(entry.name, calories: entry.calories)
            } label: {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
            }
            .accessibilityLabel("Log food")
            .buttonStyle(.plain).padding(.leading, 6)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .contextMenu {
            Button {
                FoodService.toggleFavorite(name: entry.name, foodId: entry.foodId)
                viewModel.loadSuggestions()
            } label: {
                let isFav = FoodService.isFavorite(name: entry.name)
                Label(isFav ? "Unfavorite" : "Favorite", systemImage: isFav ? "star.slash" : "star")
            }
        }
    }

    private func refreshSearch() {
        if !query.isEmpty {
            results = FoodService.searchFood(query: query)
            matchingRecipes = FoodService.searchRecipes(query: query)
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
        } else {
            amount = FoodUnit.defaultAmount(for: food)
        }

        isFoodFavorite = FoodService.isFavorite(name: food.name)
        selectedFood = food
    }

    // MARK: - No Results

    private var noResultsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(Theme.textTertiary)
            Text("No results for \"\(query)\"").font(.subheadline).foregroundStyle(Theme.textSecondary)
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
            // Food results. Recipes are excluded here — they surface in
            // "Your Recipes" above with the proper expand-on-log flow; the
            // flat row would log the combined blob as one item (search-first
            // fix 2026-07-09: everything reachable by typing, no tab switch).
            let plainResults = results.filter { !$0.isRecipe }
            if !plainResults.isEmpty {
                Section("Foods") {
                    ForEach(plainResults) { food in
                        Button { selectFood(food) } label: {
                            let primaryUnit = FoodUnit.smartUnits(for: food).first?.label ?? "serving"
                            let unitInfo = primaryUnit == "g" || primaryUnit == "ml"
                                ? "\(Int(food.servingSize))\(food.servingUnit)"
                                : "1 \(primaryUnit)"
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.name).font(.subheadline)
                                Text("\(food.macroSummary) \u{00B7} \(unitInfo)")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .tint(.primary)
                        .swipeActions(edge: .leading) {
                            Button {
                                FoodService.toggleFavorite(name: food.name, foodId: food.id)
                                viewModel.loadSuggestions()
                            } label: {
                                Label("Favorite", systemImage: "star")
                            }.tint(Theme.fatYellow)
                        }
                        .swipeActions(edge: .trailing) {
                            // Only allow deleting user-added foods (Scanned category)
                            if food.category == "Scanned", let fid = food.id {
                                Button(role: .destructive) {
                                    FoodService.deleteScannedFood(id: fid, name: food.name)
                                    viewModel.loadSuggestions()
                                    refreshSearch()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                }
            }

            // Matching recipes
            if !matchingRecipes.isEmpty {
                Section("Your Recipes") {
                    ForEach(matchingRecipes) { recipe in
                        Button {
                            FoodService.logRecipe(recipe, servings: 1, mealType: effectiveMealType,
                                                  viewModel: viewModel)
                            viewModel.loadSuggestions()
                            confirmLog(recipe.name, calories: recipe.calories)
                        } label: {
                            HStack {
                                Image(systemName: "bookmark.fill").font(.caption2).foregroundStyle(Theme.accent.opacity(0.7))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(recipe.name).font(.subheadline)
                                        // Group badge (#190): signals that logging this recipe
                                        // will expand into N individual food entries.
                                        if recipe.expandOnLog, let items = recipe.recipeItems, !items.isEmpty {
                                            Text("group · \(items.count)")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(Theme.accent)
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Theme.accent.opacity(0.15), in: Capsule())
                                        }
                                    }
                                    Text(recipe.macroSummary).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }.tint(.primary)
                        .swipeActions(edge: .trailing) {
                            if let id = recipe.id {
                                Button(role: .destructive) {
                                    FoodService.deleteFavorite(id: id)
                                    matchingRecipes.removeAll { $0.id == id }
                                    viewModel.loadSuggestions()
                                } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if recipe.recipeItems != nil {
                                Button { rebuildingRecipe = recipe } label: {
                                    Label("Edit", systemImage: "pencil")
                                }.tint(Theme.accent)
                            } else {
                                Button { editingRecipe = recipe } label: {
                                    Label("Edit", systemImage: "pencil")
                                }.tint(.orange)
                            }
                        }
                    }
                }
            }

            // Online results — deduplicated against local AND within themselves
            let localNames = Set(results.map { normalizeForDedup($0.name) })
            var seenOnline = Set<String>()
            let dedupedOnline = onlineResults.filter { food in
                let key = normalizeForDedup(food.name)
                guard !localNames.contains(key) else { return false }
                return seenOnline.insert(key).inserted
            }
            if !dedupedOnline.isEmpty {
                Section {
                    ForEach(dedupedOnline) { food in
                        Button { selectFood(food) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).font(.subheadline).lineLimit(1)
                                    Text(food.macroSummary).font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }.tint(.primary)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text("Online Results")
                        Image(systemName: "globe").font(.caption2)
                    }
                }
            }

            if isSearchingOnline && onlineResults.isEmpty && !results.isEmpty {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.7)
                        Text("Searching online...").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .listStyle(.plain)
        // Results scroll dismisses the keyboard — it trapped the list
        // behind the keyboard during user-testing (2026-07-09).
        .scrollDismissesKeyboard(.immediately)
    }

    // MARK: - Online Search

    @MainActor
    private func searchOnline(query: String) async {
        isSearchingOnline = true
        defer { isSearchingOnline = false }

        // Search OpenFoodFacts and USDA in parallel
        async let offProducts = (try? OpenFoodFactsService.search(query: query, limit: 8)) ?? []
        async let usdaItems = (try? USDAFoodService.search(query: query, limit: 5)) ?? []

        let products = await offProducts
        let usda = await usdaItems
        guard !Task.isCancelled else { return }

        var newFoods: [Food] = []

        // OpenFoodFacts results
        for p in products {
            let servingG = p.servingSizeG ?? 100
            let piece: Double? = {
                if let n = p.piecesPerServing, n > 0 { return servingG / Double(n) }
                return nil
            }()
            var food = Food(
                name: [p.name, p.brand].compactMap { $0 }.joined(separator: " - "),
                category: "Online",
                servingSize: servingG,
                servingUnit: "g",
                calories: p.calories * servingG / 100,
                proteinG: p.proteinG * servingG / 100,
                carbsG: p.carbsG * servingG / 100,
                fatG: p.fatG * servingG / 100,
                fiberG: p.fiberG * servingG / 100,
                pieceSizeG: piece
            )
            if let saved = FoodService.saveScannedFood(&food) {
                newFoods.append(saved)
            }
        }

        // USDA results
        for item in usda {
            var food = Food(
                name: item.name,
                category: "Online",
                servingSize: item.servingSizeG,
                servingUnit: "g",
                calories: item.calories,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG,
                fiberG: item.fiberG,
                pieceSizeG: item.pieceSizeG,
                cupSizeG: item.cupSizeG,
                tbspSizeG: item.tbspSizeG
            )
            if let saved = FoodService.saveScannedFood(&food) {
                newFoods.append(saved)
            }
        }

        guard !Task.isCancelled else { return }
        onlineResults = newFoods
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
                        let currentLabel = unit.label
                        let scale = (currentLabel == "g" || currentLabel == "ml" || food.servingSize <= 0) ? 1.0 : unit.gramsEquivalent / food.servingSize
                        let perText = (currentLabel == "g" || currentLabel == "ml")
                            ? "\(food.macroSummary) per \(Int(food.servingSize))\(food.servingUnit)"
                            : "\((food.calories * scale).safeInt)cal \((food.proteinG * scale).safeInt)P \((food.carbsG * scale).safeInt)C \((food.fatG * scale).safeInt)F per 1 \(currentLabel) (\(Int(unit.gramsEquivalent))g)"
                        Text(perText).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 8)

                    // Shared serving input (amount + units + quick buttons)
                    ServingInputView(amount: $amount, selectedUnitIndex: $selectedUnitIndex,
                                     units: units, servingSize: food.servingSize)

                    // Total nutrition
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\((food.calories * multiplier).safeInt)")
                                .font(.title.weight(.bold).monospacedDigit())
                            Text("cal").font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }

                        HStack(spacing: 8) {
                            macroChip("P", value: food.proteinG * multiplier, color: Theme.proteinRed)
                            macroChip("C", value: food.carbsG * multiplier, color: Theme.carbsGreen)
                            macroChip("F", value: food.fatG * multiplier, color: Theme.fatYellow)
                        }

                        if food.fiberG > 0 {
                            Text("\(MacroFormatter.fiber(food.fiberG * multiplier))g fiber")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .card()
                }
                .padding(.horizontal, 16)

                // Past-day target: this sheet covers every banner beneath it —
                // the warning must ride the surface itself (2026-07-09).
                if !viewModel.isToday {
                    PastDayLogBadge(date: viewModel.selectedDate)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }

                // Time picker
                DatePicker("Time", selection: $logTime, displayedComponents: .hourAndMinute)
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16).padding(.vertical, 8)

                // Meal type picker
                HStack {
                    Text("Meal").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Menu {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Button {
                                selectedMealType = type
                            } label: {
                                Label(type.displayName, systemImage: type.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: logMealType.icon)
                            Text(logMealType.displayName)
                        }
                        .font(.subheadline)
                        .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Log Food").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { selectedFood = nil } }
                ToolbarItem(placement: .principal) {
                    Button {
                        FoodService.toggleFavorite(name: food.name, foodId: food.id)
                        isFoodFavorite.toggle()
                    } label: {
                        Image(systemName: isFoodFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFoodFavorite ? Theme.fatYellow : .secondary)
                    }
                    .accessibilityLabel(isFoodFavorite ? "Remove from favorites" : "Add to favorites")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        viewModel.logFood(food, servings: multiplier, mealType: logMealType,
                                          loggedAt: viewModel.anchoredToSelectedDay(logTime))
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

    private func popularFoods() -> [Food] {
        let names = ["Egg", "Milk", "Bread", "Almonds", "Greek Yogurt",
                     "Banana", "Chicken", "Rice", "Oats", "Avocado"]
        var result: [Food] = []
        for name in names {
            // Canonical matches only: "Milk" may resolve to "Milk (2%)", but
            // fuzzy junk like "Bread Improver - Wallaby" for "Bread" must be
            // dropped, not shown as a starter (field report 2026-07-10).
            if let food = FoodService.findByName(name) {
                let f = food.name.lowercased(), n = name.lowercased()
                if f == n || f.hasPrefix(n + " (") || f.hasPrefix(n + ",") {
                    result.append(food)
                }
            }
        }
        return result
    }

}

// MARK: - Edit Recipe Sheet

private struct EditRecipeSheet: View {
    let recipe: SavedFood
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var fiber: String

    init(recipe: SavedFood, onSave: @escaping () -> Void) {
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
                            FoodService.updateFood(id: id, name: name,
                                                   calories: Double(calories) ?? 0, proteinG: Double(protein) ?? 0,
                                                   carbsG: Double(carbs) ?? 0, fatG: Double(fat) ?? 0,
                                                   fiberG: Double(fiber) ?? 0)
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
            Text(unit).font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 35)
        }
    }
}

extension FoodSearchView {
    func macroField(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(Theme.textSecondary).frame(width: 35)
        }
    }

    /// Normalize food name for deduplication: lowercase, strip brand suffix, strip parentheticals.
    func normalizeForDedup(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: "\\s*-\\s*[^-]+$", with: "", options: .regularExpression) // strip " - Brand"
            .replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression) // strip "(cooked)"
            .trimmingCharacters(in: .whitespaces)
    }
}
