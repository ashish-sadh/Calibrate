import SwiftUI

struct FoodTabView: View {
    @State private var viewModel = FoodLogViewModel()
    @State private var showingSearch = false
    @State private var showingQuickAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    dailyTotalsCard

                    ForEach(MealType.allCases, id: \.self) { mealType in
                        mealSection(mealType)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showingSearch = true } label: {
                            Label("Search Food", systemImage: "magnifyingglass")
                        }
                        Button { showingQuickAdd = true } label: {
                            Label("Quick Add", systemImage: "plus.circle")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                FoodSearchView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddView(viewModel: viewModel)
            }
            .onAppear { viewModel.loadTodayMeals() }
        }
    }

    private var dailyTotalsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Text("\(Int(viewModel.todayNutrition.calories))")
                    .font(.title.weight(.bold).monospacedDigit())
                Text("kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 8) {
                macroPill("P", value: viewModel.todayNutrition.proteinG, color: Theme.proteinRed)
                macroPill("C", value: viewModel.todayNutrition.carbsG, color: Theme.carbsGreen)
                macroPill("F", value: viewModel.todayNutrition.fatG, color: Theme.fatYellow)
                macroPill("Fiber", value: viewModel.todayNutrition.fiberG, color: Theme.fiberBrown)
            }
        }
        .card()
    }

    private func macroPill(_ label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 14)
            Text("\(Int(value))g \(label)")
                .font(.caption.weight(.medium).monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func mealSection(_ mealType: MealType) -> some View {
        let entries = viewModel.todayMeals[mealType] ?? []
        let totalCal = entries.reduce(0) { $0 + $1.totalCalories }

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: mealType.icon)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                Text(mealType.displayName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if totalCal > 0 {
                    Text("\(Int(totalCal)) cal")
                        .font(.caption.weight(.medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if entries.isEmpty {
                Text("Tap + to log food")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(entries, id: \.id) { entry in
                    HStack {
                        Text(entry.foodName)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(entry.totalCalories)) \u{2022} \(Int(entry.totalProtein))P \(Int(entry.totalCarbs))C \(Int(entry.totalFat))F")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let id = entry.id {
                            Button { viewModel.deleteEntry(id: id) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .card()
    }
}
