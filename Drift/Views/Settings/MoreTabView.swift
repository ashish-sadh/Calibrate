import SwiftUI
import DriftCore

struct MoreTabView: View {
    @Binding var selectedTab: Int
    @State private var navId = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // ACTIVITY section removed 2026-07-09: its only row was
                    // Exercise, which is now the Workout TAB (operator: "keep
                    // exercises on the front"). Same journey Food took —
                    // briefly a More row (c6a475fb), promoted to a tab
                    // 2026-05-20 when it felt "almost gone".

                    section("HEALTH") {
                        // Weight lives on the Body tab (the canonical screen); the
                        // detailed weight view in More is "Weight Goal" below.
                        // (A duplicate full-Weight row here pushed WeightTabView —
                        // a NavigationStack-owning tab view — into More's stack,
                        // nesting stacks → two back arrows + divergent chrome.)
                        navRow(icon: "waveform.path", title: "Body Rhythm",
                               subtitle: "Sleep, vitals, recovery",
                               color: Theme.rhythmTeal) {
                            SleepRecoveryView()
                        }
                        // Cycle row hidden 2026-07-28 (operator): keep the first
                        // impression light for new users — no cycle info before
                        // they trust the app. CycleView still exists; re-enable
                        // by restoring this row when there's a considered place for it.
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
                        navRow(icon: "camera.on.rectangle", title: "Progress Photos",
                               subtitle: "Photos & measurements · on-device only",
                               color: Theme.macroFat) {
                            ProgressGalleryView()
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
                        // Profile is identity, not goal config — its own row
                        // (operator call 2026-07-09); Weight Goal keeps a
                        // compact link so the TDEE connection stays visible.
                        navRow(icon: "person.crop.circle", title: "Profile",
                               subtitle: "Sex · age · height · weight",
                               color: Theme.chartTrend) {
                            ProfileView()
                        }
                        rowDivider
                        navRow(icon: "target", title: "Weight Goal",
                               subtitle: "Target weight, timeline, plan",
                               color: Theme.macroFat) {
                            GoalView()
                        }
                        rowDivider
                        navRow(icon: "person.2.fill", title: "Friends",
                               subtitle: "Share workouts · connect with a trainer",
                               color: Theme.deficit) {
                            SharingView()
                        }
                        rowDivider
                        navRow(icon: "key.fill", title: "Bring Your Own Key",
                               subtitle: "Snap a meal · cloud AI",
                               color: Theme.macroFiber) {
                            PhotoLogSettingsView()
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
            .floatingTabBarClearance()
            .navigationTitle("More")
            // #premium-polish: inline to match the other three tab roots — the
            // large title made the nav bar jump ~50pt taller on every swap
            // to/from More (the swap is instant, so the header hard-cut).
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.light, for: .navigationBar)
            // V7: per-tab ChatIconButton dropped — bottom-right
            // floating ChatIconButton in ContentView covers all tabs.
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
                        .font(.system(size: Theme.FontSize.subheadline, weight: .semibold))
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
    // Apple Health nutrition write-back (#934)
    @State private var healthNutritionWrite: Bool = Preferences.healthNutritionWriteEnabled
    @State private var showingPastSyncOptions = false
    @State private var pastSyncRunning = false
    @State private var telemetryEnabled: Bool = Preferences.chatTelemetryEnabled
    @State private var telemetryCount: Int = 0
    @State private var showingTelemetryDeleteConfirm = false
    @State private var showingTelemetryEnableConfirm = false
    @State private var telemetryShareURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // V7 Settings cleanup pass: explicit section headers
                // throughout. The previous flat list of cards made it
                // hard to see "which group is this in." Headers use
                // the shared `Text.sectionHeading()` (small-caps +
                // tracking + secondary) so the rhythm matches the
                // More tab and (eventually) the rest of the app.
                Text("UNITS").sectionHeading().frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Body Weight Unit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Picker("Body Weight Unit", selection: $weightUnit) {
                        Text("kg").tag(WeightUnit.kg)
                        Text("lbs").tag(WeightUnit.lbs)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: weightUnit) { _, v in Preferences.weightUnit = v }
                    Text("Body weight only — exercise weights stay in lbs.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .card()

                Text("HEALTH SOURCES").sectionHeading().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Apple Health")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    // ONE import action (2026-07-09 simplification — was three
                    // rows: Request Access / Sync Weight / Full Re-sync).
                    // Authorization is folded in (iOS only shows the sheet
                    // when undetermined), and a manual sync always does the
                    // FULL, idempotent import: incremental-vs-full was an
                    // implementation detail no user should have to pick —
                    // and the buried Full Re-sync was the only escape from a
                    // poisoned anchor (same-day field report).
                    Button {
                        Task {
                            do {
                                guard let health = DriftPlatform.health else { return }
                                try await health.requestAuthorization()
                                let weight = try await health.fullResyncWeight()
                                let bodyComp = (try? await health.syncBodyComposition()) ?? 0
                                syncStatus = weight + bodyComp > 0
                                    ? "Imported \(weight) weight + \(bodyComp) body-composition entries"
                                    : "No data found. If Apple Health has your weight, enable Weight under Settings → Privacy & Security → Health → Drift, then sync again."
                            } catch {
                                syncStatus = "Sync failed: \(error.localizedDescription)"
                            }
                            clearStatus()
                        }
                    } label: {
                        // Settings row grammar (design pass 2026-07-10):
                        // subheadline titles, leading captions — unstyled
                        // body-size titles + auto-centered captions read
                        // "so ugly / not premium" in the field.
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(Theme.heartRed).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Sync from Apple Health")
                                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                                Text("Import weight & body data — safe to run anytime")
                                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }

                    Divider().overlay(Theme.separatorFaint)

                    // Nutrition write-back (#934): dietary calories (NOT
                    // active energy) + protein/carbs/fat/fiber, written
                    // per-entry as meals are logged. Off by default; the
                    // writer auto-disables it if another app is detected
                    // writing nutrition (no double counting).
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(isOn: Binding(
                            get: { healthNutritionWrite },
                            set: { newValue in
                                if newValue {
                                    Task {
                                        switch await HealthNutritionSyncService.shared.requestEnable() {
                                        case .enabled:
                                            healthNutritionWrite = true
                                            syncStatus = "Nutrition will be written to Apple Health as you log"
                                        case .foreignDetected(let apps):
                                            healthNutritionWrite = false
                                            syncStatus = "\(apps.joined(separator: ", ")) already writes nutrition to Health — left off to avoid double counting"
                                        case .authDenied:
                                            healthNutritionWrite = false
                                            syncStatus = "Health write access denied — allow Drift in Settings → Health → Data Access"
                                        case .unavailable:
                                            healthNutritionWrite = false
                                            syncStatus = "Apple Health isn't available on this device"
                                        }
                                        clearStatus()
                                    }
                                } else {
                                    healthNutritionWrite = false
                                    Preferences.healthNutritionWriteEnabled = false
                                }
                            }
                        )) {
                            HStack(spacing: 12) {
                                Image(systemName: "fork.knife.circle.fill")
                                    .foregroundStyle(Theme.heartRed).frame(width: 24)
                                Text("Write Nutrition to Health")
                                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .tint(Theme.ink)
                        Text("Calories eaten, protein, carbs, fat, fiber — written as you log")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.leading)
                            .padding(.leading, 36)
                        if let reason = Preferences.healthNutritionAutoDisableReason, !healthNutritionWrite {
                            Text(reason).font(.caption2).foregroundStyle(Theme.warn)
                        }
                    }

                    if healthNutritionWrite {
                        Button {
                            showingPastSyncOptions = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundStyle(Theme.textSecondary).frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pastSyncRunning ? "Syncing past data…" : "Sync Past Data…")
                                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                                    Text("Writes your logged history — never duplicates")
                                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                if pastSyncRunning { ProgressView().scaleEffect(0.7) }
                            }
                        }
                        .disabled(pastSyncRunning)
                        .confirmationDialog("Sync past nutrition to Apple Health", isPresented: $showingPastSyncOptions, titleVisibility: .visible) {
                            Button("Last 30 days") { runPastSync(days: 30) }
                            Button("Last 90 days") { runPastSync(days: 90) }
                            Button("All history") { runPastSync(days: nil) }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Days another app already wrote nutrition for are skipped to avoid double counting.")
                        }
                    }

                    if let status = syncStatus {
                        Text(status).font(.caption).foregroundStyle(Theme.textSecondary)
                            .transition(.opacity)
                    }
                }
                .card()
                .onReceive(NotificationCenter.default.publisher(for: .healthNutritionAutoDisabled)) { _ in
                    healthNutritionWrite = false
                    syncStatus = Preferences.healthNutritionAutoDisableReason
                }

                // iCloud Backup
                NavigationLink {
                    BackupSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "icloud")
                            .foregroundStyle(Theme.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud Backup").font(.subheadline.weight(.medium))
                            Text("Daily snapshot of your data to iCloud Drive")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .card()

                Text("DATA").sectionHeading().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                // Export
                VStack(alignment: .leading, spacing: 10) {
                    Text("Export Data")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)

                    Button {
                        if let url = exportWorkoutsCSV() {
                            shareFile(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dumbbell.fill").foregroundStyle(Theme.textSecondary).frame(width: 24)
                            Text("Export Workouts (CSV)")
                                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "square.and.arrow.up").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }

                    Button {
                        if let url = exportFoodLogsCSV() {
                            shareFile(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "fork.knife").foregroundStyle(Theme.textSecondary).frame(width: 24)
                            Text("Export Food Logs (CSV)")
                                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Image(systemName: "square.and.arrow.up").font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                .card()

                Text("PRIVACY").sectionHeading().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                // Online Food Search
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(Theme.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Online Food Search").font(.subheadline.weight(.medium))
                            Text("Search USDA & Open Food Facts when local results are limited")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { Preferences.onlineFoodSearchEnabled },
                            set: { Preferences.onlineFoodSearchEnabled = $0 }
                        ))
                        .labelsHidden().tint(Theme.ink)
                    }
                    if Preferences.onlineFoodSearchEnabled {
                        Text("Only food search terms are sent — no personal data, no tracking.")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                            .padding(.leading, 36)
                    }
                }
                .card()

                // Coach web search — real search results for restaurant/chain
                // nutrition ("chipotle bowl calories"). Provider ladder:
                // Google Custom Search → Brave → DuckDuckGo (keyless fallback).
                // Explicit cloud touch-point: only the search query leaves the
                // device, sent to the configured provider.
                WebSearchSettingsCard()

                // Telemetry & Privacy — where the anonymous usage pipeline is
                // disclosed and switched off (operator decision 2026-07-28,
                // superseding the on-device-only counters of 2026-07-09).
                NavigationLink { TelemetrySettingsView() } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar")
                            .foregroundStyle(Theme.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Telemetry & Privacy").font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Anonymous usage · AI conversation sharing")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    .card()
                }
                .buttonStyle(.plain)

                Text("NOTIFICATIONS").sectionHeading().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                // V7 Settings restructure: the 4 notification reminders
                // (Health Nudges, Smart Meal, Medication, GLP-1) moved
                // into a dedicated `NotificationsSettingsView` sub-page
                // and shown here as a single navigation row, matching
                // iOS Settings → Notifications convention. Cuts the
                // top-level Settings list from ~13 cards to ~7.
                NavigationLink {
                    NotificationsSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(Theme.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notifications").font(.subheadline.weight(.medium))
                            Text("Health nudges, meal reminders, medication, GLP-1")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
                            .accessibilityHidden(true)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .card()

                Text("ADVANCED").sectionHeading().frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                // AI Chat Telemetry (opt-in, local only) — #261
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .foregroundStyle(Theme.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Chat Telemetry").font(.subheadline.weight(.medium))
                            Text("Stored on this device. Nothing is transmitted until you tap Export JSON.")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
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
                        .labelsHidden().tint(Theme.ink)
                    }
                    if telemetryEnabled {
                        Text("Full query + response text is stored locally, alongside the routed tool and outcome. Use Export JSON to share a transcript with the Drift team to improve multi-turn reliability. Nothing leaves this device until you do.")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
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
                                .font(.caption2).foregroundStyle(Theme.textTertiary).monospacedDigit()
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
                            .foregroundStyle(Theme.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Algorithm").font(.subheadline.weight(.medium))
                            Text("TDEE & calorie target settings").font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
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
                                    .tint(Theme.textSecondary)
                                    .frame(width: 24)
                            } else {
                                Image(systemName: "arrow.clockwise").foregroundStyle(Theme.textSecondary)
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
        // V7 light palette: button labels here inherited the system tint
        // (coral from V6) and shipped as unreadable pink. Force the tint
        // to ink so text reads as charcoal-on-white. Explicitly-colored
        // sub-elements (heart icon, sync arrows, destructive Factory
        // Reset) keep their `.foregroundStyle(...)` overrides — .tint
        // only affects the buttons' default content color.
        .tint(Theme.textPrimary)
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
        if refreshedFoodCount != nil { return Theme.textSecondary }
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

    /// Apple Health past-sync (#934). Idempotent — sync identifiers make
    /// re-runs replace rather than duplicate; foreign-app days are skipped.
    private func runPastSync(days: Int?) {
        pastSyncRunning = true
        Task {
            let summary = await HealthNutritionSyncService.shared.syncPast(days: days)
            pastSyncRunning = false
            var status = "Wrote \(summary.entriesWritten) entries to Health"
            if summary.daysSkipped > 0 {
                status += " — \(summary.daysSkipped) day(s) skipped (\(summary.foreignApps.joined(separator: ", ")) data present)"
            }
            syncStatus = status
            clearStatus()
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

// MARK: - Notifications Settings sub-page
//
// V7 Settings restructure: four notification toggles (Health Nudges,
// Smart Meal Reminders, Medication Dose, GLP-1 Weekly) extracted
// from the top-level SettingsView into a dedicated sub-page. Each
// toggle still writes Preferences and refreshes
// NotificationService — no behavior change, just IA cleanup.

struct NotificationsSettingsView: View {
    @State private var mealRemindersOn = Preferences.mealRemindersEnabled

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                toggleCard(
                    icon: "bell.badge",
                    title: "Health Nudges",
                    subtitle: "Reminders for protein, supplements, and workout gaps",
                    isOn: Binding(
                        get: { Preferences.healthNudgesEnabled },
                        set: {
                            Preferences.healthNudgesEnabled = $0
                            Task { await NotificationService.refreshScheduledAlerts() }
                        }
                    )
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife.circle")
                            .foregroundStyle(Theme.textSecondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Smart Meal Reminders").font(.subheadline.weight(.medium))
                            Text("Quiet nudge ~30 min after your typical meal time, only if you haven't logged it yet")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { Preferences.mealRemindersEnabled },
                            set: { newValue in
                                Preferences.mealRemindersEnabled = newValue
                                mealRemindersOn = newValue
                                Task { await NotificationService.refreshScheduledAlerts() }
                            }
                        ))
                        .labelsHidden().tint(Theme.ink)
                    }
                    if mealRemindersOn {
                        HStack(spacing: 12) {
                            Spacer().frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use my eating patterns").font(.caption.weight(.medium))
                                Text("Learn from the last 30 days. Needs 10+ entries per meal — falls back to defaults below threshold.")
                                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { Preferences.useEatingPatternsForReminders },
                                set: {
                                    Preferences.useEatingPatternsForReminders = $0
                                    Task { await NotificationService.refreshScheduledAlerts() }
                                }
                            ))
                            .labelsHidden().tint(Theme.ink)
                        }
                    }
                }
                .card()

                toggleCard(
                    icon: "pill.circle",
                    title: "Medication Dose Reminders",
                    subtitle: "Quiet nudge ~2h after your typical dose time, only if you haven't logged it yet today",
                    isOn: Binding(
                        get: { Preferences.medicationRemindersEnabled },
                        set: {
                            Preferences.medicationRemindersEnabled = $0
                            Task { await NotificationService.refreshScheduledAlerts() }
                        }
                    )
                )

                toggleCard(
                    icon: "syringe",
                    title: "GLP-1 Weekly Reminders",
                    subtitle: "Weekly notification on your injection day — only fires if you haven't logged a dose in the last 7 days",
                    isOn: Binding(
                        get: { Preferences.glp1RemindersEnabled },
                        set: {
                            Preferences.glp1RemindersEnabled = $0
                            Task { await NotificationService.refreshScheduledAlerts() }
                        }
                    )
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
    }

    @ViewBuilder
    private func toggleCard(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.textSecondary).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.medium))
                    Text(subtitle).font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Toggle("", isOn: isOn)
                    .labelsHidden().tint(Theme.ink)
            }
        }
        .card()
    }
}
// MARK: - Telemetry & Privacy

/// Replaced the on-device Usage Insights counters (2026-07-28). Those tallied
/// what happened on THIS phone, which never answered what real users reach for;
/// counts now aggregate anonymously server-side. This screen is where that is
/// disclosed and switched off — the "surfaced" leg of the cloud-touchpoint rule
/// in Docs/decisions.md.
struct TelemetrySettingsView: View {
    @State private var usageEnabled = Preferences.usageTelemetryEnabled
    @State private var aiCaptureEnabled = Preferences.aiCaptureEnabled

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $usageEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share anonymous usage").font(.subheadline.weight(.medium))
                            Text("Which screens and actions get used — no food, weight or health data, and no account.")
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.accent)
                    .onChange(of: usageEnabled) { _, newValue in
                        Preferences.usageTelemetryEnabled = newValue
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $aiCaptureEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Share AI conversations").font(.subheadline.weight(.medium))
                            Text("Uploads what you ask Drift Coach and Describe, plus the reply, so bad answers can be fixed. These can contain meals, weight and symptoms.")
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .tint(Theme.accent)
                    .onChange(of: aiCaptureEnabled) { _, newValue in
                        Preferences.aiCaptureEnabled = newValue
                    }
                }
                .card()

                Text("Usage counts are on by default and anonymous. AI conversations are off unless you turn them on. Neither is linked to your @username or to a Drift account.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Telemetry & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
