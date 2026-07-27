import SwiftUI
import DriftCore

// Single-source (SharedUI): the Food diary's edit sheet for BOTH apps
// (#1059/#1062 port). Recipe editing (QuickAddView) stays iOS-only behind
// DRIFT_IOS_APP; Android renders the same ingredient list read-only until
// that sheet ports.
struct EditFoodEntrySheet: View {
    let entry: FoodEntry
    @Bindable var viewModel: FoodLogViewModel
    let onCopiedToToday: (String) -> Void
    let onDone: () -> Void
    @Environment(\.dismiss) var dismiss
    @State var editAmount: String
    @State var editUnitIndex = 0
    @State var editEntryIsFav: Bool
    @State var editEntryTime: Date
    @State var editCal: String
    @State var editP: String
    @State var editC: String
    @State var editF: String
    @State var editFb: String
    @State var editName: String
    @State var editMealType: MealType
    @State var overrideMacros = false
    @State var showingRecipeEditor = false
    #if os(Android)
    // FoodService.fetchFoodById/findByName inside a ViewBuilder is a
    // JNI+SQLite hit per recomposition on Fuse — hoisted once per entry.
    // iOS keeps the original inline reads (0-IOS-GUARD).
    @State var androidDbFood: Food? = nil
    #endif

    init(entry: FoodEntry, viewModel: FoodLogViewModel, onCopiedToToday: @escaping (String) -> Void, onDone: @escaping () -> Void) {
        self.entry = entry
        self.viewModel = viewModel
        self.onCopiedToToday = onCopiedToToday
        self.onDone = onDone

        // Initialize serving amount
        if entry.servingSizeG > 0 {
            let food = Food(name: entry.foodName, category: "", servingSize: entry.servingSizeG,
                            servingUnit: "g", calories: entry.calories)
            let units = FoodUnit.smartUnits(for: food)
            let primary = units.first ?? FoodUnit(label: "serving", gramsEquivalent: entry.servingSizeG)
            let totalG = entry.servingSizeG * entry.servings
            let amountInPrimary = primary.gramsEquivalent > 0 ? totalG / primary.gramsEquivalent : entry.servings
            _editAmount = State(initialValue: amountInPrimary == Double(Int(amountInPrimary))
                ? "\(Int(amountInPrimary))" : String(format: "%.1f", amountInPrimary))
        } else {
            _editAmount = State(initialValue: entry.servings == Double(Int(entry.servings))
                ? "\(Int(entry.servings))" : String(format: "%.1f", entry.servings))
        }
        _editEntryIsFav = State(initialValue: FoodService.isFavorite(name: entry.foodName))
        _editEntryTime = State(initialValue: DateFormatters.iso8601.date(from: entry.loggedAt ?? "") ?? Date())
        _editCal = State(initialValue: "\(Int(entry.calories))")
        _editP = State(initialValue: "\(Int(entry.proteinG))")
        _editC = State(initialValue: "\(Int(entry.carbsG))")
        _editF = State(initialValue: "\(Int(entry.fatG))")
        _editFb = State(initialValue: "\(Int(entry.fiberG))")
        _editName = State(initialValue: entry.foodName)
        _editMealType = State(initialValue: MealType(rawValue: entry.mealType ?? "") ?? .snack)
    }

    private var hasServingSize: Bool { entry.servingSizeG > 0 }

    private var food: Food? {
        hasServingSize
            ? Food(name: entry.foodName, category: "", servingSize: entry.servingSizeG,
                   servingUnit: "g", calories: entry.calories,
                   proteinG: entry.proteinG, carbsG: entry.carbsG,
                   fatG: entry.fatG, fiberG: entry.fiberG)
            : nil
    }

    private var units: [FoodUnit] { food.map { FoodUnit.smartUnits(for: $0) } ?? [] }

    #if DRIFT_IOS_APP
    /// The Food record backing this entry, only when it has editable recipe items.
    private var recipeFood: Food? {
        let food = entry.foodId.flatMap { FoodService.fetchFoodById($0) }
            ?? FoodService.findByName(entry.foodName)
        return food?.recipeItems != nil ? food : nil
    }
    #endif

    private var multiplier: Double {
        let safeIndex = min(editUnitIndex, max(units.count - 1, 0))
        let unit = units.isEmpty ? FoodUnit(label: "serving", gramsEquivalent: max(entry.servingSizeG, 1)) : units[safeIndex]
        let amountNum = Double(editAmount) ?? 0
        return hasServingSize
            ? (entry.servingSizeG > 0 ? (amountNum * unit.gramsEquivalent) / entry.servingSizeG : amountNum)
            : amountNum
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                #if os(Android)
                // SkipUI's nav bar inside a sheet reserves an ~80dp dead band
                // above the title (#1089) — draw the header as content and
                // leave the nav bar off on Android.
                ZStack {
                    HStack(spacing: 6) {
                        Text("Edit").font(.headline)
                        Button {
                            FoodService.toggleFavorite(name: entry.foodName, foodId: entry.foodId)
                            editEntryIsFav.toggle()
                        } label: {
                            Image(systemName: sym(editEntryIsFav ? "star.fill" : "star"))
                                .foregroundStyle(editEntryIsFav ? Theme.fatYellow : .secondary)
                        }
                        .accessibilityLabel(editEntryIsFav ? "Remove from favorites" : "Add to favorites")
                    }
                    HStack {
                        Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                        Spacer()
                        Button("Save") { save() }.fontWeight(.semibold).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                #endif
                editForm
            }
            #if !os(Android)
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Button {
                        FoodService.toggleFavorite(name: entry.foodName, foodId: entry.foodId)
                        editEntryIsFav.toggle()
                    } label: {
                        Image(systemName: sym(editEntryIsFav ? "star.fill" : "star"))
                            .foregroundStyle(editEntryIsFav ? Theme.fatYellow : .secondary)
                    }
                    .accessibilityLabel(editEntryIsFav ? "Remove from favorites" : "Add to favorites")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            #endif
        }
        .presentationDetents([.fraction(0.85), .large])
        #if DRIFT_IOS_APP
        .sheet(isPresented: $showingRecipeEditor, onDismiss: { onDone() }) {
            if let rf = recipeFood {
                QuickAddView(viewModel: viewModel,
                             initialItems: rf.recipeItems ?? [],
                             initialName: rf.name,
                             editingRecipeID: rf.id,
                             initialExpandOnLog: rf.expandOnLog)
            }
        }
        #endif
    }

    private var editForm: some View {
        ScrollView {
            VStack(spacing: 20) {
                    VStack(spacing: 4) {
                        if entry.foodId == nil {
                            TextField("Food name", text: $editName)
                                .font(.title3.weight(.semibold))
                                .multilineTextAlignment(.center)
                        } else {
                            Text(entry.foodName).font(.title3.weight(.semibold))
                        }
                        if hasServingSize {
                            let safeIdx = min(editUnitIndex, max(units.count - 1, 0))
                            let currentUnit = units.isEmpty ? FoodUnit(label: "serving", gramsEquivalent: max(entry.servingSizeG, 1)) : units[safeIdx]
                            let currentLabel = currentUnit.label
                            let scale = (currentLabel == "g" || currentLabel == "ml" || entry.servingSizeG <= 0) ? 1.0 : currentUnit.gramsEquivalent / entry.servingSizeG
                            let perText = (currentLabel == "g" || currentLabel == "ml")
                                ? "\(Int(entry.calories))cal per \(Int(entry.servingSizeG))g"
                                : "\(Int(entry.calories * scale))cal \(Int(entry.proteinG * scale))P \(Int(entry.carbsG * scale))C \(Int(entry.fatG * scale))F per 1 \(currentLabel) (\(Int(currentUnit.gramsEquivalent))g)"
                            Text(perText).font(.caption).foregroundStyle(Theme.textSecondary)
                        } else {
                            Text("\(Int(entry.calories))cal per serving")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.top, 8)

                    // Compact time picker
                    HStack {
                        #if os(Android)
                        ClockFaceShape().fill(Theme.textTertiary).frame(width: 13, height: 13)
                        #else
                        Image(systemName: "clock").font(.caption).foregroundStyle(Theme.textTertiary)
                        #endif
                        DatePicker("", selection: $editEntryTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }

                    // Meal-type picker
                    HStack(spacing: 6) {
                        ForEach(MealType.allCases, id: \.self) { meal in
                            Button {
                                editMealType = meal
                            } label: {
                                HStack(spacing: 4) {
                                    #if os(Android)
                                    MealGlyph(meal: meal,
                                              color: editMealType == meal ? .white : Theme.textSecondary,
                                              size: 12)
                                    #else
                                    Image(systemName: meal.icon).font(.caption2)
                                    #endif
                                    Text(meal.displayName).font(.caption.weight(.medium))
                                }
                                .foregroundStyle(editMealType == meal ? .white : .secondary)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(editMealType == meal ? Theme.ink : Theme.cardBackgroundElevated,
                                            in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Set meal to \(meal.displayName)")
                        }
                    }

                    // Serving input for DB foods
                    if entry.foodId != nil && !units.isEmpty {
                        ServingInputView(amount: $editAmount, selectedUnitIndex: $editUnitIndex,
                                         units: units, servingSize: entry.servingSizeG)
                    }

                    if entry.foodId == nil {
                        // Quick-add — serving amount (descriptive, macros are the total)
                        VStack(spacing: 8) {
                            HStack {
                                Text("Servings").font(.caption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                NumericField("1", text: $editAmount)
                                    .font(.subheadline.monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 50)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusChip))

                        // Editable total macros
                        VStack(spacing: 8) {
                            CalorieField(text: $editCal)
                            HStack(spacing: 12) {
                                EditableMacroField(label: "P", text: $editP, color: Theme.proteinRed)
                                EditableMacroField(label: "C", text: $editC, color: Theme.carbsGreen)
                                EditableMacroField(label: "F", text: $editF, color: Theme.fatYellow)
                                EditableMacroField(label: "Fb", text: $editFb, color: Theme.fiberBrown)
                            }
                        }
                        .card()
                    } else {
                        // DB food — macros computed from servings, with manual override option
                        VStack(spacing: 8) {
                            if overrideMacros {
                                CalorieField(text: $editCal)
                                HStack(spacing: 12) {
                                    EditableMacroField(label: "P", text: $editP, color: Theme.proteinRed)
                                    EditableMacroField(label: "C", text: $editC, color: Theme.carbsGreen)
                                    EditableMacroField(label: "F", text: $editF, color: Theme.fatYellow)
                                    EditableMacroField(label: "Fb", text: $editFb, color: Theme.fiberBrown)
                                }
                            } else {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\((entry.calories * multiplier).safeInt)")
                                        .font(.title.weight(.bold).monospacedDigit())
                                    Text("cal").font(.subheadline).foregroundStyle(Theme.textSecondary)
                                }
                                HStack(spacing: 8) {
                                    macroChip("P", value: entry.proteinG * multiplier, color: Theme.proteinRed)
                                    macroChip("C", value: entry.carbsG * multiplier, color: Theme.carbsGreen)
                                    macroChip("F", value: entry.fatG * multiplier, color: Theme.fatYellow)
                                    if entry.fiberG > 0 {
                                        macroChip("Fb", value: entry.fiberG * multiplier, color: Theme.fiberBrown)
                                    }
                                }
                            }

                            Button {
                                if !overrideMacros {
                                    // Pre-fill with current computed values
                                    editCal = "\((entry.calories * multiplier).safeInt)"
                                    editP = "\((entry.proteinG * multiplier).safeInt)"
                                    editC = "\((entry.carbsG * multiplier).safeInt)"
                                    editF = "\((entry.fatG * multiplier).safeInt)"
                                    editFb = "\((entry.fiberG * multiplier).safeInt)"
                                }
                                overrideMacros.toggle()
                            } label: {
                                Text(overrideMacros ? "Reset to auto" : "Edit macros")
                                    .font(.caption).foregroundStyle(Theme.accent)
                            }
                        }
                        .card()
                    }

                    // Ingredients + plant indicator
                    ingredientsSection

                    // Copy to Today (only when viewing past day)
                    if !viewModel.isToday {
                        Button {
                            viewModel.copyEntryToToday(entry)
                            onCopiedToToday(entry.foodName)
                            dismiss()
                        } label: {
                            Label("Copy to Today", systemImage: sym("doc.on.doc"))
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                    }
            }
            .padding(.horizontal, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        #if os(Android)
        .task {
            androidDbFood = entry.foodId.flatMap { FoodService.fetchFoodById($0) }
                ?? FoodService.findByName(entry.foodName)
        }
        #endif
    }

    private func save() {
        if let id = entry.id {
            if entry.foodId == nil || overrideMacros {
                if entry.foodId == nil && editName != entry.foodName {
                    FoodService.updateFoodEntryName(id: id, name: editName)
                }
                // #1004: editCal/editP/… hold the DISPLAYED TOTAL
                // (entry.macro × multiplier). Store them as PER-SERVING
                // (÷ servings) so updateEntryServings doesn't multiply the
                // total a second time (the old code double-counted, so
                // bumping servings silently ballooned the logged calories).
                let s = multiplier > 0 ? multiplier : 1
                FoodService.updateFoodEntryMacros(
                    id: id, calories: (Double(editCal) ?? entry.calories * s) / s,
                    proteinG: (Double(editP) ?? entry.proteinG * s) / s,
                    carbsG: (Double(editC) ?? entry.carbsG * s) / s,
                    fatG: (Double(editF) ?? entry.fatG * s) / s,
                    fiberG: (Double(editFb) ?? entry.fiberG * s) / s)
                if multiplier > 0, multiplier != entry.servings {
                    viewModel.updateEntryServings(id: id, servings: multiplier)
                }
            } else {
                viewModel.updateEntryServings(id: id, servings: multiplier)
            }
            let newLoggedAt = DateFormatters.iso8601.string(from: editEntryTime)
            if newLoggedAt != entry.loggedAt {
                viewModel.updateEntryLoggedAt(id: id, loggedAt: newLoggedAt)
            }
            if editMealType.rawValue != entry.mealType {
                viewModel.updateEntryMealType(id: id, mealType: editMealType)
            }
            onDone()
        }
        dismiss()
    }

    // MARK: - Ingredients Section

    @ViewBuilder
    private var ingredientsSection: some View {
        let dbFood: Food? = {
            #if os(Android)
            return androidDbFood
            #else
            if let fid = entry.foodId {
                return FoodService.fetchFoodById(fid)
            }
            return FoodService.findByName(entry.foodName)
            #endif
        }()
        let nova = dbFood?.novaGroup
        let hasIngredients = dbFood.map { $0.ingredientList.count > 1 || $0.ingredientList.first != $0.name } ?? false

        if nova == nil || (nova ?? 0) <= 2 {
            let plantClass = PlantPointsService.classify(entry.foodName)
            if plantClass != .notPlant {
                HStack(spacing: 6) {
                    #if os(Android)
                    LeafShape().fill(Theme.plantGreen).frame(width: 15, height: 15)
                    #else
                    Image(systemName: "leaf.fill").foregroundStyle(Theme.plantGreen)
                    #endif
                    Text(plantClass == .herbSpice ? "Herb/Spice (¼ pt)" : "Plant (1 pt)")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        } else if hasIngredients, let dbFood {
            let plantIngredients = dbFood.ingredientList.filter { PlantPointsService.classify($0) != .notPlant }
            if !plantIngredients.isEmpty {
                HStack(spacing: 6) {
                    #if os(Android)
                    LeafShape().fill(Theme.plantGreen).frame(width: 15, height: 15)
                    #else
                    Image(systemName: "leaf.fill").foregroundStyle(Theme.plantGreen)
                    #endif
                    Text("\(plantIngredients.count) plant ingredients")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }

        if hasIngredients, let dbFood {
            #if DRIFT_IOS_APP
            if dbFood.recipeItems != nil {
                Button { showingRecipeEditor = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ingredients").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            Text(dbFood.ingredientList.joined(separator: ", "))
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            } else {
                ingredientListText(dbFood)
            }
            #else
            // Recipe editing waits on the QuickAddView port (#1062 residual);
            // the list itself still reads the same.
            ingredientListText(dbFood)
            #endif
        }
    }

    private func ingredientListText(_ dbFood: Food) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ingredients").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Text(dbFood.ingredientList.joined(separator: ", "))
                .font(.caption).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - Helpers

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        // Fiber keeps one decimal for sub-10g totals so small portions (75g
        // strawberry → 1.5g) don't truncate to "0g". #282.
        let display = label == "Fb" ? MacroFormatter.fiber(value) : "\(Int(value))"
        return HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(display)g \(label)").font(.caption2.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// One editable macro field per View struct — Fuse binds only the FIRST
/// TextField in a ViewBuilder scope, so the four macro fields must each own
/// their scope. Internal, not private — Skip cannot bridge private views.
struct EditableMacroField: View {
    let label: String
    @Binding var text: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
            NumericField("0", text: $text, decimal: false)
                .font(.caption.weight(.medium).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 45)
                .padding(.vertical, 4)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// The calories row, extracted for the same one-TextField-per-scope rule.
struct CalorieField: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Text("Cal").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary).frame(width: 30)
            NumericField("0", text: $text, decimal: false).font(.title2.weight(.bold).monospacedDigit()).multilineTextAlignment(.center)
        }
    }
}
