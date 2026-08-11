import SwiftUI
import Observation
import SkipFuse
import DriftCore

// `FoodEntryRow` lived here to feed the dashboard's hand-built meal list. That
// list is now the shared `MealTimelineSection` (#1131), which builds its own
// rows from `[FoodEntry]` via `rows(from:)` — sorting, time formatting and
// nil-id handling included — so the local row type had no consumer left.

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
    var foodEntries: [FoodEntry] = []
    var currentWeight = "—"
    var weekWorkouts = 0
    var streak = 0

    // MARK: - Daily Average (energy balance) inputs
    //
    // iOS computes all of this inside `DashboardView.tdeeCard`'s body. On Fuse a
    // body re-evaluates per scroll frame and every one of these calls crosses
    // the JNI bridge into SQLite or the key-value store —
    // `WeightTrendService.refresh()` (2 weight fetches), `cachedOrSync()`,
    // `WeightGoal.load()`, `macroTargets()`/`requiredDailyDeficit()` (both read
    // `drift_tdee_config` + the algorithm config), and the two 14-day
    // aggregates. So they run here, once per reload, and the card body does
    // nothing but arithmetic and formatting (directive 0e).
    var dailyDeficit: Double?
    var dailyDeficitIsSoft = false
    var tdee: Double = 0
    var weeklyRate: Double?
    var avgDailyIntake: Double = 0
    var foodLogConsistency: Double = 0
    var trendWeightKg: Double?
    var latestWeightKg: Double?
    var activeSources: [String] = []
    var weightUnit: WeightUnit = .lbs
    var regressionWindowDays = 21
    /// Goal-derived values, all resolved in `reload()` for the same reason.
    /// `goalIsLosing` follows iOS's `isGoalAligned` (trend weight); the target
    /// line's `targetIsLosing`/`goalRemainingAbs` follow the goal card (latest
    /// weight) — iOS deliberately uses the two different weights.
    var hasGoal = false
    var goalIsLosing = true
    var requiredDailyDeficit: Double = 0
    var goalCalorieTarget: Double?
    var goalRemainingAbs: Double = 0
    var goalHasCustomMacros = false
    var targetIsLosing = true

    func reload() {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            // FIRST, before anything reads a weight: `macroTargets()` below
            // reaches `TDEEEstimator.cachedOrSync()`, which asks
            // WeightTrendService for the latest weight and caches whatever it
            // gets. Unrefreshed in a fresh process that weight is nil, so the
            // estimator cached its no-weight fallback (a flat 2000 kcal,
            // source "Default") and every calorie target hung off it. iOS does
            // the same refresh first (DashboardViewModel.loadData:112).
            WeightTrendService.shared.refresh()
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
            // Handed to `MealTimelineSection` raw: the shared component owns
            // sorting (ascending, so the earliest meal leads) and formatting.
            foodEntries = (try? AppDatabase.shared.fetchFoodEntries(for: DateFormatters.todayString)) ?? []
            let unit = Preferences.weightUnit
            weightUnit = unit
            if let latest = WeightServiceAPI.getHistory(days: 365).sorted(by: { $0.date > $1.date }).first {
                let value = unit == .kg ? latest.weightKg : latest.weightKg * 2.20462
                currentWeight = String(format: "%.1f", value) + " \(unit.displayName)"
            }
            reloadDailyAverage()
            // Oldest → newest, so the current week is `.last` (correct here only
            // by accident of weeks:1 returning a single element — see #1076).
            weekWorkouts = (try? WorkoutService.weeklyWorkoutCounts(weeks: 1))?.last?.count ?? 0
            streak = (try? WorkoutService.workoutStreak())?.current ?? 0
        }
    }

    /// Mirrors `DashboardViewModel.loadData()` lines 110-130 — the inputs iOS's
    /// `tdeeCard` reads off its view model, minus the HealthKit half (Android
    /// gets those through the Health Connect seam, #1070).
    private func reloadDailyAverage() {
        // The trend is already refreshed at the top of `reload()`.
        let trendService = WeightTrendService.shared
        trendWeightKg = trendService.trendWeight
        latestWeightKg = trendService.latestWeightKg
        weeklyRate = trendService.weeklyRate
        dailyDeficit = trendService.dailyDeficit
        dailyDeficitIsSoft = trendService.dailyDeficitIsSoft

        let est = TDEEEstimator.shared.cachedOrSync()
        tdee = est.tdee
        activeSources = est.activeSources
        regressionWindowDays = WeightTrendCalculator.loadConfig().regressionWindowDays

        // 14-day intake average + logging consistency, same window as iOS.
        let today = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today
        let fromStr = DateFormatters.dateOnly.string(from: twoWeeksAgo)
        let toStr = DateFormatters.dateOnly.string(from: today)
        avgDailyIntake = (try? AppDatabase.shared.averageDailyCalories(from: fromStr, to: toStr)) ?? 0
        let daysLogged = (try? AppDatabase.shared.daysWithFoodLogged(from: fromStr, to: toStr)) ?? 0
        foodLogConsistency = Double(daysLogged) / 14.0

        guard let goal = WeightGoal.load() else {
            hasGoal = false
            goalCalorieTarget = nil
            requiredDailyDeficit = 0
            return
        }
        hasGoal = true
        let trendKg = trendWeightKg ?? goal.startWeightKg
        goalIsLosing = goal.isLosing(currentWeightKg: trendKg)
        requiredDailyDeficit = goal.requiredDailyDeficit(currentWeightKg: trendKg)
        goalHasCustomMacros = goal.proteinTargetG != nil || goal.carbsTargetG != nil || goal.fatTargetG != nil
        // The target line needs a real weigh-in — iOS hides it otherwise.
        if let displayKg = latestWeightKg ?? trendWeightKg {
            goalCalorieTarget = goal.macroTargets(currentWeightKg: trendWeightKg)?.calorieTarget
            goalRemainingAbs = abs(weightUnit.convert(fromKg: goal.remainingKg(currentWeightKg: displayKg)))
            targetIsLosing = goal.isLosing(currentWeightKg: displayKg)
        } else {
            goalCalorieTarget = nil
        }
    }
}

struct TodayTab: View {
    @Binding var selectedTab: PrimaryTab
    @State var store = TodayStore.shared
    @State var showingSnap = false
    @State var showingSearch = false
    @State var showingRecent = false
    @State var showingDescribe = false
    @State var showDeficitExplainer = false
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
                        // "All data" stopped being literally true when opt-out
                        // usage telemetry shipped (2026-07-28); health data IS
                        // still local, and every cloud touchpoint is user-chosen.
                        Text("Your health data stays on your device — you choose what to share.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }

                    intakeCard

                    dailyAverageCard

                    // Coach, clients & friends — thin pills, matching iOS.
                    // Each pill pushes onto the enclosing NavigationStack: a
                    // bare sheet would give SharingView's internal
                    // NavigationLinks no stack to push onto, making every row
                    // inside a dead tap (operator repro on build 69).
                    SocialPillRow()

                    logChips

                    mealsCard

                    statTrio
                }
                .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .onAppear { store.reload() }
            // TodayStore's .foodEntryAdded observer refreshes the dashboard,
            // but onDismiss also covers the cancel path's ring re-check.
            // fullScreenCover, not sheet: iOS presents Photo Log edge-to-edge
            // (ContentView.swift:118 — "single owner of the Photo Log
            // fullScreenCover"), so a partial sheet with the dashboard dimmed
            // behind it and a drag grabber above the title read as a
            // different app.
            .fullScreenCover(isPresented: $showingSnap, onDismiss: { store.reload() }) {
                SnapMealSheet()
            }
            .sheet(isPresented: $showingDescribe, onDismiss: { store.reload() }) {
                DescribeMealSheet()
            }
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
                        // `.formatted()` for the thousands separator — iOS
                        // reads "1,470 kcal left", Android read "2000".
                        Text("\(max(store.totals.remaining, 0).formatted()) kcal left")
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
                // Separators here too: the macro row read "0/2000" against
                // iOS's "0/1,469".
                Text("\(value.formatted())").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Theme.textPrimary)
                Text("/\(target.formatted())\(unit)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Daily Average (energy balance)

    /// 1:1 port of iOS `DashboardView.tdeeCard` (DashboardView+Cards.swift:10-170).
    /// Reads only precomputed `store` values — see `TodayStore.reloadDailyAverage()`.
    /// iOS wraps the card in a `NavigationLink` to `AlgorithmSettingsView`; that
    /// screen has no Android counterpart yet (#1118), so this one doesn't
    /// navigate — the info button still opens the explainer.
    private var dailyAverageCard: some View {
        let deficit = store.dailyDeficit ?? 0
        let tdee = store.tdee
        let trendIntake = tdee + deficit
        let consistency = store.foodLogConsistency
        let loggedIntake = store.avgDailyIntake
        let useFoodLogs = consistency >= 0.5 && loggedIntake > 500
            && abs(loggedIntake - trendIntake) < trendIntake * 0.4
        let intake = store.dailyDeficit != nil ? (useFoodLogs ? loggedIntake : trendIntake) : 0
        let ringFraction = intake > 0 ? min(1.0, max(0, intake / max(1, tdee))) : 0
        let deficitLabel = deficit < -5 ? "deficit" : deficit > 5 ? "surplus" : "balanced"
        // Soft read: the short-window estimate disagrees with the longer
        // horizon (recent water swing) — gray, ≈, rounded to 10s, never
        // goal-colored. Same treatment as iOS.
        let isSoft = store.dailyDeficitIsSoft
        let softDeficit = (deficit / 10).rounded() * 10

        return VStack(spacing: 12) {
            HStack {
                Text("Daily Average").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Text("14-day").font(.caption2).foregroundStyle(Theme.textTertiary)
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showDeficitExplainer.toggle() }
                    } label: {
                        Image(systemName: "info.circle").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Daily average info")
                }
            }

            // Centered ring: eating / deficit / burning (or just TDEE if no trend)
            if store.dailyDeficit == nil {
                // No weight trend — just show TDEE estimate
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        // `.formatted()` everywhere iOS interpolates an Int into a
                        // Text: SwiftUI localizes those through LocalizedStringKey
                        // and groups them ("2,220"), SkipUI doesn't ("2220").
                        // Same fix the intake card needed above.
                        Text("\(Int(tdee).formatted())")
                            .font(.title.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Text("kcal/day").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    Text("Est. Expenditure").font(.caption).foregroundStyle(Theme.textSecondary)
                    Text("Log weight to see energy balance").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 0) {
                    VStack(spacing: 2) {
                        Text("~\(Int(intake).formatted())")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Text("eating")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)

                    ZStack {
                        Circle()
                            .stroke(Theme.cardBackgroundElevated, lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: ringFraction)
                            .stroke(isSoft ? Theme.textTertiary
                                    : isGoalAligned(deficit) ? Theme.deficit : Theme.surplus,
                                    style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        VStack(spacing: 1) {
                            Text(isSoft ? "≈\(String(format: "%+.0f", softDeficit).replacingOccurrences(of: "-", with: "−"))" : "\(Int(abs(deficit)).formatted())")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(isSoft ? Theme.textSecondary : Theme.textPrimary)
                            Text(isSoft ? "recent swing" : deficitLabel)
                                .font(.caption2.weight(.medium)).foregroundStyle(Theme.textSecondary)
                            Text("/day")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(width: 88, height: 88)

                    VStack(spacing: 2) {
                        Text("\(Int(tdee).formatted())")
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                        Text("burning")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Target line — uses latest weight to match goal card display
            if let target = store.goalCalorieTarget {
                let remainingAbs = store.goalRemainingAbs
                let losing = store.targetIsLosing
                // When custom macros are set, calorie target is user-chosen — don't imply it directly causes the weight change
                let targetText = store.goalHasCustomMacros
                    ? "Target: \(Int(target)) kcal/day · \(String(format: "%.1f", remainingAbs)) \(store.weightUnit.displayName) to \(losing ? "lose" : "gain")"
                    : "Target: eat \(Int(target)) kcal/day to \(losing ? "lose" : "gain") \(String(format: "%.1f", remainingAbs)) \(store.weightUnit.displayName)"
                Text(targetText)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            // Expandable detail (only when we have actual data to explain)
            if showDeficitExplainer, store.hasGoal || store.weeklyRate != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if store.hasGoal {
                        let required = store.requiredDailyDeficit
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text("Required").font(.caption2).foregroundStyle(Theme.textTertiary)
                                Text("\(required < 0 ? "" : "+")\(Int(required).formatted())")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(isGoalAligned(required) ? Theme.deficit : Theme.surplus)
                            }
                            VStack(spacing: 2) {
                                Text("Current").font(.caption2).foregroundStyle(Theme.textTertiary)
                                Text("\(deficit < 0 ? "" : "+")\(Int(deficit).formatted())")
                                    .font(.caption.weight(.bold).monospacedDigit())
                                    .foregroundStyle(isSoft ? Theme.textSecondary
                                                    : isGoalAligned(deficit) ? Theme.deficit : Theme.surplus)
                            }
                            Text("kcal/day").font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    if let rate = store.weeklyRate {
                        Text("Trend: \(String(format: "%+.2f", store.weightUnit.convert(fromKg: rate))) \(store.weightUnit.displayName)/wk → \(String(format: "%+.0f", deficit)) kcal/day")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                        Text("Based on \(store.regressionWindowDays)-day weight trend.")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                        if isSoft {
                            Text("The last few days disagree with your longer trend — likely water. Soft read until they agree.")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .transition(.opacity)
            }

            // Data sources — quiet gray pills, metadata not CTAs (V7 discipline).
            HStack(spacing: 4) {
                ForEach(store.activeSources, id: \.self) { source in
                    Text(source)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
        }
        .card()
    }

    /// Is this deficit/surplus aligned with the user's goal? Direction comes
    /// from the goal vs the CURRENT trend weight, resolved in `reload()`; with
    /// no goal, iOS assumes losing.
    private func isGoalAligned(_ deficit: Double) -> Bool {
        guard store.hasGoal else { return deficit < 0 }
        return store.goalIsLosing ? deficit < 0 : deficit > 0
    }

    // MARK: - Log chips (Snap / Describe / Search / Recent)

    private var logChips: some View {
        HStack(spacing: 10) {
            // Snap/Describe draw real Shapes: skip-ui's Material map has no
            // camera and no chat bubble, so sym() fell through to a QR-SCAN
            // square and a SEND ARROW respectively — different objects, the
            // directive-0a failure (field report 2026-07-28). Same remedy as
            // DumbbellGlyph / ClockGlyph / SparkleGlyph.
            chipGlyph("Snap", action: { showingSnap = true }) {
                CameraShape().stroke(Theme.textPrimary, lineWidth: 1.7)
                    .frame(width: 22, height: 22)
            }
            chipGlyph("Describe", action: { showingDescribe = true }) {
                ChatBubbleShape().stroke(Theme.textPrimary, lineWidth: 1.7)
                    .frame(width: 22, height: 22)
            }
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
        chipGlyph(label, action: action) {
            Image(systemName: sym(icon))
                .font(.system(size: 20))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    /// Chip whose icon is arbitrary content — the Shape-drawn glyphs that have
    /// no Material equivalent go through here; `chip(_:icon:)` wraps it for the
    /// plain SF-symbol cases.
    private func chipGlyph<Icon: View>(_ label: String,
                                       action: @escaping () -> Void,
                                       @ViewBuilder icon: () -> Icon) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                icon()
                    .frame(height: 22)
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

    /// The shared component, called exactly as `DashboardView` calls it. It
    /// brings its own "TODAY'S MEALS" header (with the trailing "+"), the
    /// tap-to-expand macro chips, the in-row Remove, and iOS's empty state —
    /// the three things the Android re-creation was missing. The meal-type
    /// pill goes with the re-creation: iOS shows none.
    private var mealsCard: some View {
        MealTimelineSection(
            entries: store.foodEntries,
            onAdd: { showingSearch = true },
            onDelete: { id in
                try? AppDatabase.shared.deleteFoodEntry(id: id)
                store.reload()
            }
        )
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
