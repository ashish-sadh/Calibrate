import SwiftUI
import DriftCore

struct MoreTabView: View {
    @Binding var selectedTab: Int
    @State private var navId = UUID()
    @State private var hasCycleData = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    section("ACTIVITY") {
                        navRow(icon: "dumbbell.fill", title: "Exercise",
                               subtitle: "Strength, cardio, mobility",
                               color: Theme.macroKcal) {
                            WorkoutView(selectedTab: $selectedTab)
                        }
                        rowDivider
                        navRow(icon: "camera.viewfinder", title: "Photo Log",
                               subtitle: "Snap a meal · BYOK cloud AI",
                               color: Theme.macroFiber) {
                            PhotoLogBetaSettingsView()
                        }
                    }

                    section("HEALTH") {
                        navRow(icon: "waveform.path", title: "Body Rhythm",
                               subtitle: "Sleep, vitals, recovery",
                               color: Theme.rhythmTeal) {
                            SleepRecoveryView()
                        }
                        if hasCycleData {
                            rowDivider
                            navRow(icon: "circle.circle", title: "Cycle",
                                   subtitle: "From Apple Health",
                                   color: Theme.cyclePink) {
                                CycleView()
                            }
                        }
                        rowDivider
                        navRow(icon: "pill.fill", title: "Supplements",
                               subtitle: "Daily checklist",
                               color: Theme.macroProtein) {
                            SupplementsTabView()
                        }
                        rowDivider
                        navRow(icon: "figure.stand", title: "Body Composition",
                               subtitle: "DEXA scan data",
                               color: Theme.macroKcal) {
                            DEXAOverviewView()
                        }
                        rowDivider
                        navRow(icon: "waveform.path.ecg", title: "Glucose",
                               subtitle: "CGM tracking",
                               color: Theme.macroFiber) {
                            GlucoseTabView()
                        }
                        rowDivider
                        navRow(icon: "cross.case.fill", title: "Biomarkers",
                               subtitle: "Blood test results & trends",
                               color: Theme.macroCarbs) {
                            BiomarkersTabView()
                        }
                    }

                    section("APP") {
                        navRow(icon: "target", title: "Weight Goal",
                               subtitle: "Target weight, timeline, plan",
                               color: Theme.macroFat) {
                            GoalView()
                        }
                        rowDivider
                        navRow(icon: "gear", title: "Settings",
                               subtitle: "Units · sync · export",
                               color: Theme.textTertiary) {
                            SettingsView()
                        }
                    }

                    VStack(spacing: 6) {
                        Link(destination: URL(string: "https://ashish-sadh.github.io/Drift/")!) {
                            Text("Report a bug")
                                .font(.caption2)
                                .foregroundStyle(Theme.textTertiary)
                                .underline()
                        }
                        Text("Drift · v\(versionString) · \(yearString)")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("More")
            .toolbarColorScheme(.light, for: .navigationBar)
            .task { hasCycleData = await HealthKitService.shared.hasCycleData() }
        }
        .id(navId)
        .onChange(of: selectedTab) { oldTab, newTab in
            if oldTab == 4 && newTab != 4 { navId = UUID() }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.8)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .card()
        }
    }

    private var rowDivider: some View {
        Divider().overlay(Theme.separator).padding(.leading, 50)
    }

    private func navRow<Dest: View>(icon: String, title: String, subtitle: String, color: Color, @ViewBuilder destination: () -> Dest) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    private var yearString: String {
        String(Calendar.current.component(.year, from: Date()))
    }
}

struct SettingsView: View {
    @State private var weightUnit: WeightUnit = Preferences.weightUnit
    @State private var showingFactoryReset = false
    @State private var resetDone = false
    @State private var isRefreshingFoods = false
    @State private var foodsRefreshError: String? = nil
    @State private var refreshedFoodCount: Int? = nil
    @State private var syncStatus: String?
    @State private var telemetryEnabled: Bool = Preferences.chatTelemetryEnabled
    @State private var telemetryCount: Int = 0
    @State private var showingTelemetryDeleteConfirm = false
    @State private var showingTelemetryEnableConfirm = false
    @State private var telemetryShareURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Body Weight Unit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Body Weight Unit", selection: $weightUnit) {
                        Text("kg").tag(WeightUnit.kg)
                        Text("lbs").tag(WeightUnit.lbs)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: weightUnit) { _, v in Preferences.weightUnit = v }
                    Text("Affects body weight tracking only. Exercise weights are always shown in lbs.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Apple Health")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button {
                        Task {
                            do {
                                try await HealthKitService.shared.requestAuthorization()
                                syncStatus = "Health access granted"
                            } catch {
                                syncStatus = "Access denied: \(error.localizedDescription)"
                            }
                            clearStatus()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: "heart.fill").foregroundStyle(Theme.heartRed)
                                Text("Request Health Access")
                                Spacer()
                            }
                            Text("Grant permission to read weight, sleep, vitals, and activity")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }

                    Button {
                        Task {
                            do {
                                let count = try await HealthKitService.shared.syncWeight()
                                syncStatus = "Synced \(count) weight entries"
                            } catch {
                                syncStatus = "Sync failed: \(error.localizedDescription)"
                            }
                            clearStatus()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.accent)
                                Text("Sync Weight")
                                Spacer()
                            }
                            Text("Import new weight data from Apple Health")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }

                    Button {
                        Task {
                            do {
                                let count = try await HealthKitService.shared.fullResyncWeight()
                                syncStatus = "Re-synced \(count) entries from all history"
                            } catch {
                                syncStatus = "Re-sync failed: \(error.localizedDescription)"
                            }
                            clearStatus()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Image(systemName: "arrow.clockwise").foregroundStyle(.orange)
                                Text("Full Re-sync")
                                Spacer()
                            }
                            Text("Clear sync history and re-import all weight data")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }

                    if let status = syncStatus {
                        Text(status).font(.caption).foregroundStyle(Theme.accent)
                            .transition(.opacity)
                    }
                }
                .card()

                // iCloud Backup
                NavigationLink {
                    BackupSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud Backup").font(.subheadline.weight(.medium))
                            Text("Daily snapshot of your data to iCloud Drive")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .card()

                // Export
                VStack(alignment: .leading, spacing: 10) {
                    Text("Export Data")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Button {
                        if let url = exportWorkoutsCSV() {
                            shareFile(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "dumbbell.fill").foregroundStyle(Theme.accent)
                            Text("Export Workouts (CSV)")
                            Spacer()
                        }
                    }

                    Button {
                        if let url = exportFoodLogsCSV() {
                            shareFile(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "fork.knife").foregroundStyle(Theme.accent)
                            Text("Export Food Logs (CSV)")
                            Spacer()
                        }
                    }
                }
                .card()

                // Online Food Search
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Online Food Search").font(.subheadline.weight(.medium))
                            Text("Search USDA & Open Food Facts when local results are limited")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { Preferences.onlineFoodSearchEnabled },
                            set: { Preferences.onlineFoodSearchEnabled = $0 }
                        ))
                        .labelsHidden().tint(Theme.accent)
                    }
                    if Preferences.onlineFoodSearchEnabled {
                        Text("Only food search terms are sent — no personal data, no tracking.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.leading, 36)
                    }
                }
                .card()

                // Health Nudges
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Health Nudges").font(.subheadline.weight(.medium))
                            Text("Reminders for protein, supplements, and workout gaps")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { Preferences.healthNudgesEnabled },
                            set: {
                                Preferences.healthNudgesEnabled = $0
                                Task { await NotificationService.refreshScheduledAlerts() }
                            }
                        ))
                        .labelsHidden().tint(Theme.accent)
                    }
                }
                .card()

                // Smart Meal Reminders — #385 / #690
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Meal Reminders").font(.subheadline.weight(.medium))
                            Text("Quiet nudge ~30 min after your typical meal time, only if you haven't logged it yet")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { Preferences.mealRemindersEnabled },
                            set: {
                                Preferences.mealRemindersEnabled = $0
                                Task { await NotificationService.refreshScheduledAlerts() }
                            }
                        ))
                        .labelsHidden().tint(Theme.accent)
                    }
                    if Preferences.mealRemindersEnabled {
                        HStack(spacing: 12) {
                            Spacer().frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use my eating patterns").font(.caption.weight(.medium))
                                Text("Learn from the last 30 days. Needs 10+ entries per meal — falls back to defaults below threshold.")
                                    .font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { Preferences.useEatingPatternsForReminders },
                                set: {
                                    Preferences.useEatingPatternsForReminders = $0
                                    Task { await NotificationService.refreshScheduledAlerts() }
                                }
                            ))
                            .labelsHidden().tint(Theme.accent)
                        }
                    }
                }
                .card()

                // Medication Dose Reminders — #592
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "pill.circle")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Medication Dose Reminders").font(.subheadline.weight(.medium))
                            Text("Quiet nudge ~2h after your typical dose time, only if you haven't logged it yet today")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { Preferences.medicationRemindersEnabled },
                            set: {
                                Preferences.medicationRemindersEnabled = $0
                                Task { await NotificationService.refreshScheduledAlerts() }
                            }
                        ))
                        .labelsHidden().tint(Theme.accent)
                    }
                }
                .card()

                // GLP-1 Weekly Reminders — #620
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "syringe")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GLP-1 Weekly Reminders").font(.subheadline.weight(.medium))
                            Text("Weekly notification on your injection day — only fires if you haven't logged a dose in the last 7 days")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { Preferences.glp1RemindersEnabled },
                            set: {
                                Preferences.glp1RemindersEnabled = $0
                                Task { await NotificationService.refreshScheduledAlerts() }
                            }
                        ))
                        .labelsHidden().tint(Theme.accent)
                    }
                }
                .card()

                // AI Chat Telemetry (opt-in, local only) — #261
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Chat Telemetry").font(.subheadline.weight(.medium))
                            Text("Stored on this device. Nothing is transmitted until you tap Export JSON.")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        // Custom binding instead of .onChange — otherwise the
                        // "revert + show confirm" pattern recursed: setting
                        // telemetryEnabled=false fired onChange with on=false,
                        // which then ran the off-branch (deleteAll) *and* the
                        // alert. Tapping "Turn on" in the alert re-fired
                        // onChange → re-reverted → re-showed alert.
                        // Setter just stages the user's intent; actual state
                        // flip happens from the alert's "Turn on" button.
                        Toggle("", isOn: Binding(
                            get: { telemetryEnabled },
                            set: { newValue in
                                if newValue {
                                    // Confirm first — don't flip yet. Toggle
                                    // bounces back to off via `get`.
                                    showingTelemetryEnableConfirm = true
                                } else {
                                    telemetryEnabled = false
                                    Preferences.chatTelemetryEnabled = false
                                    ChatTelemetryService.shared.deleteAll()
                                    telemetryCount = 0
                                }
                            }
                        ))
                        .labelsHidden().tint(Theme.accent)
                    }
                    if telemetryEnabled {
                        Text("Full query + response text is stored locally, alongside the routed tool and outcome. Use Export JSON to share a transcript with the Drift team to improve multi-turn reliability. Nothing leaves this device until you do.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.leading, 36)

                        HStack(spacing: 12) {
                            NavigationLink {
                                AIChatInsightsView()
                            } label: {
                                Label("View insights", systemImage: "chart.line.uptrend.xyaxis")
                                    .font(.caption)
                            }
                            Spacer()
                            Text("\(telemetryCount) turns")
                                .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                        }
                        .padding(.leading, 36)
                        .padding(.top, 4)

                        HStack(spacing: 14) {
                            Button {
                                if let data = ChatTelemetryService.shared.exportJSON() {
                                    telemetryShareURL = writeTelemetryExport(data)
                                    if let url = telemetryShareURL { shareFile(url) }
                                }
                            } label: {
                                Label("Export JSON", systemImage: "square.and.arrow.up").font(.caption)
                            }
                            Button(role: .destructive) {
                                showingTelemetryDeleteConfirm = true
                            } label: {
                                Label("Delete all", systemImage: "trash").font(.caption)
                            }
                            Spacer()
                        }
                        .padding(.leading, 36)
                        .padding(.top, 2)
                    }
                }
                .card()
                .onAppear { telemetryCount = ChatTelemetryService.shared.count() }
                .alert("Delete telemetry?", isPresented: $showingTelemetryDeleteConfirm) {
                    Button("Delete", role: .destructive) {
                        ChatTelemetryService.shared.deleteAll()
                        telemetryCount = 0
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes all recorded chat-turn telemetry from this device. User data (weight, food, workouts) is not affected.")
                }
                .alert("Store chat transcripts on this device?", isPresented: $showingTelemetryEnableConfirm) {
                    Button("Turn on") {
                        Preferences.chatTelemetryEnabled = true
                        telemetryEnabled = true
                        telemetryCount = ChatTelemetryService.shared.count()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("When on, each chat turn's full query and assistant response will be saved on this device only. Nothing is transmitted. You can Export JSON anytime to share a transcript with the Drift team to improve multi-turn AI reliability, or Delete all to wipe it.")
                }

                // Algorithm
                NavigationLink {
                    AlgorithmSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Algorithm").font(.subheadline.weight(.medium))
                            Text("TDEE & calorie target settings").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                }
                .card()

                // Food database refresh — for users who report stale
                // calorie values after an update. Hash-gated reseed runs on
                // every app update, but this gives a manual escape hatch
                // if the automatic path missed (e.g. bundle cached).
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        refreshFoodDatabase()
                    } label: {
                        HStack {
                            if isRefreshingFoods {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(Theme.accent)
                                    .frame(width: 24)
                            } else {
                                Image(systemName: "arrow.clockwise").foregroundStyle(Theme.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Refresh food database").foregroundStyle(Theme.textPrimary)
                                Text(refreshFoodsSubtitle)
                                    .font(.caption2)
                                    .foregroundStyle(refreshFoodsSubtitleColor)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingFoods)
                    .accessibilityLabel("Refresh food database")
                    .accessibilityValue(isRefreshingFoods ? "Refreshing" : refreshFoodsSubtitle)
                    .accessibilityHint("Reloads bundled calorie and macro data")
                }
                .card()

                // Factory Reset
                VStack(alignment: .leading, spacing: 10) {
                    Text("Danger Zone")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.surplus)

                    Button(role: .destructive) {
                        showingFactoryReset = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.fill").foregroundStyle(Theme.surplus)
                            Text("Factory Reset")
                            Spacer()
                        }
                    }
                }
                .card()
                .alert("Factory Reset", isPresented: $showingFactoryReset) {
                    Button("Reset Everything", role: .destructive) { performFactoryReset() }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes ALL local data: weight entries, food logs, workouts, favorites, supplements, DEXA scans, glucose data, lab reports, biomarker results, barcode cache, goals, and algorithm settings. Apple Health data is NOT affected. This cannot be undone.")
                }
                .alert("Reset Complete", isPresented: $resetDone) {
                    Button("OK") {}
                } message: {
                    Text("All data has been cleared. Restart the app for a fresh start.")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Settings")
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    private var refreshFoodsSubtitle: String {
        if isRefreshingFoods {
            return "Reloading bundled foods… please wait"
        }
        if let error = foodsRefreshError {
            return "Refresh failed: \(error)"
        }
        if let count = refreshedFoodCount {
            return "Refreshed — \(count.formatted()) foods loaded"
        }
        return "Reload calories + macros from the bundled list. Use if you see stale values like 0-cal coffee."
    }

    private var refreshFoodsSubtitleColor: Color {
        if foodsRefreshError != nil { return Theme.surplus }
        if refreshedFoodCount != nil { return Theme.accent }
        return .secondary
    }

    private func refreshFoodDatabase() {
        guard !isRefreshingFoods else { return }
        isRefreshingFoods = true
        foodsRefreshError = nil
        refreshedFoodCount = nil
        Task.detached(priority: .userInitiated) {
            do {
                UserDefaults.standard.removeObject(forKey: "drift_foods_json_hash")
                try AppDatabase.shared.seedFoodsFromJSON()
                let count = (try? AppDatabase.shared.foodCount()) ?? 0
                // seedFoodsFromJSON returns silently when the bundled JSON is
                // missing or unreadable. Detect that here so the user sees a
                // real error instead of a green "Refreshed 0 foods" lie.
                if count == 0 {
                    await MainActor.run {
                        foodsRefreshError = "bundled food list is missing"
                        isRefreshingFoods = false
                    }
                    return
                }
                await MainActor.run {
                    refreshedFoodCount = count
                    isRefreshingFoods = false
                }
            } catch {
                await MainActor.run {
                    foodsRefreshError = error.localizedDescription
                    isRefreshingFoods = false
                }
            }
        }
    }

    private func clearStatus() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { syncStatus = nil }
        }
    }

    private func shareFile(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        root.present(vc, animated: true)
    }

    private func performFactoryReset() {
        do {
            try AppDatabase.shared.factoryReset()
            WeightGoal.clear()
            WeightTrendCalculator.saveConfig(.default)
            TDEEEstimator.saveConfig(.default)
            WorkoutService.clearSession()
            UserDefaults.standard.removeObject(forKey: "weight_unit")
            UserDefaults.standard.removeObject(forKey: "drift_custom_exercises")
            UserDefaults.standard.removeObject(forKey: "drift_exercise_favorites")
            UserDefaults.standard.removeObject(forKey: "drift_tdee_cache")
            UserDefaults.standard.removeObject(forKey: "drift_default_templates_v3")
            UserDefaults.standard.removeObject(forKey: "drift_default_templates_v2")
            UserDefaults.standard.removeObject(forKey: "drift_default_templates_seeded")
            UserDefaults.standard.removeObject(forKey: "drift_cycle_fertile_window")
            Log.app.info("Factory reset performed")
            resetDone = true
        } catch {
            Log.app.error("Factory reset failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Export

    private func exportWorkoutsCSV() -> URL? {
        // Only export workouts created in Drift (exclude imported history older than the app install)
        // Use the same data the dashboard shows
        guard let workouts = try? WorkoutService.fetchWorkouts(limit: 10000) else { return nil }
        // Filter: only workouts that have sets (imported but empty workouts are noise)
        let validWorkouts = workouts.filter { w in
            guard let wid = w.id else { return false }
            let sets = (try? WorkoutService.fetchSets(forWorkout: wid)) ?? []
            return !sets.isEmpty
        }
        var csv = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps,RPE\n"
        for w in validWorkouts {
            guard let wid = w.id else { continue }
            let sets = (try? WorkoutService.fetchSets(forWorkout: wid)) ?? []
            for s in sets {
                let weight = s.weightLbs.map { String(format: "%.1f", $0) } ?? ""
                let reps = s.reps.map { "\($0)" } ?? ""
                let rpe = s.rpe.map { String(format: "%.1f", $0) } ?? ""
                let eName = s.exerciseName.replacingOccurrences(of: "\"", with: "\"\"")
                let wName = w.name.replacingOccurrences(of: "\"", with: "\"\"")
                csv += "\"\(w.date)\",\"\(wName)\",\"\(eName)\",\(s.setOrder),\(weight),\(reps),\(rpe)\n"
            }
        }
        let dateStr = DateFormatters.dateOnly.string(from: Date())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drift_workouts_\(dateStr).csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func exportFoodLogsCSV() -> URL? {
        var csv = "Date,Time,Food,Calories,Protein,Carbs,Fat,Fiber,Servings\n"
        // Export last 90 days
        let today = Date()
        for dayOffset in 0..<90 {
            guard let date = Calendar.current.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            let logs = FoodService.fetchMealLogs(for: dateStr)
            guard !logs.isEmpty else { continue }
            for log in logs {
                guard let logId = log.id else { continue }
                let entries = FoodService.fetchFoodEntries(forMealLog: logId)
                guard !entries.isEmpty else { continue }
                for e in entries {
                    let fName = e.foodName.replacingOccurrences(of: "\"", with: "\"\"")
                    let time = (DateFormatters.iso8601.date(from: e.loggedAt) ?? DateFormatters.sqliteDatetime.date(from: e.loggedAt))
                        .map { DateFormatters.shortTime.string(from: $0) } ?? ""
                    csv += "\"\(dateStr)\",\"\(time)\",\"\(fName)\",\(Int(e.totalCalories)),\(Int(e.totalProtein)),\(Int(e.totalCarbs)),\(Int(e.totalFat)),\(Int(e.totalFiber)),\(String(format: "%.1f", e.servings))\n"
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("drift_food_logs.csv")
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Write exported telemetry JSON to a temp file for the share sheet. #261.
    private func writeTelemetryExport(_ data: Data) -> URL? {
        let dateStr = DateFormatters.dateOnly.string(from: Date())
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drift_chat_telemetry_\(dateStr).json")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.app.error("Telemetry export write failed: \(error.localizedDescription)")
            return nil
        }
    }
}

// ShareSheet is defined in WorkoutView.swift — reused here for file export
