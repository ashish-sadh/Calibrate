import SwiftUI

struct FoodTabView: View {
    @State private var viewModel = FoodLogViewModel()
    @State private var showingSearch = false
    @State private var showingQuickAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Daily totals
                    dailyTotalsCard

                    // Meals
                    ForEach(MealType.allCases, id: \.self) { mealType in
                        mealSection(mealType)
                    }
                }
                .padding()
            }
            .navigationTitle("Food")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingSearch = true
                        } label: {
                            Label("Search Food", systemImage: "magnifyingglass")
                        }
                        Button {
                            showingQuickAdd = true
                        } label: {
                            Label("Quick Add", systemImage: "plus.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                FoodSearchView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingQuickAdd) {
                QuickAddView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.loadTodayMeals()
            }
        }
    }

    private var dailyTotalsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's Nutrition")
                .font(.subheadline.bold())

            HStack(spacing: 12) {
                nutrientPill("\(Int(viewModel.todayNutrition.calories))", label: "cal", color: .blue)
                nutrientPill("\(Int(viewModel.todayNutrition.proteinG))g", label: "P", color: .red)
                nutrientPill("\(Int(viewModel.todayNutrition.fatG))g", label: "F", color: .yellow)
                nutrientPill("\(Int(viewModel.todayNutrition.carbsG))g", label: "C", color: .green)
                nutrientPill("\(Int(viewModel.todayNutrition.fiberG))g", label: "Fiber", color: .brown)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func nutrientPill(_ value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
    }

    private func mealSection(_ mealType: MealType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: mealType.icon)
                    .foregroundStyle(.secondary)
                Text(mealType.displayName)
                    .font(.subheadline.bold())
                Spacer()

                let entries = viewModel.todayMeals[mealType] ?? []
                let totalCal = entries.reduce(0) { $0 + $1.totalCalories }
                if totalCal > 0 {
                    Text("\(Int(totalCal)) cal")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            let entries = viewModel.todayMeals[mealType] ?? []
            if entries.isEmpty {
                Text("No items logged")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(entries, id: \.id) { entry in
                    HStack {
                        Text(entry.foodName)
                            .font(.subheadline)
                        Spacer()
                        Text("\(Int(entry.totalCalories))cal \(Int(entry.totalProtein))P \(Int(entry.totalFat))F \(Int(entry.totalCarbs))C")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if let id = entry.id {
                            Button(role: .destructive) {
                                viewModel.deleteEntry(id: id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
