import SwiftUI

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
        .preferredColorScheme(.dark)
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
        Section {
            ForEach($items) { $item in
                PhotoLogItemRow(item: $item)
            }
        } header: {
            Text("Items")
        } footer: {
            Text("Uncheck anything the model got wrong. Tap grams to adjust.")
                .font(.caption2)
        }
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

    /// Build a Food from the LLM's answer — LLM-first, no matching against
    /// the local food DB. Curated DB rows were giving users calories for a
    /// different portion than what the photo showed, which was confusing.
    /// Ingredients come from the LLM too (food_log schema extension) and are
    /// attached to the Food struct so plant-points picks them up via the
    /// existing name-join fallback in fetchFoodItemsForPlantPoints.
    private func photoLogFood(for item: PhotoLogEditableItem) -> Food {
        let ingredientsJSON: String? = {
            guard !item.ingredients.isEmpty else { return nil }
            let data = try? JSONEncoder().encode(item.ingredients)
            return data.flatMap { String(data: $0, encoding: .utf8) }
        }()
        return Food(
            name: item.name,
            category: "Photo Log",
            servingSize: max(item.grams, 1),
            servingUnit: "g",
            calories: item.calories,
            proteinG: item.proteinG,
            carbsG: item.carbsG,
            fatG: item.fatG,
            ingredients: ingredientsJSON,
            source: "photo_log"
        )
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
    @FocusState private var amountFocused: Bool
    @State private var amountText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                Button {
                    item.selected.toggle()
                } label: {
                    Image(systemName: item.selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(item.selected ? Theme.accent : Theme.textTertiary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(item.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if item.confidence == .low {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                                .foregroundStyle(Theme.surplus)
                        }
                    }
                    Text("\(Int(item.calories.rounded())) cal · \(Int(item.proteinG.rounded()))P / \(Int(item.carbsG.rounded()))C / \(Int(item.fatG.rounded()))F · \(Int(item.grams.rounded()))g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                amountField
                unitPicker
            }
        }
        .opacity(item.selected ? 1.0 : 0.45)
        .onAppear { syncAmountText() }
        .onChange(of: item.servingUnit) { _, _ in syncAmountText() }
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
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
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
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
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
