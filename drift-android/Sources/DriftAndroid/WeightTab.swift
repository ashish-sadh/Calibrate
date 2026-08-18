import SwiftUI
import Observation
import SkipFuse
import DriftCore

// MARK: - Rows

struct WeightStats: Sendable {
    var current: String = "—"
    var trend: String = ""
    var change7d: String?
    var change30d: String?
}

/// Mirrors `WeightViewModel.TimeRange` (iOS) — the Android chart re-windows
/// in-memory over this instead of iOS's chartScrollableAxes pan (#1092 plan).
enum WeightChartRange: String, CaseIterable {
    case oneWeek = "1W", oneMonth = "1M", threeMonths = "3M", sixMonths = "6M", oneYear = "1Y", all = "All"

    var days: Int? {
        switch self {
        case .oneWeek: 7
        case .oneMonth: 30
        case .threeMonths: 90
        case .sixMonths: 180
        case .oneYear: 365
        case .all: nil
        }
    }
}

/// Mirrors `WeightViewModel.Granularity`. iOS presents it as a Menu+Picker;
/// Picker-inside-Menu is unproven on Fuse, so Android uses two chips in the
/// existing range-chip idiom — same two choices, same effect on the series.
enum WeightGranularity: String, CaseIterable {
    case daily = "Daily", weekly = "Weekly"
}

// MARK: - Store

@MainActor @Observable public class WeightStore {
    /// Shared for the same reason as `TodayStore.shared` — see that comment.
    static let shared = WeightStore()

    var stats = WeightStats()
    /// Raw history, newest first — rendered by the single-sourced
    /// `WeightLogListView` (month groups, medians, change arrows).
    var history: [WeightEntry] = []
    /// Full-history series for `WeightChartAndroid` at the current granularity;
    /// the range chips filter this in-memory rather than refetching (#1092).
    var allDailyPoints: [WeightChartSeries.Point] = []
    var goalChangeKg: Double?
    var unit: WeightUnit = .kg
    /// Goal direction, for the history rows' goal-aware change colours.
    var isLosing: Bool = true
    /// "New Low!" / "New High!" — cleared by the tab after the overlay plays.
    var milestoneMessage: String?
    /// False until the first reload lands, so the empty state can't flash
    /// during DB warm-up (the Android read crosses JNI and is not instant).
    var loaded = false
    var granularity: WeightGranularity = .daily {
        didSet { rebuildSeries() }
    }

    /// Calculator output kept so a granularity flip re-aggregates without a
    /// refetch or a per-frame recompute.
    private var trendPoints: [WeightTrendCalculator.WeightDataPoint] = []

    /// Loads once when `shared` is first touched — see FoodStore.init.
    init() { reload() }

    func reload() {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            let unit = Preferences.weightUnit
            self.unit = unit
            // 365 → AppDatabase.fetchWeightEntries' full history (see the
            // days >= 365 branch in WeightServiceAPI.getHistory) so the "All"
            // range and a continuous EMA work — the chart needs the whole
            // trajectory even when the stats header/log list only show recent.
            let history = WeightServiceAPI.getHistory(days: 365).sorted { $0.date > $1.date }
            self.history = history
            var s = WeightStats()
            if let latest = history.first {
                s.current = Self.format(kg: latest.weightKg, unit: unit)
                s.change7d = Self.change(history: history, days: 7, unit: unit)
                s.change30d = Self.change(history: history, days: 30, unit: unit)
            }
            // The trend line needs a few days of data — next to a real current
            // value, "No weight data yet." reads as a bug, so suppress it.
            // describeTrend() ALSO returns that copy itself when the entries
            // span too few days, so filter the sentinel, not just the count.
            let trend = history.count >= 2 ? WeightServiceAPI.describeTrend() : ""
            s.trend = trend.hasPrefix("No weight data") ? "" : trend
            stats = s

            // Chart series — calculateTrend sorts its input itself, so
            // history's (descending) order here doesn't matter.
            let fullTrend = WeightTrendCalculator.calculateTrend(
                entries: history.map { (date: $0.date, weightKg: $0.weightKg) })
            trendPoints = fullTrend?.dataPoints ?? []
            rebuildSeries()
            if let goal = WeightGoal.load() {
                goalChangeKg = goal.totalChangeKg
                isLosing = goal.isLosing(
                    currentWeightKg: WeightTrendService.shared.latestWeightKg ?? goal.startWeightKg)
            } else {
                goalChangeKg = nil
                isLosing = true
            }
            loaded = true
        }
    }

    private func rebuildSeries() {
        allDailyPoints = granularity == .weekly
            ? WeightChartSeries.weekly(trendPoints, unit: unit)
            : WeightChartSeries.daily(trendPoints, unit: unit)
    }

    private static func format(kg: Double, unit: WeightUnit) -> String {
        String(format: "%.1f %@", unit.convert(fromKg: kg), unit.displayName)
    }

    private static func change(history: [WeightEntry], days: Int, unit: WeightUnit) -> String? {
        guard let latest = history.first else { return nil }
        let cutoff = DateFormatters.dateOnly.string(
            from: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        guard let past = history.last(where: { $0.date >= cutoff }), past.id != latest.id else { return nil }
        let value = unit.convert(fromKg: latest.weightKg - past.weightKg)
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.1f", value)) \(unit.displayName)"
    }

    /// Mirrors `WeightViewModel.addWeight(value:date:)` — same unit handling,
    /// same milestone rule (`WeightMilestone`, Tier-0 tested), same upsert.
    /// Editing an existing weigh-in comes through here too: `saveWeightEntry`
    /// upserts by date, exactly as iOS does.
    func addWeight(value: Double, date: Date) {
        // Read the unit at log time, never from a snapshot: a Settings change
        // between process start and now must decide how this value is stored (#1088).
        let unit = Preferences.weightUnit
        let kg = unit.convertToKg(value)
        FeatureUsage.record(TelemetryEvent.weightLogged)
        // Milestone compares against the history BEFORE this entry is saved.
        milestoneMessage = WeightMilestone.message(newWeightKg: kg,
                                                   existingWeightsKg: history.map(\.weightKg),
                                                   isLosing: isLosing, unit: unit)
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            var entry = WeightEntry(date: DateFormatters.dateOnly.string(from: date),
                                    weightKg: kg, source: "manual")
            try? AppDatabase.shared.saveWeightEntry(&entry)
            reload()
            // The dashboard's WEIGHT card reads its own store — without this
            // it kept showing the pre-log value until relaunch (#1090 sweep).
            TodayStore.shared.reload()
        }
    }

    func saveBodyComposition(_ comp: BodyComposition) {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            var entry = comp
            WeightServiceAPI.saveBodyComposition(&entry)
            reload()
        }
    }

    func delete(id: Int64) {
        Task {
            try? AppDatabase.shared.deleteWeightEntry(id: id)
            reload()
            TodayStore.shared.reload()
        }
    }
}

/// One presentation modifier drives both the add and the edit sheet — two
/// `.sheet`s on one view is the Fuse trap `ProgressGalleryAndroid` already ate.
/// The last body composition is captured at TAP time, never inside the sheet
/// builder: Fuse builds sheet content eagerly, so an in-builder DB read (iOS's
/// shape) would run on every render of the tab.
struct WeightSheetRequest: Identifiable {
    let id: String
    let entry: WeightEntry?
    let unit: WeightUnit
    let lastComp: BodyComposition?
}

// MARK: - Weight tab

struct WeightTab: View {
    @State var store = WeightStore.shared
    @State var activeSheet: WeightSheetRequest?
    @State var range: WeightChartRange = .threeMonths
    @State var showLog = false
    @State var showMilestone = false
    @State var syncFeedback: String?

    /// In-memory re-window — no DB refetch on chip tap (#1092 plan).
    private var displayPoints: [WeightChartSeries.Point] {
        guard let days = range.days,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else {
            return store.allDailyPoints
        }
        return store.allDailyPoints.filter { $0.date >= cutoff }
    }

    /// The latest weigh-in when it differs >10% from the one before it — iOS's
    /// `bigChangeBanner` guard, same threshold, same dismissal key.
    private var outlier: (latest: WeightEntry, previous: WeightEntry)? {
        guard store.history.count >= 2 else { return nil }
        let latest = store.history[0]
        let previous = store.history[1]
        guard previous.weightKg > 0 else { return nil }
        let pctChange = abs(latest.weightKg - previous.weightKg) / previous.weightKg
        guard pctChange > 0.10, Preferences.dismissedOutlierDate != latest.date else { return nil }
        return (latest, previous)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.history.isEmpty {
                    // Nothing to draw until the first read lands — showing the
                    // empty state during warm-up would flash "Track Your Weight"
                    // at a user who has 200 weigh-ins.
                    if store.loaded { emptyState } else { Color.clear }
                } else {
                    weightScroll
                }
            }
            .background(Theme.background.ignoresSafeArea())
            // iOS draws NO title on this screen (the Body tab's nav bar is
            // empty); a large "Weight" header is Android-only chrome.
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { store.reload() }
            .sheet(item: $activeSheet) { request in
                WeightEntryView(
                    unit: request.unit,
                    initialWeight: request.entry?.weightKg,
                    initialDate: request.entry?.date,
                    lastBodyFat: request.lastComp?.bodyFatPct,
                    lastBMI: request.lastComp?.bmi,
                    lastWater: request.lastComp?.waterPct,
                    onSave: { value, date in store.addWeight(value: value, date: date) },
                    onSaveBodyComp: { comp in store.saveBodyComposition(comp) }
                )
            }
            .onChange(of: store.milestoneMessage) { _, message in
                guard message != nil else { return }
                showMilestone = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showMilestone = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        store.milestoneMessage = nil
                    }
                }
            }
            // Haptics is an iOS app-target type; the bridged sensory feedback
            // modifier is the Fuse-side equivalent of Haptics.celebrate().
            // Closure form so only the ENTRANCE buzzes — the plain
            // `trigger:` overload also fires when the overlay hides.
            // Needs android.permission.VIBRATE in the manifest: SkipUI calls
            // Vibrator.vibrate() unguarded, and without the permission this is
            // a fatal SecurityException rather than a silent no-op.
            .sensoryFeedback(trigger: showMilestone) { _, isShowing in
                isShowing ? .success : nil
            }
            .overlay {
                if showMilestone, let msg = store.milestoneMessage {
                    milestoneCard(msg)
                }
            }
        }
    }

    private var weightScroll: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Stats header
                VStack(alignment: .leading, spacing: 10) {
                    Text("CURRENT").sectionHeading()
                    Text(store.stats.current)
                        .font(Theme.rounded(size: Theme.FontSize.display1).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    if !store.stats.trend.isEmpty {
                        Text(store.stats.trend)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    HStack(spacing: 12) {
                        if let change = store.stats.change7d {
                            changeChip("7d", change)
                        }
                        if let change = store.stats.change30d {
                            changeChip("30d", change)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                Button { presentSheet(editing: nil) } label: {
                    Label("Log Weight", systemImage: sym("plus.circle.fill"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous))
                }.buttonStyle(.plain)

                bigChangeBanner

                // Chart shows from the FIRST weigh-in, matching iOS
                // (WeightTabView gates on entries.isEmpty only). The old
                // >= 2 gate left a new user with no graph at all — and
                // with the outlier filter having eaten one of two honest
                // entries, it hid the chart even at two (2026-07-28).
                if !store.allDailyPoints.isEmpty {
                    rangePicker
                    if !displayPoints.isEmpty {
                        WeightChartAndroid(points: displayPoints, unit: store.unit,
                                           goalChangeKg: store.goalChangeKg,
                                           isWeekly: store.granularity == .weekly)
                    }
                }

                logSection
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
        }
    }

    // MARK: - Big change banner (port of WeightTabView.bigChangeBanner)

    @ViewBuilder
    private var bigChangeBanner: some View {
        if let outlier {
            let unit = store.unit
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    // The warning triangle is the INTENDED glyph here.
                    Image(systemName: sym("exclamationmark.triangle.fill")).foregroundStyle(Theme.fatYellow)
                    Text("Big change: \(String(format: "%.1f", unit.convert(fromKg: outlier.previous.weightKg))) → \(String(format: "%.1f", unit.convert(fromKg: outlier.latest.weightKg))) \(unit.displayName)")
                        .font(.caption.weight(.medium))
                }
                HStack(spacing: 12) {
                    Button {
                        // Durable on Android: a raw @AppStorage write would not
                        // survive process death (#1108).
                        Preferences.dismissedOutlierDate = outlier.latest.date
                        store.reload()
                    } label: {
                        Text("That's correct").font(.caption2.weight(.medium))
                    }.buttonStyle(.bordered).tint(Theme.accent)

                    Button {
                        presentSheet(editing: outlier.latest)
                    } label: {
                        Text("Edit").font(.caption2.weight(.medium))
                    }.buttonStyle(.bordered)

                    Button {
                        if let id = outlier.latest.id { store.delete(id: id) }
                    } label: {
                        Text("Remove").font(.caption2.weight(.medium))
                    }.buttonStyle(.bordered).tint(Theme.surplus)
                }
            }
            .padding(12)
            .background(Theme.fatYellow.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
        }
    }

    // MARK: - Collapsible history (port of WeightTabView.logSection)

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLog.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: sym("clock.arrow.circlepath"))
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text("History")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(store.history.count) entries")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Image(systemName: sym("chevron.down"))
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(showLog ? 0 : -90))
                }
                .card()
            }
            .buttonStyle(.plain)

            if showLog {
                WeightLogListView(
                    entries: store.history,
                    unit: store.unit,
                    onDelete: { store.delete(id: $0) },
                    onEdit: { presentSheet(editing: $0) },
                    isLosing: store.isLosing
                )
            }
        }
    }

    // MARK: - Milestone (port of WeightTabView's overlay)

    private func milestoneCard(_ msg: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: sym("star.fill"))
                .font(.title2).foregroundStyle(Theme.fatYellow)
            Text(msg)
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 28).padding(.vertical, 16)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
        .shadowGlow()
        .scaleEffect(showMilestone ? 1.0 : 0.8)
        .opacity(showMilestone ? 1.0 : 0)
        .animation(Theme.Motion.hero, value: showMilestone)
    }

    // MARK: - Empty state (port of WeightTabView.emptyState)

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            // No scale glyph exists in skip-ui 1.58's ~46-symbol map (and
            // sym("scalemass") targets a 1.59-only name), so the tab draws the
            // chart mark the rest of the app already uses for weight.
            BarChartShape()
                .fill(Theme.accent.opacity(0.4))
                .frame(width: 56, height: 56)

            VStack(spacing: 6) {
                Text("Track Your Weight")
                    .font(.title3.weight(.semibold))
                Text(healthSyncAvailable
                     ? "Log your first weigh-in or sync from Health Connect to start tracking your progress."
                     : "Log your first weigh-in to start tracking your progress.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(spacing: 10) {
                if healthSyncAvailable {
                    Button {
                        Task { await syncFromHealthConnect() }
                    } label: {
                        Label("Sync from Health Connect", systemImage: sym("heart.fill"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }

                if let syncFeedback {
                    Text(syncFeedback)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button { presentSheet(editing: nil) } label: {
                    Label("Log Weight Manually", systemImage: sym("plus"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    /// Hide the sync CTA rather than show a button that can't work — the seam
    /// is registered but Health Connect itself may be absent on the device.
    private var healthSyncAvailable: Bool {
        DriftPlatform.health?.isAvailable == true
    }

    /// iOS's three-fix first-sync flow (field report 2026-07-09), with Health
    /// Connect's permission story instead of Apple Health's: ask HERE (the
    /// launch sheet may never have completed), FULL resync (an empty state
    /// means nothing is incremental), and a visible outcome either way.
    private func syncFromHealthConnect() async {
        syncFeedback = "Syncing…"
        do {
            let health = HealthConnectService.shared
            // #1207: wait for the real permission answer — `requestAuthorization()`
            // returns while the grant sheet is still up, so the resync below
            // used to read permissions the user hadn't granted yet and import
            // nothing on the first tap.
            _ = await health.requestAuthorizationInteractive()
            let count = try await health.fullResyncWeight()
            store.reload()
            syncFeedback = count > 0 ? nil :
                "No weight data found. If Health Connect has your weight, grant Drift the Weight permission in Health Connect → App permissions."
        } catch {
            syncFeedback = "Sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Chrome

    private var rangePicker: some View {
        HStack(spacing: 0) {
            ForEach(WeightChartRange.allCases, id: \.self) { r in
                Button {
                    range = r
                } label: {
                    Text(r.rawValue)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        // iOS timeRangeBar: selected = solid ink + white text.
                        .background(range == r ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(range == r ? .white : Theme.textSecondary)
                }.buttonStyle(.plain)
            }
            Spacer()
            ForEach(WeightGranularity.allCases, id: \.self) { g in
                Button {
                    store.granularity = g
                } label: {
                    Text(g.rawValue)
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(store.granularity == g ? Theme.cardBackgroundElevated : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(store.granularity == g ? Theme.textPrimary : Theme.textSecondary)
                }.buttonStyle(.plain)
            }
        }
    }

    private func changeChip(_ label: String, _ change: String) -> some View {
        // Goal-aware: default goal is losing weight — down = green.
        let isDown = change.hasPrefix("-")
        return HStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            Text(change)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isDown ? Theme.deficit : Theme.surplus)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.pillBackground, in: Capsule())
    }

    /// `latestBodyComposition()` is read here, on the tap, and handed to the
    /// sheet — never read inside the sheet builder (Fuse builds those eagerly).
    private func presentSheet(editing entry: WeightEntry?) {
        Task {
            await CoreResourcesBootstrap.warmUpDatabase()
            let comp = WeightServiceAPI.latestBodyComposition()
            activeSheet = WeightSheetRequest(
                id: entry?.id.map { String($0) } ?? "add",
                entry: entry,
                unit: Preferences.weightUnit,
                lastComp: comp)
        }
    }
}
