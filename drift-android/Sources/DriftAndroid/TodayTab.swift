import SwiftUI
import Observation
import SkipFuse
import DriftCore

// These row types lived in FoodTab.swift until the Food tab became the shared
// FoodTabView port (#1062) — the dashboard is their only consumer now.
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

/// Today tab v2 — ports the iOS DashboardView's visual structure: brand
/// header, the concentric intake rings, macro legend, Snap/Describe/Search/
/// Recent chips, TODAY'S MEALS, and the Weight/Sleep/Readiness stat trio.
/// (#1061 tracks the remaining Dashboard depth: coaching cards, sleep/
/// recovery data via Health Connect, daily-average footer.)
@MainActor @Observable class TodayStore {
    /// One instance for the whole app. `ContentView.tabContent` is a `switch`
    /// in a ViewBuilder, so each branch has its own view identity and Compose
    /// tears the outgoing tab down and rebuilds the incoming one on every tab
    /// change. With a per-view `@State` store that rebuild handed the screen a
    /// freshly-initialized (empty) store, so the tab painted "0 kcal left" and
    /// "Log your first meal" over real data until the async reload landed —
    /// reads as data loss, and is the "buggy" half of #1075. Sharing the
    /// instance keeps loaded data alive across the rebuild; observation is
    /// unchanged (still `@State` + `@Observable`, as before).
    static let shared = TodayStore()

    init() {
        reload()
        // Fuse's onAppear doesn't reliably re-fire on tab re-selection, so
        // data mutated elsewhere left this dashboard stale (#1090 sweep).
        // Food writes announce themselves via `.foodEntryAdded` (posted by the
        // shared FoodLogViewModel); weight writes call reload() directly from
        // WeightStore. Observer lives as long as the process — no removal.
        _ = NotificationCenter.default.addObserver(forName: .foodEntryAdded, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    var totals = TotalsRow()
    var proteinTarget = 0
    var carbsTarget = 0
    var fatTarget = 0
    var fiberTarget = 25
    var meals: [FoodEntryRow] = []
    var currentWeight = "—"
    var weekWorkouts = 0
    var streak = 0

    func reload() {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            let t = FoodService.getDailyTotals()
            totals = TotalsRow(eaten: t.eaten, target: t.target, remaining: t.remaining,
                               proteinG: t.proteinG, carbsG: t.carbsG, fatG: t.fatG, fiberG: t.fiberG)
            if let targets = WeightGoal.load()?.macroTargets(currentWeightKg: WeightTrendService.shared.trendWeight) {
                proteinTarget = Int(targets.proteinG)
                carbsTarget = Int(targets.carbsG)
                fatTarget = Int(targets.fatG)
                fiberTarget = Int(targets.fiberG)
            } else {
                // No goal configured yet — standard 30/40/30 split off the
                // resolved calorie target, same defaults a fresh iOS install shows.
                let kcal = Double(max(t.target, 1200))
                proteinTarget = Int(kcal * 0.30 / 4)
                carbsTarget = Int(kcal * 0.40 / 4)
                fatTarget = Int(kcal * 0.30 / 9)
                fiberTarget = 25
            }
            let entries = (try? AppDatabase.shared.fetchFoodEntries(for: DateFormatters.todayString)) ?? []
            meals = entries.compactMap { e in
                guard let id = e.id else { return nil }
                let servings = e.servings == 1 ? "" : "\(e.servings.formatted()) servings · "
                return FoodEntryRow(id: id, name: e.foodName,
                                    detail: "\(servings)\(Int(e.calories * e.servings)) kcal",
                                    mealType: e.mealType ?? "")
            }
            let unit = Preferences.weightUnit
            if let latest = WeightServiceAPI.getHistory(days: 365).sorted(by: { $0.date > $1.date }).first {
                let value = unit == .kg ? latest.weightKg : latest.weightKg * 2.20462
                currentWeight = String(format: "%.1f", value) + " \(unit.displayName)"
            }
            // Oldest → newest, so the current week is `.last` (correct here only
            // by accident of weeks:1 returning a single element — see #1076).
            weekWorkouts = (try? WorkoutService.weeklyWorkoutCounts(weeks: 1))?.last?.count ?? 0
            streak = (try? WorkoutService.workoutStreak())?.current ?? 0
        }
    }
}

struct TodayTab: View {
    @Binding var selectedTab: PrimaryTab
    @State var store = TodayStore.shared
    @State var showingCoachInfo = false
    @State var showingSearch = false
    @State var showingRecent = false
    @State var foodLogVM = FoodLogViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Brand header — matches iOS Dashboard's centered mark.
                    HStack(spacing: 8) {
                        Text("D")
                            .font(Theme.rounded(size: 17))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Theme.accent, in: Circle())
                        Text("Drift")
                            .font(Theme.rounded(size: 22))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.deficit)
                        Text("All data stays on your device.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }

                    intakeCard

                    logChips

                    mealsCard

                    statTrio
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .onAppear { store.reload() }
            .sheet(isPresented: $showingCoachInfo) { CoachComingSheet() }
            .sheet(isPresented: $showingSearch, onDismiss: { store.reload() }) {
                AndroidFoodSearchSheet(viewModel: foodLogVM, initialMealType: nil)
            }
            .sheet(isPresented: $showingRecent, onDismiss: { store.reload() }) {
                AndroidRecentMealsSheet(viewModel: foodLogVM)
            }
        }
    }

    // MARK: - Intake card with rings

    private var intakeCard: some View {
        let eaten = store.totals.eaten
        let target = max(store.totals.target, 1)
        let pct = Int((Double(eaten) / Double(target) * 100).rounded())
        return Button { selectedTab = .food } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TODAY'S INTAKE").sectionHeading()
                        Text("\(max(store.totals.remaining, 0)) kcal left")
                            .font(Theme.rounded(size: Theme.FontSize.title2))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    Text("\(pct)% of goal")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.accentSoft, in: Capsule())
                }

                rings
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                // Legend — kcal / protein / fiber, then carbs / fat.
                HStack {
                    legend("kcal", eaten, target, Theme.macroKcal)
                    legend("protein", store.totals.proteinG, store.proteinTarget, Theme.macroProtein, unit: "g")
                    legend("fiber", store.totals.fiberG, store.fiberTarget, Theme.macroFiber, unit: "g")
                }
                Divider()
                HStack {
                    legend("carbs", store.totals.carbsG, store.carbsTarget, Theme.macroCarbs, unit: "g")
                    legend("fat", store.totals.fatG, store.fatTarget, Theme.macroFat, unit: "g")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }

    private var rings: some View {
        let kcalProgress = min(Double(store.totals.eaten) / Double(max(store.totals.target, 1)), 1)
        let proteinProgress = min(Double(store.totals.proteinG) / Double(max(store.proteinTarget, 1)), 1)
        let fiberProgress = min(Double(store.totals.fiberG) / Double(max(store.fiberTarget, 1)), 1)
        return ZStack {
            ring(progress: kcalProgress, color: Theme.macroKcal, track: Theme.V6.ringMoveBg, diameter: 190)
            ring(progress: proteinProgress, color: Theme.macroProtein, track: Theme.deficitSoft, diameter: 150)
            ring(progress: fiberProgress, color: Theme.macroFiber, track: Color(hex: "D6EEF7"), diameter: 110)
            VStack(spacing: 0) {
                Text("\(store.totals.eaten)")
                    .font(Theme.rounded(size: Theme.FontSize.display2).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                Text("KCAL")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .tracking(1.5)
            }
        }
        .frame(height: 200)
    }

    private func ring(progress: Double, color: Color, track: Color, diameter: CGFloat) -> some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: 14)
            Circle()
                .trim(from: 0, to: max(progress, 0.001))
                .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }

    private func legend(_ label: String, _ value: Int, _ target: Int, _ color: Color, unit: String = "") -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 0) {
                Text("\(value)").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                Text("/\(target)\(unit)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Log chips (Snap / Describe / Search / Recent)

    private var logChips: some View {
        HStack(spacing: 10) {
            chip("Snap", icon: "camera.fill") { showingCoachInfo = true }
            chip("Describe", icon: "bubble.left.fill") { showingCoachInfo = true }
            // Present over Today, don't switch tabs first: ContentView.tabContent
            // is a `switch` on selectedTab (ContentView.swift:36) — changing it
            // unmounts TodayTab (and this sheet) before it can appear. Matches
            // iOS anyway (LogMealSheet is a dashboard-presented modal; the tab
            // selection doesn't change), and TodayStore's .foodEntryAdded
            // observer already updates the dashboard in place after a log.
            chip("Search", icon: "magnifyingglass") { showingSearch = true }
            chip("Recent", icon: "clock.arrow.circlepath") { showingRecent = true }
        }
    }

    private func chip(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: sym(icon))
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textPrimary)
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
            .shadowSoft(cornerRadius: Theme.radiusControl)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Meals

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TODAY'S MEALS").sectionHeading()
            if store.meals.isEmpty {
                Button { selectedTab = .food } label: {
                    HStack(spacing: 8) {
                        ForkKnifeShape()
                            .fill(Theme.textSecondary)
                            .frame(width: 12, height: 12)
                        Text("Log your first meal — try the Search chip above")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .card()
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.meals) { row in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Text(row.detail).font(.caption2).foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if !row.mealType.isEmpty {
                                Text(row.mealType.capitalized)
                                    .font(.system(size: Theme.FontSize.nano))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.pillBackground, in: Capsule())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Stat trio (Weight / Workouts / Streak)

    private var statTrio: some View {
        HStack(spacing: 10) {
            statCard("WEIGHT", store.currentWeight, Theme.accent) { selectedTab = .body }
            statCard("WORKOUTS", "\(store.weekWorkouts)", Theme.deficit, caption: "this week") { selectedTab = .workout }
            statCard("STREAK", store.streak > 0 ? "\(store.streak)w" : "—", Theme.stepsOrange) { selectedTab = .workout }
        }
    }

    private func statCard(_ label: String, _ value: String, _ color: Color,
                          caption: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 6, height: 6)
                    Text(label).font(.system(size: Theme.FontSize.tiny, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.6)
                }
                Text(value)
                    .font(Theme.rounded(size: Theme.FontSize.title3).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let caption {
                    Text(caption).font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
    }
}
