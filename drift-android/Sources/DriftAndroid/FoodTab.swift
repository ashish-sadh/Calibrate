import SwiftUI
import Observation
import SkipFuse
import DriftCore

/// Android Food tab: warms the DB off-main, then hosts the shared
/// `FoodTabView` port (SharedUI single-source, #1059/#1062). The old
/// Android-only re-creation (FoodStore + inline search card) is gone —
/// what remains here is the platform seam: the interim search sheet the
/// ported tab presents until FoodSearchView/LogMealSheet port, and the
/// serving-confirm stepper it logs through.
struct FoodTab: View {
    @State var warm = CoreResourcesBootstrap.isWarm

    var body: some View {
        if warm {
            FoodTabView(selectedTab: .constant(1))
        } else {
            // Only ever visible on the very first entry before the one-time
            // warm-up finishes; every later visit skips straight to content.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background.ignoresSafeArea())
                .task {
                    await CoreResourcesBootstrap.warmUpDatabase()
                    warm = true
                }
        }
    }
}

// MARK: - Interim search sheet

/// Search-and-log sheet presented by the ported FoodTabView's add-food entry
/// points. Debounced live search (0-SEARCH-PERF house pattern), off-main
/// SQLite, logs through the shared FoodLogViewModel so reload discipline and
/// `.foodEntryAdded` behave exactly like iOS. Replaced by the FoodSearchView
/// port later (#1062 residual).
struct AndroidFoodSearchSheet: View {
    let viewModel: FoodLogViewModel
    let initialMealType: MealType?
    @Environment(\.dismiss) var dismiss
    @State var query = ""
    @State var results: [Food] = []
    @State var confirmFood: Food? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // In-content header — SkipUI's nav bar in a sheet reserves an
                // ~80dp dead band above the title (#1089 pattern).
                ZStack {
                    Text(initialMealType.map { "Add to \($0.displayName)" } ?? "Add Food")
                        .font(.headline)
                    HStack {
                        Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                HStack(spacing: 8) {
                    Image(systemName: sym("magnifyingglass"))
                        .foregroundStyle(Theme.textTertiary)
                    SearchQueryField(query: $query)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Theme.cardBackground)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if results.isEmpty && query.count >= 2 {
                            Text("No foods found for \"\(query)\"")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else if results.isEmpty {
                            Text("Search the food database — dosa, dal, eggs…")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                        ForEach(results) { food in
                            Button { confirmFood = food } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(food.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                        Text("\(Int(food.calories)) kcal · P \(Int(food.proteinG))g · \(food.servingSize.formatted())\(food.servingUnit)")
                                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: sym("plus.circle.fill"))
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Theme.background)
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .task(id: query) { await liveSearch() }
        .sheet(item: $confirmFood) { food in
            ServingConfirmSheet(food: food,
                                initialMealType: initialMealType ?? viewModel.autoMealType) { servings, meal, time in
                viewModel.logFood(food, servings: servings, mealType: meal,
                                  loggedAt: viewModel.anchoredToSelectedDay(time))
            }
        }
    }

    /// Live search as the user types — 200ms debounce, cancelled per
    /// keystroke by `.task(id:)`; Skip's cancellation is cooperative, so the
    /// guards after each await are what discard a stale run.
    private func liveSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            return
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard !Task.isCancelled else { return }
        // The DB is warm before FoodTabView ever presents this sheet
        // (FoodTab gates on warmUpDatabase), so this is belt-and-braces
        // for the .openFoodSearch path (#1075 lesson: an early search that
        // beats warm-up throws inside try? → silent empty results).
        await CoreResourcesBootstrap.warmUpDatabase()
        guard !Task.isCancelled else { return }
        let hits = await onDB {
            (try? AppDatabase.shared.searchFoods(query: q, limit: 25)) ?? []
        }
        guard !Task.isCancelled else { return }
        results = hits
    }
}

// MARK: - Interim recent-meals sheet

/// Recent-meals sheet presented by the dashboard's Recent chip. Line-for-line
/// port of iOS `LogMealSheet.recentContent/recentRow/logEntry`
/// (LogMealSheet.swift:201–283) minus the segmented Recent/Search/Describe/Snap
/// chrome — that's the full `LogMealSheet` port, #1062 residual. Internal, not
/// private — Skip cannot bridge private views.
struct AndroidRecentMealsSheet: View {
    let viewModel: FoodLogViewModel
    @Environment(\.dismiss) var dismiss
    @State var recents: [RecentEntry] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // In-content header — SkipUI's nav bar in a sheet reserves an
                // ~80dp dead band above the title (#1089 pattern).
                ZStack {
                    Text("Recent")
                        .font(.headline)
                    HStack {
                        Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if recents.isEmpty {
                    Text("No recent foods yet — log a meal once and it'll appear here.")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(recents) { entry in
                                recentRow(entry)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .task {
            await CoreResourcesBootstrap.warmUpDatabase()
            recents = (try? AppDatabase.shared.fetchRecentEntryNames(limit: 30)) ?? []
        }
    }

    private func recentRow(_ entry: RecentEntry) -> some View {
        Button {
            logRecent(entry)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(entry.macroSummary)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(Int(entry.calories))")
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: sym("plus.circle.fill"))
                    .foregroundStyle(Theme.ink)
            }
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            .overlay(
                // strokeBorder(_:lineWidth:antialiased:) is an ambiguous overload
                // on SkipUI (not on Darwin) — plain stroke() is proven to compile
                // here (see TodayTab's ring()) and is visually identical at 0.5pt.
                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .stroke(Theme.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    /// Mirrors iOS `logEntry` (LogMealSheet.swift:256): re-log exactly what was
    /// logged before — a DB food via its catalog row, a recipe/manual/photo
    /// entry via its stored macros.
    private func logRecent(_ entry: RecentEntry) {
        if entry.isDBFood, let food = FoodService.findByName(entry.name) {
            viewModel.quickLogFood(food)
        } else {
            viewModel.quickAdd(
                name: entry.name,
                calories: entry.calories,
                proteinG: entry.proteinG,
                carbsG: entry.carbsG,
                fatG: entry.fatG,
                fiberG: entry.fiberG,
                mealType: viewModel.autoMealType,
                servingSizeG: entry.servingSize,
                servings: 1
            )
        }
        dismiss()
    }
}

/// The one TextField gets its own scope (Fuse binds only the first TextField
/// per ViewBuilder scope). Internal, not private — Skip cannot bridge
/// private views.
struct SearchQueryField: View {
    @Binding var query: String

    var body: some View {
        TextField("Search foods — dosa, dal, eggs…", text: $query)
            .textFieldStyle(.plain)
    }
}

private func onDB<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work())
        }
    }
}

// MARK: - Serving confirm

/// Half-serving stepper confirm. Interim: the shared ServingInputView
/// (amount field + unit pills + fraction chips) replaces this when the full
/// serving sheet ports (#1062 residual).
struct ServingConfirmSheet: View {
    let food: Food
    let onLog: (Double, MealType, Date) -> Void
    @Environment(\.dismiss) var dismiss
    @State var servings = 1.0
    @State var logTime = Date()
    @State var mealType: MealType

    init(food: Food, initialMealType: MealType, onLog: @escaping (Double, MealType, Date) -> Void) {
        self.food = food
        self.onLog = onLog
        _mealType = State(initialValue: initialMealType)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                // In-content chrome (#1089 pattern) — sheet nav bar off.
                HStack {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                    Spacer()
                }
                .padding(.top, 4)

                Text(food.name).font(Theme.fontTitle)
                Text("\(food.servingSize.formatted())\(food.servingUnit) per serving · \(Int(food.calories)) kcal")
                    .font(.caption).foregroundStyle(Theme.textSecondary)

                HStack(spacing: 20) {
                    Button {
                        servings = max(0.5, servings - 0.5)
                    } label: {
                        Text("−")
                            .font(.title2.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(Theme.pillBackground, in: Circle())
                    }.buttonStyle(.plain)

                    VStack(spacing: 2) {
                        Text(servings.formatted())
                            .font(Theme.rounded(size: Theme.FontSize.display1))
                        Text(servings == 1 ? "serving" : "servings")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(minWidth: 90)

                    Button {
                        servings += 0.5
                    } label: {
                        Text("+")
                            .font(.title2.weight(.semibold))
                            .frame(width: 40, height: 40)
                            .background(Theme.pillBackground, in: Circle())
                    }.buttonStyle(.plain)
                }

                Text("\(Int(food.calories * servings)) kcal · P \(Int(food.proteinG * servings))g")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                // Time slider + meal chips, coupled (2026-07-27 field ask) —
                // Android previously logged with autoMealType and no way to
                // adjust either.
                MealTimePicker(time: $logTime, mealType: $mealType)

                Button {
                    onLog(servings, mealType, logTime)
                    dismiss()
                } label: {
                    Text("Log Food")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: Capsule())
                }.buttonStyle(.plain)

                Spacer()
            }
            .padding(20)
            .background(Theme.background)
        }
    }
}
