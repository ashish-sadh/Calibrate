import SwiftUI

struct MoreTabView: View {
    @Binding var selectedTab: Int
    @State private var navId = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
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
                        Divider().overlay(Color.white.opacity(0.05))
                        navRow(icon: "pill.fill", title: "Supplements", subtitle: "Daily checklist, consistency", color: .mint) {
                            SupplementsTabView()
                        }
                        Divider().overlay(Color.white.opacity(0.05))
                        navRow(icon: "figure.stand", title: "Body Composition", subtitle: "DEXA scan data", color: Theme.accent) {
                            DEXAOverviewView()
                        }
                        Divider().overlay(Color.white.opacity(0.05))
                        navRow(icon: "waveform.path.ecg", title: "Glucose", subtitle: "CGM glucose tracking", color: Theme.calorieBlue) {
                            GlucoseTabView()
                        }
                        Divider().overlay(Color.white.opacity(0.05))
                        navRow(icon: "cross.case.fill", title: "Biomarkers", subtitle: "Blood test results & trends", color: Theme.heartRed) {
                            BiomarkersTabView()
                        }
                    }
                    .card()

                    // Settings
                    VStack(spacing: 0) {
                        navRow(icon: "gear", title: "Settings", subtitle: "Units, Health access", color: .secondary) {
                            SettingsView()
                        }
                        Divider().overlay(Color.white.opacity(0.05))
                        navRow(icon: "slider.horizontal.3", title: "Algorithm", subtitle: "TDEE & calorie target settings", color: Theme.accent) {
                            AlgorithmSettingsView()
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
                        Text("Drift stores all data locally on your iPhone and Apple Health. No accounts, no cloud, no tracking. Barcode lookups use Open Food Facts (open-source) and only send the barcode number.")
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
            .navigationTitle("More")
            .toolbarColorScheme(.dark, for: .navigationBar)
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
                                syncStatus = "Sync failed"
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
                                syncStatus = "Re-sync failed"
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

    private func performFactoryReset() {
        do {
            try AppDatabase.shared.factoryReset()
            WeightGoal.clear()
            WeightTrendCalculator.saveConfig(.default)
            TDEEEstimator.saveConfig(.default)
            WorkoutService.clearSession()
            UserDefaults.standard.removeObject(forKey: "weight_unit")
            UserDefaults.standard.removeObject(forKey: "drift_custom_exercises")
            UserDefaults.standard.removeObject(forKey: "drift_default_templates_v3")
            UserDefaults.standard.removeObject(forKey: "drift_default_templates_v2")
            UserDefaults.standard.removeObject(forKey: "drift_default_templates_seeded")
            UserDefaults.standard.removeObject(forKey: "drift_default_foods_seeded_v1")
            Log.app.info("Factory reset performed")
            resetDone = true
        } catch {
            Log.app.error("Factory reset failed: \(error.localizedDescription)")
        }
    }
}
