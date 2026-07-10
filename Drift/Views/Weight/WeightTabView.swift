import SwiftUI
import DriftCore
import Charts

struct WeightTabView: View {
    @Binding var syncComplete: Bool
    @Binding var selectedTab: Int
    @State private var viewModel = WeightViewModel()
    @State private var showingAddWeight = false
    @State private var showingAddBodyComp = false
    @State private var showLog = false
    @State private var showMilestone = false
    @State private var editingEntry: WeightEntry?
    @AppStorage("drift_dismissed_outlier") private var dismissedOutlierDate = ""
    /// Outcome of the empty-state "Sync from Apple Health" attempt — the sync
    /// must never be silent (field report 2026-07-09).
    @State private var syncFeedback: String?

    var body: some View {
        NavigationStack {
            if viewModel.entries.isEmpty {
                emptyState
                    .floatingTabBarClearance()
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        timeRangeBar

                        // Chart — hero element. Was passing the windowed
                        // `viewModel.trend` (only entries inside the
                        // selected time range), which made the chart's
                        // EMA reseed from scratch at the leftmost
                        // entry's raw weight. Real bug from the field:
                        // a user whose long-term trajectory is a steady
                        // loss saw the chart trend UP because the
                        // windowed EMA reset at a low value on the left
                        // and accumulated upward, while the cards
                        // (`fullTrend`-backed) correctly showed losing
                        // — producing the "Difference +1.5 lbs but Est.
                        // Deficit -357 kcal/day" contradiction in the
                        // same view. Chart now uses the same fullTrend
                        // as the insights cards; `rangeStart` scopes
                        // the visible X-axis, and `displayPoints` is
                        // filtered to match so avg / diff / labels
                        // reflect the visible window.
                        WeightChartView(
                            trend: viewModel.fullTrend,
                            unit: viewModel.weightUnit,
                            granularity: viewModel.granularity,
                            rawEntries: viewModel.entries,
                            rangeStart: viewModel.selectedTimeRange.days.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: Date()) }
                        )
                        .frame(height: 340)
                        // Legend moved INTO WeightChartView (#932) so the trend
                        // swatch tracks the goal-aware line colour.

                        // Big change banner
                        bigChangeBanner

                        // Compact metrics + weight changes
                        if let fullTrend = viewModel.fullTrend {
                            WeightInsightsView(trend: fullTrend, unit: viewModel.weightUnit, entries: viewModel.allEntries, isLosing: viewModel.isLosing,
                                              onAddWeight: { showingAddWeight = true },
                                              onAddBodyComp: { showingAddBodyComp = true })
                        }

                        // Collapsible history log
                        logSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .floatingTabBarClearance()
            }
        }
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { selectedTab = 0 } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddWeight = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Add weight")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingAddWeight, onDismiss: {
            viewModel.loadEntries()
        }) {
            let latestComp = WeightServiceAPI.latestBodyComposition()
            WeightEntryView(
                unit: viewModel.weightUnit,
                lastBodyFat: latestComp?.bodyFatPct,
                lastBMI: latestComp?.bmi,
                lastWater: latestComp?.waterPct,
                onSave: { value, date in
                    viewModel.addWeight(value: value, date: date)
                },
                onSaveBodyComp: { comp in
                    var entry = comp
                    WeightServiceAPI.saveBodyComposition(&entry)
                    viewModel.loadEntries()
                }
            )
        }
        .sheet(isPresented: $showingAddBodyComp, onDismiss: { viewModel.loadEntries() }) {
            let latestComp = WeightServiceAPI.latestBodyComposition()
            WeightEntryView(
                unit: viewModel.weightUnit,
                lastBodyFat: latestComp?.bodyFatPct,
                lastBMI: latestComp?.bmi,
                lastWater: latestComp?.waterPct,
                onSave: { value, date in
                    viewModel.addWeight(value: value, date: date)
                },
                onSaveBodyComp: { comp in
                    var entry = comp
                    WeightServiceAPI.saveBodyComposition(&entry)
                    viewModel.loadEntries()
                }
            )
        }
        .onChange(of: viewModel.milestoneMessage) { _, message in
            if message != nil {
                // #premium-polish: single motion spec (the `.animation(value:)`
                // on the overlay drives scale+opacity on Motion.hero) plus a
                // celebratory haptic — the moment was silent and its entrance
                // never played because three animation specs fought.
                Haptics.celebrate()
                showMilestone = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showMilestone = false
                    // Clear the message after the exit animation settles.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        viewModel.milestoneMessage = nil
                    }
                }
            }
        }
        .overlay {
            if showMilestone, let msg = viewModel.milestoneMessage {
                VStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.title2).foregroundStyle(Theme.fatYellow)
                    Text(msg)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
                // V7 milestone-celebration card: was `.ultraThinMaterial`
                // (renders dark on light theme over the chart) — solid
                // ink + white text matches the V7 primary-CTA convention
                // and keeps the celebratory shadow pop intact.
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
                // #premium-polish: the ONE intentional colored shadow, now named
                // (was an ad-hoc coral `.shadow` that read as a random glow).
                .shadowGlow()
                .scaleEffect(showMilestone ? 1.0 : 0.8)
                .opacity(showMilestone ? 1.0 : 0)
                .animation(Theme.Motion.hero, value: showMilestone)
            }
        }
        .onAppear {
            AIScreenTracker.shared.currentScreen = .weight
            // #premium-polish: defer the full-history fetch + trend recompute
            // past the tab-swap frame (TabView keeps this view alive; the chart
            // is already on screen). Removes the hitch on every switch to Body.
            // <30s-fresh data skips entirely; edits/sync still force reload.
            if Date().timeIntervalSince(viewModel.lastLoadedAt) > 30 {
                Task { @MainActor in viewModel.loadEntries() }
            }
        }
        .task {
            #if !targetEnvironment(simulator)
            // HK weight sync only re-runs when stale — it was a fresh
            // anchored query + full reload on every tab re-selection.
            guard Date().timeIntervalSince(viewModel.lastLoadedAt) > 30 else { return }
            let _ = try? await HealthKitService.shared.syncWeight()
            viewModel.loadEntries()
            #endif
        }
        .onChange(of: syncComplete) { _, done in
            if done { viewModel.loadEntries() }
        }
        .sheet(item: $editingEntry) { entry in
            WeightEntryView(unit: viewModel.weightUnit, initialWeight: entry.weightKg, initialDate: entry.date) { value, date in
                viewModel.addWeight(value: value, date: date)
            }
        }
    }

    // MARK: - Big Change Banner

    @ViewBuilder
    private var bigChangeBanner: some View {
        let entries = viewModel.allEntries
        if entries.count >= 2 {
            let latest = entries[0]
            let previous = entries[1]
            let change = latest.weightKg - previous.weightKg
            let pctChange = abs(change) / previous.weightKg
            if pctChange > 0.10 && dismissedOutlierDate != latest.date {
                let unit = viewModel.weightUnit
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.fatYellow)
                        Text("Big change: \(String(format: "%.1f", unit.convert(fromKg: previous.weightKg))) → \(String(format: "%.1f", unit.convert(fromKg: latest.weightKg))) \(unit.displayName)")
                            .font(.caption.weight(.medium))
                    }
                    HStack(spacing: 12) {
                        Button {
                            dismissedOutlierDate = latest.date
                        } label: {
                            Text("That's correct").font(.caption2.weight(.medium))
                        }.buttonStyle(.bordered).tint(Theme.accent)

                        Button {
                            editingEntry = latest
                        } label: {
                            Text("Edit").font(.caption2.weight(.medium))
                        }.buttonStyle(.bordered)

                        Button {
                            if let id = latest.id { viewModel.deleteWeight(id: id) }
                        } label: {
                            Text("Remove").font(.caption2.weight(.medium))
                        }.buttonStyle(.bordered).tint(Theme.surplus)
                    }
                }
                .padding(12)
                .background(Theme.fatYellow.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }

    // MARK: - Time Range Bar

    private var timeRangeBar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(WeightViewModel.TimeRange.allCases, id: \.self) { range in
                    Button {
                        viewModel.selectedTimeRange = range
                        viewModel.loadEntries()
                    } label: {
                        Text(range.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            // V7 chip: selected = solid ink + white text
                            // (high contrast). Was .accent.opacity(0.3) with
                            // .white text — pale coral with white = washed out.
                            .background(viewModel.selectedTimeRange == range ? Theme.ink : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(viewModel.selectedTimeRange == range ? .white : .secondary)
                    }
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Menu {
                    // #940: a Picker renders native checkmark menu rows — the
                    // old Label(_, systemImage: "") with an EMPTY symbol name
                    // is malformed and drew an oversized, clipped menu.
                    Picker("Granularity", selection: Binding(
                        get: { viewModel.granularity },
                        set: { viewModel.granularity = $0 }
                    )) {
                        Text("Daily").tag(WeightViewModel.Granularity.daily)
                        Text("Weekly").tag(WeightViewModel.Granularity.weekly)
                    }
                } label: {
                    // Full word, not a cryptic single letter (design pass).
                    Text(viewModel.granularity == .daily ? "Daily" : "Weekly")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                        .foregroundStyle(Theme.textSecondary)
                }
                .accessibilityLabel(viewModel.granularity == .daily ? "Granularity: Daily" : "Granularity: Weekly")

                // The calorie-overlay flame toggle lived here — removed with
                // the overlay itself (#932, operator-approved removal).

                // V7 polish: per-screen chat icon dropped in favor of
                // the single bottom-right ChatIconButton in
                // ContentView. The brief stint of an inline chat
                // button here (commit fd45503c) is gone.
            }
        }
    }

    // MARK: - Collapsible Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLog.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text("History")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(viewModel.allEntries.count) entries")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(showLog ? 0 : -90))
                }
                .card()
            }
            .buttonStyle(.plain)

            if showLog {
                WeightLogListView(
                    entries: viewModel.allEntries,
                    unit: viewModel.weightUnit,
                    onDelete: { viewModel.deleteWeight(id: $0) },
                    onEdit: { editingEntry = $0 },
                    isLosing: viewModel.isLosing
                )
                .transition(.opacity)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "scalemass.fill")
                .font(.system(size: Theme.FontSize.display3))
                .foregroundStyle(Theme.accent.opacity(0.4))

            VStack(spacing: 6) {
                Text("Track Your Weight")
                    .font(.title3.weight(.semibold))
                Text("Log your first weigh-in or sync from Apple Health to start tracking your progress.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(spacing: 10) {
                Button {
                    Task {
                        // First-sync surface — three fixes (field report
                        // 2026-07-09: "granted permissions, has Health data,
                        // sync does nothing"):
                        // 1. Request authorization HERE — if the launch sheet
                        //    never completed, read is notDetermined and the
                        //    query throws (previously swallowed by try?).
                        // 2. FULL resync (clears the anchor) — an install
                        //    whose first launch-sync raced an ungranted sheet
                        //    saved a poisoned anchor that hides all historical
                        //    samples forever. Empty state ⇒ nothing is
                        //    incremental; full import is always correct here.
                        // 3. Visible outcome either way — silence read as
                        //    "broken".
                        syncFeedback = "Syncing…"
                        do {
                            try await HealthKitService.shared.requestAuthorization()
                            let count = try await HealthKitService.shared.fullResyncWeight()
                            viewModel.loadEntries()
                            syncFeedback = count > 0 ? nil :
                                "No weight data found. If Apple Health has your weight, enable Weight under Settings → Privacy & Security → Health → Drift."
                        } catch {
                            syncFeedback = "Sync failed: \(error.localizedDescription)"
                        }
                    }
                } label: {
                    Label("Sync from Apple Health", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                if let syncFeedback {
                    Text(syncFeedback)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                Button { showingAddWeight = true } label: {
                    Label("Log Weight Manually", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
