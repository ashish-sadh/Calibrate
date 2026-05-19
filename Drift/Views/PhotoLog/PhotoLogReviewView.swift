import SwiftUI
import UIKit
import DriftCore

/// Second step of the Photo Log flow. The cloud-vision response has been
/// decoded into `PhotoLogEditableItem`s by the parent; this view lets the
/// user uncheck misrecognized items, tweak the grams inline (macros scale
/// with the cached per-gram rates), pick a meal period, and log the
/// selected items. Shows an empty state if the provider returned nothing.
/// #224 / #267.
struct PhotoLogReviewView: View {
    @Binding var items: [PhotoLogEditableItem]
    let overallConfidence: Confidence
    let notes: String?
    /// Original captured image — passed to per-item AI correction so the fix
    /// call can reference the photo without re-running on the whole meal.
    let photo: UIImage?
    let foodLog: FoodLogViewModel
    let onLogged: () -> Void
    let onRetake: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var mealType: MealType = .snack
    @State private var mealTypeResolved = false

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    emptyState
                } else {
                    content
                }
            }
            .background(Theme.background)
            .navigationTitle("Review Photo Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: resolveDefaultMealType)
        }
    }

    // MARK: - Populated content

    private var content: some View {
        VStack(spacing: 0) {
            List {
                overallSection
                itemsSection
                if let notes, !notes.isEmpty {
                    Section {
                        Text(notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Notes")
                    }
                }
                mealSection
                totalsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)

            logButton
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Theme.background)
        }
    }

    private var overallSection: some View {
        Section {
            HStack {
                confidenceBadge(for: overallConfidence, big: true)
                Spacer()
                Text("\(items.count) item\(items.count == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var itemsSection: some View {
        let corrector: ((PhotoLogEditableItem, String) async -> PhotoLogItem?)? = photo.map { img in
            { item, hint in try? await PhotoLogFlowService.correctItem(item, hint: hint, image: img) }
        }
        return Section {
            ForEach($items) { $item in
                PhotoLogItemRow(item: $item, aiCorrector: corrector)
            }
            .onDelete(perform: removeItems)
            Button {
                items.append(.blank())
            } label: {
                Label("Add item", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text("Items")
        } footer: {
            Text("Edit the name, uncheck wrong items, swipe to delete, or Add item for anything the model missed. Tap grams or macros to adjust.")
                .font(.caption2)
        }
    }

    private func removeItems(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    private var mealSection: some View {
        Section {
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
        } header: {
            Text("Log as")
        }
    }

    private var totalsSection: some View {
        let totals = PhotoLogTotals.sum(items)
        return Section {
            HStack {
                totalStat("\(totals.calories)", "cal")
                Divider().frame(height: 24)
                totalStat("\(totals.proteinG)g", "protein")
                Divider().frame(height: 24)
                totalStat("\(totals.carbsG)g", "carbs")
                Divider().frame(height: 24)
                totalStat("\(totals.fatG)g", "fat")
            }
            .frame(maxWidth: .infinity)
        } header: {
            Text("Totals (\(totals.selectedCount) selected)")
        }
    }

    private func totalStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.fontHeadline).foregroundStyle(Theme.textPrimary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var logButton: some View {
        let totals = PhotoLogTotals.sum(items)
        return Button {
            logSelected()
        } label: {
            Text(totals.selectedCount == 0
                 ? "Select at least one item"
                 : "Log \(totals.selectedCount) item\(totals.selectedCount == 1 ? "" : "s") as \(mealType.displayName)")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(totals.selectedCount == 0)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 56))
                .foregroundStyle(Theme.textTertiary)
            Text("We couldn't spot any food in that photo.")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Try one with the meal centered and in good light.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                onRetake()
            } label: {
                Label("Take another", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .padding(.top, 8)
        }
        .padding(24)
    }

    // MARK: - Behavior

    /// Resolve the default meal period the first time this view appears.
    /// Uses the same 3h-inherit rule as manual food logging so a second
    /// bowl at 10am still defaults to breakfast. Flag ensures we don't
    /// clobber a user-picked meal on subsequent body refreshes.
    private func resolveDefaultMealType() {
        guard !mealTypeResolved else { return }
        mealType = MealType.resolve(now: Date(), recentEntries: foodLog.todayEntries)
        mealTypeResolved = true
    }

    private func logSelected() {
        for item in items where item.selected {
            foodLog.logFood(photoLogFood(for: item), servings: 1, mealType: mealType)
        }
        onLogged()
        dismiss()
    }

    /// Build a Food from the LLM's answer — LLM-first for macros (no curated
    /// overrides), but persist a `source="photo_log"` row when the name is
    /// new so the ingredients JSON survives for plant-points joins.
    /// `saveScannedFood` is a no-op when a Food with that name already
    /// exists, so we don't pollute the DB with duplicates; in that case
    /// food_id stays nil on the FoodEntry and plant-points name-fallbacks
    /// to the existing curated Food's ingredients.
    private func photoLogFood(for item: PhotoLogEditableItem) -> Food {
        let ingredientsJSON: String? = {
            guard !item.ingredients.isEmpty else { return nil }
            let data = try? JSONEncoder().encode(item.ingredients)
            return data.flatMap { String(data: $0, encoding: .utf8) }
        }()
        var food = Food(
            name: item.name,
            category: "Photo Log",
            servingSize: max(item.grams, 1),
            servingUnit: "g",
            calories: item.calories,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            fiberG: item.fiberG,
            ingredients: ingredientsJSON,
            source: "photo_log"
        )
        // Persist only if the name is new — otherwise the existing curated
        // Food wins (its own ingredients feed plant-points via the name-
        // fallback join). Macros we pass to logFood are ALWAYS the LLM's;
        // food_entry.calories = food.calories, so curated macros never leak.
        _ = FoodService.saveScannedFood(&food)
        return food
    }

    private func confidenceBadge(for confidence: Confidence, big: Bool = false) -> some View {
        let (text, color): (String, Color) = switch confidence {
        case .high: ("High confidence", Theme.deficit)
        case .medium: ("Medium confidence", Theme.fatYellow)
        case .low: ("Low confidence — double-check", Theme.surplus)
        }
        return Label(text, systemImage: confidence == .low ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
            .font(big ? .footnote : .caption2)
            .foregroundStyle(color)
    }
}

// MARK: - Row

private struct PhotoLogItemRow: View {
    @Binding var item: PhotoLogEditableItem
    /// Scoped AI corrector — called with just this item + hint. Never receives
    /// the full items array. nil when no photo is available (e.g. tests).
    let aiCorrector: ((PhotoLogEditableItem, String) async -> PhotoLogItem?)?
    @FocusState private var amountFocused: Bool
    @FocusState private var correctionFocused: Bool
    @FocusState private var searchFocused: Bool
    @State private var amountText: String = ""
    @State private var expanded: Bool = false
    @State private var showCorrection: Bool = false
    @State private var correctionHint: String = ""
    @State private var correctionError: String? = nil
    @State private var correctionLoading = false
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var searchResults: [Food] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showSearch {
                searchField
            } else {
            // Top row — checkbox, name, amount+unit picker.
            HStack(alignment: .center, spacing: 12) {
                Button {
                    item.selected.toggle()
                } label: {
                    Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.selected ? Theme.accent : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.selected ? "Deselect \(item.name)" : "Select \(item.name)")

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("Name", text: $item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.words)
                        if item.confidence == .low {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.surplus)
                        }
                        if item.macrosManuallyEdited {
                            Image(systemName: "pencil.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Text("\(Int(item.calories.rounded())) cal · \(Int(item.grams.rounded()))g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                amountField
                unitPicker
            }

            macroBoxes

            if !item.ingredients.isEmpty {
                plantBadge
            }

            correctionRow
            } // end else
        }
        .opacity(item.selected ? 1.0 : 0.45)
        .onAppear { syncAmountText() }
        .onChange(of: item.servingUnit) { _, _ in syncAmountText() }
        .task {
            guard item.name.isEmpty && item.calories == 0 else { return }
            showSearch = true
            try? await Task.sleep(nanoseconds: 100_000_000)
            searchFocused = true
        }
    }

    // MARK: - Inline DB search (new blank items)

    private var searchField: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField("Search foods…", text: $searchQuery)
                    .font(.subheadline)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
                    .onChange(of: searchQuery) { _, q in
                        let trimmed = q.trimmingCharacters(in: .whitespaces)
                        searchResults = trimmed.count >= 2
                            ? Array(FoodService.searchFood(query: trimmed).prefix(5))
                            : []
                    }
                    .onSubmit { commitSearch() }
                Button { commitSearch() } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 10))

            ForEach(searchResults, id: \.name) { food in
                Button {
                    item.applyHintMatch(food)
                    searchQuery = ""
                    searchResults = []
                    showSearch = false
                } label: {
                    HStack {
                        Text(food.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(food.calories.rounded())) cal · \(Int(food.servingSize.rounded()))g")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commitSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { item.name = trimmed }
        searchQuery = ""
        searchResults = []
        showSearch = false
    }

    // MARK: - Correction row

    @ViewBuilder
    private var correctionRow: some View {
        if showCorrection {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("e.g. paratha, or 'half portion'", text: $correctionHint)
                        .font(.caption)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .focused($correctionFocused)
                        .onSubmit { applyCorrection() }
                        .onChange(of: correctionHint) { _, _ in correctionError = nil }
                    if correctionLoading {
                        ProgressView()
                            .frame(width: 32)
                    } else {
                        Button("Fix") { applyCorrection() }
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                            .disabled(correctionHint.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if let error = correctionError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(Theme.surplus)
                }
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else {
            Button {
                withAnimation { showCorrection = true }
                correctionFocused = true
            } label: {
                Text("Not right? Describe the food")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    private func applyCorrection() {
        let hint = correctionHint.trimmingCharacters(in: .whitespaces)
        guard !hint.isEmpty else { return }

        // Portion multiplier is purely local — no AI needed.
        if let multiplier = PhotoLogMatcher.parsePortionMultiplier(hint), item.grams > 0 {
            item.setAmount(item.servingAmount * multiplier)
            correctionHint = ""
            correctionError = nil
            withAnimation { showCorrection = false }
            return
        }

        // AI correction scoped to this item only — passes item + hint + photo,
        // never the full items array. Other rows are untouched.
        guard let aiCorrector else {
            correctionError = "Correction unavailable — try 'half' or 'double' for portions."
            return
        }
        correctionLoading = true
        correctionError = nil
        Task { @MainActor in
            defer { correctionLoading = false }
            if let aiItem = await aiCorrector(item, hint) {
                item.applyAICorrection(aiItem)
                correctionHint = ""
                correctionError = nil
                withAnimation { showCorrection = false }
            } else {
                correctionError = "Couldn't identify that — try a clearer description."
            }
        }
    }

    // MARK: - Amount field

    /// Step-friendly decimal input. Accepts "1", "1.5", "0.5" etc. so pieces
    /// like "1.5 slices of pizza" or "0.5 cup rice" feel natural.
    private var amountField: some View {
        TextField("0", text: $amountText)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .focused($amountFocused)
            .frame(width: 56)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: amountText) { _, newValue in
                // Allow trailing "." so the user can type "1.5" without the
                // field nuking partial input. Only commit when parseable.
                if let parsed = Double(newValue), abs(parsed - item.servingAmount) > 1e-6 {
                    item.setAmount(parsed)
                }
            }
    }

    // MARK: - Unit picker

    private var unitPicker: some View {
        Menu {
            ForEach(PhotoLogServingUnit.allCases, id: \.self) { u in
                Button {
                    item.setUnit(u)
                } label: {
                    if u == item.servingUnit {
                        Label(u.label, systemImage: "checkmark")
                    } else {
                        Text(u.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(item.servingUnit.label).font(.caption.weight(.medium))
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .foregroundStyle(.secondary)
            .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Macro boxes

    /// Five-up editable macro grid (Cal / P / C / F / Fb) — mirrors the
    /// manual food log sheet so users have the same editing affordance for
    /// LLM-detected items as for manually-entered ones.
    private var macroBoxes: some View {
        HStack(spacing: 6) {
            macroBox("Cal", value: item.calories, field: .calories, color: Theme.textPrimary)
            macroBox("P",   value: item.proteinG, field: .protein,  color: Theme.proteinRed)
            macroBox("C",   value: item.carbsG,   field: .carbs,    color: Theme.carbsGreen)
            macroBox("F",   value: item.fatG,     field: .fat,      color: Theme.fatYellow)
            macroBox("Fb",  value: item.fiberG,   field: .fiber,    color: Theme.textSecondary)
        }
    }

    private func macroBox(_ label: String,
                          value: Double,
                          field: PhotoLogEditableItem.MacroField,
                          color: Color) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(color)
            TextField("0", text: macroBinding(for: field))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
                .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    /// TextField binding per macro — parses decimals, commits via `setMacro`
    /// so per-gram rates get re-derived and future amount changes still reflow
    /// proportionally from the corrected baseline.
    private func macroBinding(for field: PhotoLogEditableItem.MacroField) -> Binding<String> {
        Binding(
            get: {
                let v = currentValue(for: field)
                return v == floor(v) ? String(Int(v.rounded())) : String(format: "%.1f", v)
            },
            set: { newValue in
                guard let parsed = Double(newValue) else { return }
                if abs(parsed - currentValue(for: field)) > 1e-6 {
                    item.setMacro(field, to: parsed)
                }
            }
        )
    }

    private func currentValue(for field: PhotoLogEditableItem.MacroField) -> Double {
        switch field {
        case .calories: return item.calories
        case .protein:  return item.proteinG
        case .carbs:    return item.carbsG
        case .fat:      return item.fatG
        case .fiber:    return item.fiberG
        }
    }

    // MARK: - Plant badge

    private var plantBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "leaf.fill")
                .font(.caption2)
                .foregroundStyle(Theme.deficit)
            Text(item.ingredients.joined(separator: ", "))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Text sync

    /// Keep the TextField's string representation in sync with the underlying
    /// double so unit changes and external mutations reflect immediately.
    /// Integer units render without a trailing ".0" for cleaner UX.
    private func syncAmountText() {
        let v = item.servingAmount
        if v == floor(v) {
            amountText = String(Int(v.rounded()))
        } else {
            amountText = String(format: "%.1f", v)
        }
    }
}
