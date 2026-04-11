import SwiftUI

struct EditFoodEntrySheet: View {
    let entry: FoodEntry
    @Bindable var viewModel: FoodLogViewModel
    let onCopiedToToday: (String) -> Void
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editAmount: String
    @State private var editUnitIndex = 0
    @State private var editEntryIsFav: Bool
    @State private var editEntryTime: Date
    @State private var editCal: String
    @State private var editP: String
    @State private var editC: String
    @State private var editF: String
    @State private var editFb: String
    @State private var editName: String

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
        _editEntryIsFav = State(initialValue: (try? AppDatabase.shared.isFoodFavorite(name: entry.foodName)) ?? false)
        _editEntryTime = State(initialValue: DateFormatters.iso8601.date(from: entry.loggedAt ?? "") ?? Date())
        _editCal = State(initialValue: "\(Int(entry.calories))")
        _editP = State(initialValue: "\(Int(entry.proteinG))")
        _editC = State(initialValue: "\(Int(entry.carbsG))")
        _editF = State(initialValue: "\(Int(entry.fatG))")
        _editFb = State(initialValue: "\(Int(entry.fiberG))")
        _editName = State(initialValue: entry.foodName)
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
                            Text(perText).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("\(Int(entry.calories))cal per serving")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 8)

                    // Compact time picker
                    HStack {
                        Image(systemName: "clock").font(.caption).foregroundStyle(.tertiary)
                        DatePicker("", selection: $editEntryTime, displayedComponents: .hourAndMinute)
                            .labelsHidden()
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
                                Text("Servings").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                TextField("1", text: $editAmount)
                                    .keyboardType(.decimalPad)
                                    .font(.subheadline.monospacedDigit())
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 50)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))

                        // Editable total macros
                        VStack(spacing: 8) {
                            HStack {
                                Text("Cal").font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(width: 30)
                                TextField("0", text: $editCal).keyboardType(.numberPad).font(.title2.weight(.bold).monospacedDigit()).multilineTextAlignment(.center)
                            }
                            HStack(spacing: 12) {
                                editableMacroField("P", text: $editP, color: Theme.proteinRed)
                                editableMacroField("C", text: $editC, color: Theme.carbsGreen)
                                editableMacroField("F", text: $editF, color: Theme.fatYellow)
                                editableMacroField("Fb", text: $editFb, color: Theme.fiberBrown)
                            }
                        }
                        .card()
                    } else {
                        // DB food — read-only macros (adjusted by serving multiplier)
                        VStack(spacing: 8) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text("\(Int(entry.calories * multiplier))")
                                    .font(.title.weight(.bold).monospacedDigit())
                                Text("cal").font(.subheadline).foregroundStyle(.secondary)
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
                            Label("Copy to Today", systemImage: "doc.on.doc")
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
            .navigationTitle("Edit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .principal) {
                    Button {
                        try? AppDatabase.shared.toggleFoodFavorite(name: entry.foodName, foodId: entry.foodId)
                        editEntryIsFav.toggle()
                    } label: {
                        Image(systemName: editEntryIsFav ? "star.fill" : "star")
                            .foregroundStyle(editEntryIsFav ? Theme.fatYellow : .secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let id = entry.id {
                            if entry.foodId == nil {
                                if editName != entry.foodName {
                                    try? AppDatabase.shared.updateFoodEntryName(id: id, name: editName)
                                }
                                try? AppDatabase.shared.updateFoodEntryMacros(
                                    id: id, calories: Double(editCal) ?? entry.calories,
                                    proteinG: Double(editP) ?? entry.proteinG,
                                    carbsG: Double(editC) ?? entry.carbsG,
                                    fatG: Double(editF) ?? entry.fatG,
                                    fiberG: Double(editFb) ?? entry.fiberG)
                            } else {
                                viewModel.updateEntryServings(id: id, servings: multiplier)
                            }
                            let newLoggedAt = DateFormatters.iso8601.string(from: editEntryTime)
                            if newLoggedAt != entry.loggedAt {
                                viewModel.updateEntryLoggedAt(id: id, loggedAt: newLoggedAt)
                            }
                            onDone()
                        }
                        dismiss()
                    }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.85), .large])
    }

    // MARK: - Ingredients Section

    @ViewBuilder
    private var ingredientsSection: some View {
        let dbFood: Food? = {
            if let fid = entry.foodId {
                return try? AppDatabase.shared.reader.read { db in try Food.fetchOne(db, id: fid) }
            }
            return (try? AppDatabase.shared.searchFoods(query: entry.foodName, limit: 1))?.first
        }()
        let nova = dbFood?.novaGroup
        let hasIngredients = dbFood.map { $0.ingredientList.count > 1 || $0.ingredientList.first != $0.name } ?? false

        if nova == nil || (nova ?? 0) <= 2 {
            let plantClass = PlantPointsService.classify(entry.foodName)
            if plantClass != .notPlant {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").foregroundStyle(Theme.plantGreen)
                    Text(plantClass == .herbSpice ? "Herb/Spice (¼ pt)" : "Plant (1 pt)")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        } else if hasIngredients {
            let plantIngredients = dbFood!.ingredientList.filter { PlantPointsService.classify($0) != .notPlant }
            if !plantIngredients.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "leaf.fill").foregroundStyle(Theme.plantGreen)
                    Text("\(plantIngredients.count) plant ingredients")
                        .font(.caption.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 4)
            }
        }

        if hasIngredients, let dbFood {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ingredients").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(dbFood.ingredientList.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Helpers

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))g \(label)").font(.caption2.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func editableMacroField(_ label: String, text: Binding<String>, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color)
            TextField("0", text: text)
                .keyboardType(.numberPad)
                .font(.caption.weight(.medium).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 45)
                .padding(.vertical, 4)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
