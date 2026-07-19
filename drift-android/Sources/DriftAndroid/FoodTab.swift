import SwiftUI
import Observation
import SkipFuse
import DriftCore

// MARK: - Rows

struct FoodEntryRow: Identifiable, Sendable {
    let id: Int64
    let name: String
    let detail: String    // "2 servings · 340 kcal"
    let mealType: String
}

struct TotalsRow: Sendable {
    var eaten = 0
    var target = 0
    var remaining = 0
    var proteinG = 0
    var carbsG = 0
    var fatG = 0
    var fiberG = 0
}

struct FoodHit: Identifiable, Sendable {
    let id: Int64
    let name: String
    let calories: Int
    let proteinG: Int
    let servingDisplay: String
}

// MARK: - Store

@MainActor @Observable public class FoodStore {
    var totals = TotalsRow()
    var today: [FoodEntryRow] = []
    var query = ""
    var results: [FoodHit] = []

    init() { reload() }

    func reload() {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            let t = FoodService.getDailyTotals()
            totals = TotalsRow(eaten: t.eaten, target: t.target, remaining: t.remaining,
                               proteinG: t.proteinG, carbsG: t.carbsG, fatG: t.fatG, fiberG: t.fiberG)
            let entries = (try? AppDatabase.shared.fetchFoodEntries(for: DateFormatters.todayString)) ?? []
            today = entries.compactMap { e in
                guard let id = e.id else { return nil }
                let servings = e.servings == 1 ? "" : "\(e.servings.formatted()) servings · "
                return FoodEntryRow(id: id, name: e.foodName,
                                    detail: "\(servings)\(Int(e.calories * e.servings)) kcal · P \(Int(e.proteinG * e.servings))g",
                                    mealType: e.mealType ?? "")
            }
        }
    }

    func search() {
        let q = query
        Task {
            results = await Self.runSearch(q)
        }
    }

    private static func runSearch(_ query: String) async -> [FoodHit] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return await onDB {
            let foods = (try? AppDatabase.shared.searchFoods(query: query, limit: 25)) ?? []
            return foods.compactMap { f in
                guard let id = f.id else { return nil }
                return FoodHit(id: id, name: f.name, calories: Int(f.calories),
                               proteinG: Int(f.proteinG),
                               servingDisplay: "\(f.servingSize.formatted())\(f.servingUnit)")
            }
        }
    }

    func log(foodId: Int64, servings: Double) {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            if let food = FoodService.fetchFoodById(foodId) {
                let today = DateFormatters.todayString
                let mealType = Self.currentMealType()
                // food_entry.meal_log_id has a cascade FK — find or create the
                // day's meal log first, like the iOS and chat log paths do.
                let logs = FoodService.fetchMealLogs(for: today)
                var mealLogId = logs.first(where: { $0.mealType == mealType })?.id
                if mealLogId == nil {
                    var newLog = MealLog(date: today, mealType: mealType)
                    try? AppDatabase.shared.saveMealLog(&newLog)
                    mealLogId = newLog.id
                }
                if let mealLogId {
                    var entry = FoodEntry(food: food, servings: servings,
                                          date: today, mealType: mealType)
                    entry.mealLogId = mealLogId
                    try? AppDatabase.shared.saveFoodEntry(&entry)
                }
            }
            query = ""
            results = []
            reload()
        }
    }

    func delete(id: Int64) {
        Task {
            _ = FoodService.deleteEntry(id: id)
            reload()
        }
    }

    /// Same hour buckets the iOS quick-log flow uses.
    private static func currentMealType() -> String {
        switch Calendar.current.component(.hour, from: Date()) {
        case ..<11: return "breakfast"
        case ..<15: return "lunch"
        case ..<18: return "snack"
        default: return "dinner"
        }
    }
}

private func onDB<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work())
        }
    }
}

// MARK: - Food tab

struct FoodTab: View {
    @State var store = FoodStore()
    @State var confirmHit: FoodHit? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    totalsCard

                    // Search + log
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("Search foods — dosa, dal, eggs…", text: $store.query)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit { store.search() }
                            Button { store.search() } label: {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusChip))
                            }.buttonStyle(.plain)
                        }
                        ForEach(store.results) { hit in
                            Button { confirmHit = hit } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(hit.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                        Text("\(hit.calories) kcal · P \(hit.proteinG)g · \(hit.servingDisplay)")
                                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(.vertical, 4)
                            }.buttonStyle(.plain)
                        }
                    }
                    .card()

                    // Today's meals
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TODAY'S MEALS").sectionHeading()
                        if store.today.isEmpty {
                            Text("Nothing logged yet — search above to log your first meal")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 12)
                        }
                        ForEach(store.today) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                    HStack(spacing: 6) {
                                        if !row.mealType.isEmpty {
                                            Text(row.mealType.capitalized)
                                                .font(.system(size: Theme.FontSize.nano))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(Theme.pillBackground, in: Capsule())
                                                .foregroundStyle(Theme.textSecondary)
                                        }
                                        Text(row.detail).font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer()
                                Button { store.delete(id: row.id) } label: {
                                    Image(systemName: "trash")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }.buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .card()
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Food")
            .onAppear { store.reload() }
            .sheet(item: $confirmHit) { hit in
                ServingConfirmSheet(hit: hit) { servings in
                    store.log(foodId: hit.id, servings: servings)
                }
            }
        }
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TODAY'S INTAKE").sectionHeading()
                Spacer()
                if store.totals.target > 0 {
                    Text("\(store.totals.remaining) kcal left")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(store.totals.remaining >= 0 ? Theme.deficit : Theme.surplus)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(store.totals.eaten)")
                    .font(.system(size: Theme.FontSize.display1, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.macroKcal)
                Text("/ \(store.totals.target) kcal")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 8) {
                macroChip("P", store.totals.proteinG, Theme.macroProtein)
                macroChip("C", store.totals.carbsG, Theme.macroCarbs)
                macroChip("F", store.totals.fatG, Theme.macroFat)
                macroChip("Fiber", store.totals.fiberG, Theme.macroFiber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func macroChip(_ label: String, _ grams: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(grams)g \(label)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.pillBackground, in: Capsule())
    }
}

// MARK: - Serving confirm

struct ServingConfirmSheet: View {
    let hit: FoodHit
    let onLog: (Double) -> Void
    @Environment(\.dismiss) var dismiss
    @State var servings = 1.0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(hit.name).font(Theme.fontTitle)
                Text("\(hit.servingDisplay) per serving · \(hit.calories) kcal")
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
                            .font(.system(size: Theme.FontSize.display1, weight: .bold, design: .rounded))
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

                Text("\(Int(Double(hit.calories) * servings)) kcal · P \(Int(Double(hit.proteinG) * servings))g")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)

                Button {
                    onLog(servings)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
