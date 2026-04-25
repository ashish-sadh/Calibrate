import SwiftUI
import DriftCore

/// Lightweight "log this food with adjustable servings" sheet. Opened when
/// the user taps a recent/favorite food in the Food tab suggestion strip,
/// replacing the old calories-first `ManualFoodEntrySheet` route that
/// couldn't rescale macros from serving changes. Reuses `ServingInputView`
/// so the unit pills, gram equivalence, and quick-amount buttons match the
/// rest of the app. #270.
struct FoodLogSheet: View {
    let food: Food
    let foodLog: FoodLogViewModel
    let onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amount: String
    @State private var selectedUnitIndex: Int = 0
    @State private var logTime: Date = Date()
    @State private var mealType: MealType = .snack
    @State private var mealTypeResolved = false

    init(food: Food, foodLog: FoodLogViewModel, onLogged: @escaping () -> Void) {
        self.food = food
        self.foodLog = foodLog
        self.onLogged = onLogged
        // Default "1" on a ml/g primary unit turned into 0.004 of a serving
        // for coffee (240ml) → 0.25 cal → displayed 0 cal. FoodUnit.defaultAmount
        // already existed for this exact reason but wasn't wired here; this
        // sheet re-opens from the Food tab suggestion strip, recents, and
        // re-log from diary so it hits the same coffee/milk zero-cal path.
        _amount = State(initialValue: FoodUnit.defaultAmount(for: food))
    }

    private var units: [FoodUnit] { FoodUnit.smartUnits(for: food) }

    private var unit: FoodUnit {
        let idx = min(selectedUnitIndex, max(units.count - 1, 0))
        return units.isEmpty ? FoodUnit(label: "g", gramsEquivalent: 1) : units[idx]
    }

    /// Multiplier applied to the Food's per-serving macros. Mirrors the
    /// formula in `FoodSearchView.logFoodSheet` so scaling stays identical.
    var multiplier: Double {
        FoodLogSheet.multiplier(amount: Double(amount) ?? 0,
                                unitGramsEquivalent: unit.gramsEquivalent,
                                servingSize: food.servingSize)
    }

    /// Pure helper so the scaling math is independently testable without
    /// spinning up a view. If the food has no declared serving size (e.g.
    /// a quick-add with servingSize=0), the amount itself becomes the
    /// multiplier — that matches the fallback `ServingInputView` uses.
    static func multiplier(amount: Double, unitGramsEquivalent: Double, servingSize: Double) -> Double {
        let grams = amount * unitGramsEquivalent
        return servingSize > 0 ? grams / servingSize : amount
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    ServingInputView(amount: $amount,
                                     selectedUnitIndex: $selectedUnitIndex,
                                     units: units,
                                     servingSize: food.servingSize)
                    totalsCard
                    timeAndMealPicker
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Log Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { logAndDismiss() }
                        .fontWeight(.semibold)
                        .disabled((Double(amount) ?? 0) <= 0)
                }
            }
            .onAppear(perform: resolveDefaultMealType)
        }
        .presentationDetents([.fraction(0.65), .large])
        .presentationBackground(Theme.background)
        .presentationCornerRadius(20)
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 4) {
            Text(food.name).font(.title3.weight(.semibold))
            let currentLabel = unit.label
            let scale: Double = {
                guard food.servingSize > 0, currentLabel != "g", currentLabel != "ml" else { return 1.0 }
                return unit.gramsEquivalent / food.servingSize
            }()
            // Prefix the gram figure with "≈" when the unit is an estimate
            // (spray=0.25g, tbsp=15g flat, synthesized scoops) so the UI doesn't
            // advertise a guessed number as ground truth. Audit 2026-04-24.
            let gramPrefix = unit.isEstimate ? "≈" : ""
            let perText = (currentLabel == "g" || currentLabel == "ml")
                ? "\(food.macroSummary) per \(Int(food.servingSize))\(food.servingUnit)"
                : "\(Int(food.calories * scale))cal \(Int(food.proteinG * scale))P \(Int(food.carbsG * scale))C \(Int(food.fatG * scale))F per 1 \(currentLabel) (\(gramPrefix)\(Int(unit.gramsEquivalent))g)"
            Text(perText).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var totalsCard: some View {
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
                Text("\(MacroFormatter.fiber(food.fiberG * multiplier))g fiber")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var timeAndMealPicker: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Time").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                DatePicker("", selection: $logTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            HStack {
                Text("Meal").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(MealType.allCases, id: \.self) { type in
                        Button {
                            mealType = type
                        } label: {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mealType.icon)
                        Text(mealType.displayName)
                    }
                    .font(.subheadline).foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private func macroChip(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 2, height: 10)
            Text("\(Int(value))g \(label)").font(.caption2.weight(.medium).monospacedDigit())
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Behavior

    /// Pick the default meal period once, using the same 3h-inherit logic
    /// as manual food logging. Won't clobber a user-selected value on
    /// subsequent body refreshes.
    private func resolveDefaultMealType() {
        guard !mealTypeResolved else { return }
        mealType = MealType.resolve(now: Date(), recentEntries: foodLog.todayEntries)
        mealTypeResolved = true
    }

    private func logAndDismiss() {
        foodLog.logFood(food, servings: multiplier, mealType: mealType, loggedAt: logTime)
        onLogged()
        dismiss()
    }
}
