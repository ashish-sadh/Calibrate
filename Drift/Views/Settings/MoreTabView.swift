import SwiftUI

struct MoreTabView: View {
    @Binding var selectedTab: Int
    @State private var navId = UUID()
    @State private var hasCycleData = false
    @State private var showingAIRemoveConfirm = false
    @State private var showingAIRemoved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Report a Bug — prominent at top
                    Link(destination: URL(string: "https://ashish-sadh.github.io/Drift/")!) {
                        HStack(spacing: 12) {
                            Image(systemName: "ant.fill")
                                .foregroundStyle(.red)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Report a Bug")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Found something wrong? Let us know")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                    }
                    .card()

                    // Goal
                    VStack(spacing: 0) {
                        navRow(icon: "target", title: "Weight Goal", subtitle: "Target weight, timeline, deficit plan", color: Theme.deficit) {
                            GoalView()
                        }
                    }
                    .card()

                    // Health & Data
                    VStack(spacing: 0) {
                        navRow(icon: "waveform.path", title: "Body Rhythm", subtitle: "Sleep, vitals, and recovery", color: Theme.rhythmTeal) {
                            SleepRecoveryView()
                        }
                        if hasCycleData {
                            Divider().overlay(Theme.separator)
                            navRow(icon: "circle.circle", title: "Cycle", subtitle: "Period tracking from Apple Health", color: Theme.cyclePink) {
                                CycleView()
                            }
                        }
                        Divider().overlay(Theme.separator)
                        navRow(icon: "pill.fill", title: "Supplements", subtitle: "Daily checklist, consistency", color: Theme.supplementMint) {
                            SupplementsTabView()
                        }
                        Divider().overlay(Theme.separator)
                        navRow(icon: "figure.stand", title: "Body Composition", subtitle: "DEXA scan data", color: Theme.accent) {
                            DEXAOverviewView()
                        }
                        Divider().overlay(Theme.separator)
                        navRow(icon: "waveform.path.ecg", title: "Glucose", subtitle: "CGM glucose tracking", color: Theme.calorieBlue) {
                            GlucoseTabView()
                        }
                        Divider().overlay(Theme.separator)
                        navRow(icon: "cross.case.fill", title: "Biomarkers", subtitle: "Blood test results & trends", color: Theme.heartRed) {
                            BiomarkersTabView()
                        }
                        Divider().overlay(Theme.separator)
                        navRow(icon: "gear", title: "Settings", subtitle: "Units, Health access, algorithm", color: .secondary) {
                            SettingsView()
                        }
                    }
                    .card()

                    // AI
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(Theme.accent).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("AI Assistant").font(.subheadline.weight(.medium))
                                Text("On-device AI · Beta").font(.caption2).foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { Preferences.aiEnabled },
                                set: { Preferences.aiEnabled = $0 }
                            ))
                            .labelsHidden().tint(Theme.accent)
                        }
                        .padding(.vertical, 10)

                        if AIModelManager.shared.isModelDownloaded || showingAIRemoved {
                            Divider().overlay(Theme.separator)
                            if showingAIRemoved {
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.deficit)
                                    Text("AI data removed").font(.subheadline).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                                .transition(.opacity)
                            } else {
                                Button(role: .destructive) {
                                    showingAIRemoveConfirm = true
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "trash").foregroundStyle(Theme.surplus).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Remove AI Data").font(.subheadline.weight(.medium)).foregroundStyle(Theme.surplus)
                                            Text("Free ~\(AIModelManager.shared.modelSizeOnDiskMB) MB")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 10)
                                }.buttonStyle(.plain)
                                .alert("Remove AI Data?", isPresented: $showingAIRemoveConfirm) {
                                    Button("Remove", role: .destructive) {
                                        LocalAIService.shared.deleteModel()
                                        Preferences.aiEnabled = false
                                        withAnimation { showingAIRemoved = true }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                            withAnimation { showingAIRemoved = false }
                                        }
                                    }
                                    Button("Cancel", role: .cancel) {}
                                } message: {
                                    Text("This will delete the AI model (~\(AIModelManager.shared.modelSizeOnDiskMB) MB) from your device.")
                                }
                            }
                        }
                    }
                    .card()

                    // Privacy
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(Theme.deficit)
                                .font(.caption)
                            Text("Your data stays on your device")
                                .font(.caption.weight(.medium))
                        }
                        Text("Drift stores all data locally on your iPhone and Apple Health. No accounts, no cloud, no tracking. Barcode lookups send only the barcode number. Online food search (opt-in) sends food search terms to USDA and Open Food Facts — no personal data.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .card()

                    // Version
                    Text("Drift v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("More")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { hasCycleData = await HealthKitService.shared.hasCycleData() }
        }
        .id(navId)
        .onChange(of: selectedTab) { oldTab, newTab in
            // When leaving More tab, reset navigation so it shows root when coming back
            if oldTab == 4 && newTab != 4 { navId = UUID() }
        }
    }

    private func navRow<Dest: View>(icon: String, title: String, subtitle: String, color: Color, @ViewBuilder destination: () -> Dest) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundStyle(color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @State private var weightUnit: WeightUnit = Preferences.weightUnit
    @State private var showingFactoryReset = false
    @State private var resetDone = false
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
                    Text("Units")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Weight Unit", selection: $weightUnit) {
                        Text("kg").tag(WeightUnit.kg)
                        Text("lbs").tag(WeightUnit.lbs)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: weightUnit) { _, v in Preferences.weightUnit = v }
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
                        Toggle("", isOn: $telemetryEnabled)
                            .labelsHidden().tint(Theme.accent)
                            .onChange(of: telemetryEnabled) { _, on in
                                if on {
                                    // Show the storage disclosure before flipping the pref
                                    // so the user confirms they understand raw text is kept.
                                    telemetryEnabled = false
                                    showingTelemetryEnableConfirm = true
                                } else {
                                    Preferences.chatTelemetryEnabled = false
                                    ChatTelemetryService.shared.deleteAll()
                                    telemetryCount = ChatTelemetryService.shared.count()
                                }
                            }
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

                // Photo Log (Beta) — BYOK cloud vision. #224 / #266.
                NavigationLink {
                    PhotoLogBetaSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.viewfinder")
                            .foregroundStyle(Theme.accent).frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("Photo Log").font(.subheadline.weight(.medium))
                                Text("BETA").font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Theme.accent.opacity(0.2)).clipShape(Capsule())
                            }
                            Text("Snap a meal, get calories · BYOK cloud AI")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                }
                .card()

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
                    }
                    .padding(.vertical, 10)
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
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            UserDefaults.standard.removeObject(forKey: "drift_default_foods_seeded_v1")
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
