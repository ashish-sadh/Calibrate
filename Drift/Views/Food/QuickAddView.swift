import SwiftUI

struct QuickAddView: View {
    @Bindable var viewModel: FoodLogViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: AddMode = .favorites

    enum AddMode: String, CaseIterable {
        case favorites = "Favorites"
        case new = "New"
        case manual = "Manual"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $mode) {
                    ForEach(AddMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

                switch mode {
                case .favorites: FavoritesTab(viewModel: viewModel, dismiss: dismiss)
                case .new: BuildMealTab(viewModel: viewModel, dismiss: dismiss)
                case .manual: ManualTab(viewModel: viewModel, dismiss: dismiss)
                }
            }
            .background(Theme.background)
            .navigationTitle("Quick Add").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

// MARK: - Favorites (one-tap log)

private struct FavoritesTab: View {
    @Bindable var viewModel: FoodLogViewModel
    let dismiss: DismissAction
    @State private var favorites: [FavoriteFood] = []
    @State private var mealType: MealType = .lunch
    @State private var showingAdd = false
    private let db = AppDatabase.shared

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mealType) {
                ForEach(MealType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }.pickerStyle(.segmented).padding(.horizontal, 12).padding(.vertical, 6)

            if favorites.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star").font(.system(size: 36)).foregroundStyle(Theme.accent.opacity(0.5))
                    Text("No favorites yet").font(.subheadline).foregroundStyle(.secondary)
                    Text("Save meals from the 'New' tab or add manually").font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                    Button { showingAdd = true } label: {
                        Label("Add Favorite", systemImage: "plus.circle")
                    }.buttonStyle(.bordered).padding(.top, 4)
                }.padding(.top, 30).padding(.horizontal, 20)
                Spacer()
            } else {
                List {
                    ForEach(favorites) { fav in
                        Button {
                            viewModel.quickAdd(name: fav.name, calories: fav.calories, proteinG: fav.proteinG,
                                               carbsG: fav.carbsG, fatG: fav.fatG, fiberG: fav.fiberG, mealType: mealType)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: fav.isRecipe ? "frying.pan.fill" : "star.fill")
                                    .font(.caption).foregroundStyle(fav.isRecipe ? Theme.stepsOrange : Theme.fatYellow)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fav.name).font(.subheadline)
                                    Text(fav.macroSummary).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                            }
                        }.tint(.primary)
                    }
                    .onDelete { indexSet in
                        for i in indexSet { if let id = favorites[i].id { try? db.deleteFavorite(id: id) } }
                        loadFavorites()
                    }
                }.listStyle(.plain)
            }
        }
        .onAppear { loadFavorites() }
        .sheet(isPresented: $showingAdd) { AddFavoriteSheet { loadFavorites() } }
    }

    private func loadFavorites() { favorites = (try? db.fetchFavorites()) ?? [] }
}

// MARK: - Build Meal (search + combine items → log or log+save)

private struct BuildMealTab: View {
    @Bindable var viewModel: FoodLogViewModel
    let dismiss: DismissAction
    @State private var mealName = ""
    @State private var items: [MealItem] = []
    @State private var mealType: MealType = .lunch
    @State private var showingSearch = false
    private let db = AppDatabase.shared

    struct MealItem: Identifiable {
        let id = UUID()
        var name: String
        var calories: Double
        var proteinG: Double
        var carbsG: Double
        var fatG: Double
        var fiberG: Double
    }

    var total: MealItem {
        MealItem(name: "", calories: items.reduce(0) { $0 + $1.calories },
                 proteinG: items.reduce(0) { $0 + $1.proteinG },
                 carbsG: items.reduce(0) { $0 + $1.carbsG },
                 fatG: items.reduce(0) { $0 + $1.fatG },
                 fiberG: items.reduce(0) { $0 + $1.fiberG })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                TextField("Meal name (optional)", text: $mealName)
                    .textFieldStyle(.roundedBorder).padding(.horizontal, 12)

                // Items
                ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.subheadline)
                            Text("\(Int(item.calories))cal \(Int(item.proteinG))P \(Int(item.carbsG))C \(Int(item.fatG))F")
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { items.remove(at: i) } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.tertiary)
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 14).padding(.vertical, 4)
                }

                // Add item button
                Button { showingSearch = true } label: {
                    Label("Add Item", systemImage: "plus.circle").frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).padding(.horizontal, 12)

                if !items.isEmpty {
                    // Total
                    VStack(spacing: 4) {
                        Text("\(Int(total.calories)) cal").font(.title3.weight(.bold).monospacedDigit())
                        HStack(spacing: 8) {
                            macroChip("P", value: total.proteinG, color: Theme.proteinRed)
                            macroChip("C", value: total.carbsG, color: Theme.carbsGreen)
                            macroChip("F", value: total.fatG, color: Theme.fatYellow)
                        }
                    }.card().padding(.horizontal, 12)

                    Picker("", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }.pickerStyle(.segmented).padding(.horizontal, 12)

                    // Action buttons
                    Button {
                        logMeal()
                        dismiss()
                    } label: {
                        Label("Log", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).tint(Theme.accent).padding(.horizontal, 12)

                    Button {
                        saveFavoriteAndLog()
                        dismiss()
                    } label: {
                        Label("Log + Save as Favorite", systemImage: "star.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).padding(.horizontal, 12)
                }
            }.padding(.top, 8).padding(.bottom, 24)
        }
        .sheet(isPresented: $showingSearch) {
            ItemSearchView { name, cal, p, c, f, fb in
                items.append(MealItem(name: name, calories: cal, proteinG: p, carbsG: c, fatG: f, fiberG: fb))
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

    private func logMeal() {
        let t = total
        viewModel.quickAdd(name: mealName.isEmpty ? (items.count == 1 ? items[0].name : "Meal") : mealName,
                           calories: t.calories, proteinG: t.proteinG, carbsG: t.carbsG, fatG: t.fatG, fiberG: t.fiberG,
                           mealType: mealType)
    }

    private func saveFavoriteAndLog() {
        let t = total
        let name = mealName.isEmpty ? (items.count == 1 ? items[0].name : "Meal") : mealName
        var fav = FavoriteFood(name: name, calories: t.calories, proteinG: t.proteinG, carbsG: t.carbsG,
                               fatG: t.fatG, fiberG: t.fiberG, isRecipe: items.count > 1)
        try? db.saveFavorite(&fav)
        viewModel.quickAdd(name: name, calories: t.calories, proteinG: t.proteinG, carbsG: t.carbsG,
                           fatG: t.fatG, fiberG: t.fiberG, mealType: mealType)
    }
}

// MARK: - Item Search (DB foods + raw ingredients + manual)

private struct ItemSearchView: View {
    let onAdd: (String, Double, Double, Double, Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var dbResults: [Food] = []
    @State private var showManual = false
    @State private var manualName = ""
    @State private var manualCal = ""
    @State private var manualP = ""
    @State private var manualC = ""
    @State private var manualF = ""
    @State private var manualFb = ""

    private var ingredientResults: [RawIngredient] {
        if query.isEmpty { return [] }
        return RawIngredient.allCases.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search food, ingredient, or enter manually", text: $query)
                        .textFieldStyle(.plain).autocorrectionDisabled()
                        .onChange(of: query) { _, _ in dbResults = (try? AppDatabase.shared.searchFoods(query: query)) ?? [] }
                }.padding().background(.ultraThinMaterial)

                List {
                    // Manual entry option at top
                    Button {
                        showManual = true
                    } label: {
                        Label("Enter calories manually", systemImage: "pencil")
                            .font(.subheadline).foregroundStyle(Theme.accent)
                    }

                    // DB results
                    if !dbResults.isEmpty {
                        Section("Foods") {
                            ForEach(dbResults) { food in
                                Button {
                                    onAdd(food.name, food.calories, food.proteinG, food.carbsG, food.fatG, food.fiberG)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(food.name).font(.subheadline)
                                        Text(food.macroSummary).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.tint(.primary)
                            }
                        }
                    }

                    // Ingredients
                    if !ingredientResults.isEmpty {
                        Section("Raw Ingredients (per 100g)") {
                            ForEach(ingredientResults) { ing in
                                Button {
                                    onAdd(ing.name, ing.caloriesPer100g, ing.proteinPer100g, ing.carbsPer100g, ing.fatPer100g, ing.fiberPer100g)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ing.name).font(.subheadline)
                                        Text("\(Int(ing.caloriesPer100g))cal \(Int(ing.proteinPer100g))P \(Int(ing.carbsPer100g))C \(Int(ing.fatPer100g))F /100g")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }.tint(.primary)
                            }
                        }
                    }
                }.listStyle(.plain)
            }
            .navigationTitle("Add Item").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showManual) {
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
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showManual = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                onAdd(manualName.isEmpty ? "Item" : manualName, Double(manualCal) ?? 0, Double(manualP) ?? 0,
                                      Double(manualC) ?? 0, Double(manualF) ?? 0, Double(manualFb) ?? 0)
                                showManual = false; dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Add Favorite Sheet

private struct AddFavoriteSheet: View {
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") { TextField("Name", text: $name) }
                Section("Per Serving") {
                    field("Calories", $calories, "kcal"); field("Protein", $protein, "g")
                    field("Carbs", $carbs, "g"); field("Fat", $fat, "g"); field("Fiber", $fiber, "g")
                }
            }
            .navigationTitle("Add Favorite").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var fav = FavoriteFood(name: name, calories: Double(calories) ?? 0, proteinG: Double(protein) ?? 0,
                                               carbsG: Double(carbs) ?? 0, fatG: Double(fat) ?? 0, fiberG: Double(fiber) ?? 0)
                        try? AppDatabase.shared.saveFavorite(&fav)
                        onSave(); dismiss()
                    }.disabled(name.isEmpty || calories.isEmpty)
                }
            }
        }
    }

    private func field(_ label: String, _ value: Binding<String>, _ unit: String) -> some View {
        HStack { Text(label); Spacer(); TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 35) }
    }
}

// MARK: - Manual Tab

private struct ManualTab: View {
    @Bindable var viewModel: FoodLogViewModel
    let dismiss: DismissAction
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var mealType: MealType = .lunch

    var body: some View {
        Form {
            Section("Food") { TextField("Name", text: $name) }
            Section("Macros") {
                field("Calories", $calories, "kcal"); field("Protein", $protein, "g")
                field("Carbs", $carbs, "g"); field("Fat", $fat, "g"); field("Fiber", $fiber, "g")
            }
            Section("Meal") {
                Picker("", selection: $mealType) { ForEach(MealType.allCases, id: \.self) { Text($0.displayName).tag($0) } }.pickerStyle(.segmented)
            }
            Section {
                Button {
                    viewModel.quickAdd(name: name.isEmpty ? "Quick Add" : name, calories: Double(calories) ?? 0,
                                       proteinG: Double(protein) ?? 0, carbsG: Double(carbs) ?? 0,
                                       fatG: Double(fat) ?? 0, fiberG: Double(fiber) ?? 0, mealType: mealType)
                    dismiss()
                } label: { Label("Log Food", systemImage: "plus.circle.fill").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(calories.isEmpty)
            }
        }
    }

    private func field(_ label: String, _ value: Binding<String>, _ unit: String) -> some View {
        HStack { Text(label); Spacer(); TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80); Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 35) }
    }
}
