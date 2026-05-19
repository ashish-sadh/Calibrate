import SwiftUI
import DriftCore

struct DashboardView: View {
    @Binding var syncComplete: Bool
    @Binding var selectedTab: Int
    @State var viewModel = DashboardViewModel()
    @State var showDeficitExplainer = false
    @AppStorage("drift_ai_enabled") private var aiEnabled = false
    @AppStorage("workout_consistency_dismissed_until") private var workoutConsistencyDismissedUntil: Double = 0
    @State var showingWeightEntry = false
    @State var showingSleepRecovery = false
    @State private var staleBackupDays: Int?
    @State private var showingBackupSettings = false
    @State private var showFeedbackPrompt = false
    @Environment(\.scenePhase) private var scenePhase

    private var isWorkoutConsistencyDismissed: Bool {
        Date().timeIntervalSince1970 < workoutConsistencyDismissedUntil
    }

    /// Recomputes the 7-day Feedback banner visibility from Preferences. Called
    /// on appear, on scene → active (day-boundary crossings during foreground),
    /// and from the 180s `.task` poll (auto-dismiss after day 14 without
    /// requiring the user to leave + revisit the tab). #759.
    private func refreshFeedbackPrompt() {
        let next = Preferences.shouldShowFeedbackPrompt(
            now: Date(),
            installDate: Preferences.installDate,
            hasSeen: Preferences.hasSeenFeedbackPrompt
        )
        if next != showFeedbackPrompt {
            withAnimation { showFeedbackPrompt = next }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Profile nudge (if incomplete)
                    let config = TDEEEstimator.loadConfig()
                    if config.sex == nil || config.age == nil || config.heightCm == nil {
                        NavigationLink { GoalView() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.subheadline).foregroundStyle(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Complete your profile").font(.caption.weight(.medium))
                                    Text("Add age, sex & height for better calorie targets")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }.tint(.primary)
                    }

                    // 7-day Feedback activation banner (#759) — surfaces once
                    // per install between days 7..<14. Main row routes to More
                    // tab (where Report a Bug sits at top); the trailing xmark
                    // dismisses in place. Two side-by-side Buttons so the
                    // xmark hit-target can't bleed into the engage action.
                    if showFeedbackPrompt {
                        HStack(spacing: 4) {
                            Button {
                                Preferences.hasSeenFeedbackPrompt = true
                                showFeedbackPrompt = false
                                selectedTab = 4
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "hand.wave.fill")
                                        .font(.subheadline).foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("How's it going?")
                                            .font(.caption.weight(.medium))
                                        Text("Tap to send a quick note")
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("How's it going? Tap to send a quick note")

                            Button {
                                Preferences.hasSeenFeedbackPrompt = true
                                withAnimation { showFeedbackPrompt = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .padding(8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss feedback prompt")
                        }
                        .padding(10)
                        .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Stale-backup banner (#561) — appears when last successful
                    // iCloud backup is older than 3 days. Tap routes to Backup
                    // settings.
                    if let days = staleBackupDays {
                        Button {
                            showingBackupSettings = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "icloud.slash")
                                    .font(.subheadline).foregroundStyle(Theme.surplus)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Last backed up \(days) days ago")
                                        .font(.caption.weight(.medium))
                                    Text("Tap to fix")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(Theme.surplus.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }.tint(.primary)
                    }

                    // Privacy banner
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.deficit)
                        Text("All data stays on your device.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)

                    // ── Today ──
                    // Nutrition hero (macro rings) → Food tab
                    Button { selectedTab = 2 } label: { calorieBalanceCard }.buttonStyle(.plain)

                    // V6 quick-log row — Snap · Voice · Search · Recent.
                    // Per v6-today.jsx anatomy, this sits between the hero and
                    // the Body section; always visible regardless of whether
                    // food was logged so first-time users have 4 clear entry
                    // points into logging.
                    V6QuickLogRow(selectedTab: $selectedTab, aiEnabled: $aiEnabled)

                    // V6 meals timeline — fixed 4-slot Breakfast/Lunch/Dinner
                    // /Snacks per v6-today.jsx anatomy step 4. Replaces the
                    // legacy "No food logged today" muted state that used to
                    // live inside calorieBalanceCard. Tap routes to the Food
                    // tab where edit-meal / add-meal flows are owned today.
                    sectionHeader("Today's meals")
                    V6MealTimeline(
                        slots: V6MealTimeline.payloads(from: viewModel.todayFoodEntries)
                    ) { _ in
                        selectedTab = 2
                    }

                    // ── Body ──
                    sectionHeader("Body")

                    // V6 Body tile row — Weight + Sleep + Readiness. Per
                    // v6-today.jsx anatomy step 5, three small tiles replace
                    // the legacy full-width Weight+Trend card so the user
                    // sees current weight, last-night sleep, and recovery at
                    // a glance. Detail entry points are unchanged: Weight tap
                    // opens the entry sheet (with "+" inline log button),
                    // Sleep / Readiness route into SleepRecoveryView.
                    v6BodyTileRow

                    // Proactive alerts — urgent, actionable
                    if !viewModel.proactiveAlerts.isEmpty {
                        ForEach(viewModel.proactiveAlerts) { alert in
                            HStack(spacing: 10) {
                                Image(systemName: alert.icon)
                                    .font(.body)
                                    .foregroundStyle(Theme.fatYellow)
                                    .frame(width: 32, height: 32)
                                    .background(Theme.fatYellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alert.title).font(.caption.weight(.semibold))
                                    Text(alert.detail).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let key = alert.dismissKey {
                                    Button {
                                        withAnimation { viewModel.dismissProactiveAlert(key: key) }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .accessibilityLabel("Dismiss alert")
                                }
                            }.card()
                        }
                    }

                    // Goal progress → Goal page
                    NavigationLink { GoalView() } label: { goalCard }.tint(.primary)

                    // TDEE → Algorithm settings
                    NavigationLink { AlgorithmSettingsView() } label: { tdeeCard }.tint(.primary)

                    // ── Activity ──
                    sectionHeader("Activity")

                    // Active/Steps → Exercise tab
                    Button { selectedTab = 3 } label: { healthRow }.buttonStyle(.plain)

                    // Apple Health Workouts — show if any today
                    if !viewModel.todayWorkouts.isEmpty {
                        Button { selectedTab = 3 } label: { workoutCard }.buttonStyle(.plain)
                    }

                    // Weekly workout consistency card
                    if let insight = viewModel.workoutConsistencyInsight, !isWorkoutConsistencyDismissed {
                        WorkoutConsistencyCard(insight: insight) {
                            workoutConsistencyDismissedUntil = Date().addingTimeInterval(86400).timeIntervalSince1970
                        }
                    }

                    // ── Recovery ──
                    sectionHeader("Recovery")

                    // Body Rhythm → SleepRecoveryView
                    NavigationLink { SleepRecoveryView() } label: { sleepRecoveryCard }

                    // Supplements — show if any configured
                    if viewModel.supplementsTotal > 0 {
                        NavigationLink { SupplementsTabView() } label: { supplementCard }
                    }

                    // Behavior Insights
                    if !viewModel.behaviorInsights.isEmpty {
                        sectionHeader("Insights")
                        insightsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        Image(systemName: "d.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                        Text("Drift")
                            .font(.headline.weight(.bold))
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if DeviceCapability.canRunAI {
                        Button { aiEnabled.toggle() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles").font(.system(size: 10))
                                Text("beta").font(.system(size: 8, weight: .semibold))
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(aiEnabled ? Theme.accent : Theme.textTertiary)
                                    .frame(width: 28, height: 16)
                                    .overlay(alignment: aiEnabled ? .trailing : .leading) {
                                        Circle().fill(Theme.textPrimary).frame(width: 12, height: 12)
                                            .padding(.horizontal, 2)
                                    }
                                    .animation(.easeInOut(duration: 0.15), value: aiEnabled)
                            }
                            .foregroundStyle(aiEnabled ? Theme.accent : .secondary)
                        }
                        .accessibilityLabel("AI beta, \(aiEnabled ? "on" : "off")")
                        .accessibilityHint("Double tap to toggle")
                    }
                }
            }
            .onAppear {
                AIScreenTracker.shared.currentScreen = .dashboard
                Task { await viewModel.loadToday() }
                refreshFeedbackPrompt()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refreshFeedbackPrompt() }
            }
            .task {
                await viewModel.loadToday()
                // Auto-refresh every 3 minutes
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(180))
                    await viewModel.loadToday()
                    refreshFeedbackPrompt()
                }
            }
            .refreshable { await viewModel.loadToday() }
            .onChange(of: syncComplete) { _, done in
                if done { Task { await viewModel.loadToday() } }
            }
            .sheet(isPresented: $showingWeightEntry, onDismiss: {
                Task { await viewModel.loadToday() }
            }) {
                let latestComp = WeightServiceAPI.latestBodyComposition()
                WeightEntryView(
                    unit: Preferences.weightUnit,
                    lastBodyFat: latestComp?.bodyFatPct,
                    lastBMI: latestComp?.bmi,
                    lastWater: latestComp?.waterPct,
                    onSave: { value, date in
                        let kg = Preferences.weightUnit == .kg ? value : value / 2.20462
                        let dateStr = DateFormatters.dateOnly.string(from: date)
                        var entry = WeightEntry(date: dateStr, weightKg: kg, source: "manual")
                        WeightServiceAPI.saveWeightEntry(&entry)
                        WeightTrendService.shared.refresh()
                    },
                    onSaveBodyComp: { comp in
                        var c = comp
                        WeightServiceAPI.saveBodyComposition(&c)
                    }
                )
            }
            .sheet(isPresented: $showingBackupSettings) {
                NavigationStack { BackupSettingsView() }
            }
            .navigationDestination(isPresented: $showingSleepRecovery) {
                SleepRecoveryView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .backupStaleBanner)) { note in
                staleBackupDays = note.userInfo?["daysSinceBackup"] as? Int
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Apple Health Workouts

    private var workoutCard: some View {
        let workouts = viewModel.todayWorkouts
        let totalCal = Int(workouts.reduce(0) { $0 + $1.calories })
        let latest = workouts.first

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "flame.circle.fill").foregroundStyle(Theme.stepsOrange)
                Text("Workouts").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.stepsOrange)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }

            if let w = latest {
                Text("You burned \(totalCal) calories during \(workouts.count == 1 ? "your last workout" : "\(workouts.count) workouts").")
                    .font(.caption).foregroundStyle(.secondary)

                ForEach(workouts.prefix(3)) { w in
                    HStack(spacing: 10) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.title3).foregroundStyle(Theme.stepsOrange)
                            .frame(width: 36, height: 36)
                            .background(Theme.stepsOrange.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(w.type).font(.caption.weight(.semibold))
                            HStack(spacing: 8) {
                                Text(w.durationDisplay).font(.caption2.monospacedDigit())
                                Text("\(Int(w.calories)) cal").font(.caption2.monospacedDigit())
                            }
                            .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Health

    private var healthRow: some View {
        HStack(spacing: 12) {
            healthPill(icon: "flame.fill", value: "\(Int(viewModel.activeCalories))", label: "Active", color: Theme.stepsOrange)
            healthPill(icon: "figure.walk", value: formatSteps(viewModel.steps), label: "Steps", color: Theme.deficit)
        }
    }

    private func healthPill(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    private func formatSteps(_ steps: Double) -> String {
        if steps >= 1000 {
            return String(format: "%.1fk", steps / 1000)
        }
        return "\(Int(steps))"
    }

    // MARK: - Goal

    private var goalCard: some View {
        Group {
            if let goal = WeightGoal.load(), let current = viewModel.latestWeight ?? viewModel.trendWeight {
                NavigationLink {
                    GoalView()
                } label: {
                    GoalProgressCard(goal: goal, currentWeightKg: current, trendWeightKg: viewModel.trendWeight)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "target")
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No weight goal set")
                            .font(.subheadline).foregroundStyle(.tertiary)
                        Text("Set a goal to see calorie targets and track progress")
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                    Spacer()
                }
                .card()
            }
        }
    }

    // MARK: - Supplements

    // MARK: - Sleep & Recovery

    private var sleepRecoveryCard: some View {
        let hasData = viewModel.sleepHours > 0 || viewModel.recoveryScore > 0 || viewModel.hrvMs > 0 || viewModel.restingHR > 0

        return VStack(spacing: 8) {
            if hasData {
                // Recovery + Sleep scores
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recovery").font(.caption).foregroundStyle(.secondary)
                        Text("\(viewModel.recoveryScore)")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(Theme.scoreColor(viewModel.recoveryScore))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2).fill(Theme.cardBackgroundElevated).frame(height: 4)
                                RoundedRectangle(cornerRadius: 2).fill(Theme.scoreColor(viewModel.recoveryScore))
                                    .frame(width: geo.size.width * Double(viewModel.recoveryScore) / 100, height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sleep").font(.caption).foregroundStyle(.secondary)
                        Text(viewModel.sleepHours > 0 ? String(format: "%.1fh", viewModel.sleepHours) : "--")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(viewModel.sleepHours > 0 ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    if viewModel.hrvMs > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "waveform.path").font(.caption).foregroundStyle(Theme.deficit)
                            Text("\(Int(viewModel.hrvMs))ms").font(.caption2.monospacedDigit())
                        }
                    }
                    if viewModel.restingHR > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.heartRed)
                            Text("\(Int(viewModel.restingHR))bpm").font(.caption2.monospacedDigit())
                        }
                    }
                    Spacer()
                    Text("Last night").font(.caption2).foregroundStyle(.quaternary)
                }
                .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path")
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Body Rhythm")
                            .font(.subheadline).foregroundStyle(.tertiary)
                        Text("Sleep, recovery, and vitals from Apple Health")
                            .font(.caption2).foregroundStyle(.quaternary)
                    }
                    Spacer()
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hasData
            ? "Recovery \(viewModel.recoveryScore) percent, Sleep \(viewModel.sleepHours > 0 ? String(format: "%.1f hours", viewModel.sleepHours) : "no data")"
            : "Body Rhythm: no data from Apple Health")
    }

    // MARK: - Supplements

    private var supplementCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "pill.fill")
                .foregroundStyle(Theme.supplementMint)
            Text("Supplements")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("\(viewModel.supplementsTaken)/\(viewModel.supplementsTotal)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(viewModel.supplementsTaken == viewModel.supplementsTotal ? Theme.deficit : .secondary)
            Text("taken")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    // MARK: - Behavior Insights Card

    private var insightsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption).foregroundStyle(Theme.fatYellow)
                Text("Insights").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
            }
            ForEach(viewModel.behaviorInsights) { insight in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: insight.icon)
                        .font(.caption)
                        .foregroundStyle(insight.isPositive ? Theme.deficit : Theme.surplus)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.caption.weight(.semibold))
                        Text(insight.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
        }
        .card()
    }
}
