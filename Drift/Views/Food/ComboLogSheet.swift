import SwiftUI

private struct ComboLogItem: Identifiable {
    let id = UUID()
    var recipeItem: QuickAddView.RecipeItem
    var enabled: Bool = true
    var servings: Double = 1

    var totalCal: Double { recipeItem.calories * servings }
    var totalP: Double { recipeItem.proteinG * servings }
    var totalC: Double { recipeItem.carbsG * servings }
    var totalF: Double { recipeItem.fatG * servings }
}

struct ComboLogSheet: View {
    let combo: Food
    @Bindable var viewModel: FoodLogViewModel
    let onLogged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var logItems: [ComboLogItem]

    init(combo: Food, viewModel: FoodLogViewModel, onLogged: @escaping () -> Void) {
        self.combo = combo
        self.viewModel = viewModel
        self.onLogged = onLogged
        _logItems = State(initialValue: (combo.recipeItems ?? []).map { ComboLogItem(recipeItem: $0) })
    }

    private var checkedItems: [ComboLogItem] { logItems.filter { $0.enabled } }

    private var totalCal: Double { logItems.isEmpty ? combo.calories : checkedItems.reduce(0) { $0 + $1.totalCal } }
    private var totalP: Double { logItems.isEmpty ? combo.proteinG : checkedItems.reduce(0) { $0 + $1.totalP } }
    private var totalC: Double { logItems.isEmpty ? combo.carbsG : checkedItems.reduce(0) { $0 + $1.totalC } }
    private var totalF: Double { logItems.isEmpty ? combo.fatG : checkedItems.reduce(0) { $0 + $1.totalF } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    macroSummary
                    if logItems.isEmpty {
                        noItemsFallback
                    } else {
                        itemList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(combo.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    let canLog = logItems.isEmpty || !checkedItems.isEmpty
                    Button(logItems.isEmpty ? "Log" : "Log \(checkedItems.count)") { logSelected() }
                        .fontWeight(.semibold)
                        .foregroundStyle(canLog ? Theme.accent : .secondary)
                        .disabled(!canLog)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var macroSummary: some View {
        HStack(spacing: 0) {
            macroStat(label: "cal", value: Int(totalCal))
            Divider().frame(height: 28)
            macroStat(label: "protein", value: Int(totalP))
            Divider().frame(height: 28)
            macroStat(label: "carbs", value: Int(totalC))
            Divider().frame(height: 28)
            macroStat(label: "fat", value: Int(totalF))
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 12))
        .animation(.easeInOut(duration: 0.2), value: totalCal)
    }

    private func macroStat(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.title3.weight(.semibold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("FOOD ITEMS")
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
            VStack(spacing: 1) {
                ForEach($logItems) { $item in
                    itemRow(item: $item)
                }
            }
        }
        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private func itemRow(item: Binding<ComboLogItem>) -> some View {
        HStack(spacing: 12) {
            Button {
                item.enabled.wrappedValue.toggle()
            } label: {
                Image(systemName: item.wrappedValue.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.wrappedValue.enabled ? Theme.accent : Color.secondary.opacity(0.4))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.wrappedValue.recipeItem.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(item.wrappedValue.enabled ? .primary : .secondary)
                Text("\(Int(item.wrappedValue.totalCal)) cal · \(Int(item.wrappedValue.totalP))g P")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            // Serving stepper
            HStack(spacing: 0) {
                Button {
                    if item.wrappedValue.servings > 0.5 {
                        item.servings.wrappedValue = max(0.5, (item.wrappedValue.servings * 10 - 5).rounded() / 10)
                    }
                } label: {
                    Image(systemName: "minus").font(.caption2.weight(.bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!item.wrappedValue.enabled)

                Text(item.wrappedValue.servings.truncatingRemainder(dividingBy: 1) == 0 ?
                     "\(Int(item.wrappedValue.servings))x" :
                     String(format: "%.1fx", item.wrappedValue.servings))
                    .font(.caption.weight(.medium))
                    .frame(width: 32, alignment: .center)
                    .foregroundStyle(item.wrappedValue.enabled ? .primary : .secondary)

                Button {
                    item.servings.wrappedValue = (item.wrappedValue.servings * 10 + 5).rounded() / 10
                } label: {
                    Image(systemName: "plus").font(.caption2.weight(.bold))
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!item.wrappedValue.enabled)
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var noItemsFallback: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text(combo.name).font(.headline)
            Text(combo.macroSummary).font(.subheadline).foregroundStyle(.secondary)
            Text("This combo was saved in an older format.\nAll macros will be logged as a single entry.")
                .font(.caption).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 12))
    }

    private func logSelected() {
        let mealType = viewModel.autoMealType
        if logItems.isEmpty {
            viewModel.quickAdd(name: combo.name, calories: combo.calories,
                               proteinG: combo.proteinG, carbsG: combo.carbsG,
                               fatG: combo.fatG, fiberG: combo.fiberG,
                               mealType: mealType, servingSizeG: combo.servingSize, servings: 1)
        } else {
            for item in checkedItems {
                viewModel.quickAdd(name: item.recipeItem.name,
                                   calories: item.totalCal,
                                   proteinG: item.totalP,
                                   carbsG: item.totalC,
                                   fatG: item.totalF,
                                   fiberG: item.recipeItem.fiberG * item.servings,
                                   mealType: mealType,
                                   servingSizeG: item.recipeItem.servingSizeG,
                                   servings: item.servings)
            }
        }
        try? AppDatabase.shared.trackFoodUsage(name: combo.name, foodId: combo.id, servings: 1,
                                               calories: combo.calories, proteinG: combo.proteinG,
                                               carbsG: combo.carbsG, fatG: combo.fatG, fiberG: combo.fiberG,
                                               servingSizeG: combo.servingSize)
        dismiss()
        onLogged()
    }
}
