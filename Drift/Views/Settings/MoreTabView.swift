import SwiftUI

struct MoreTabView: View {
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

                    // Data section
                    VStack(spacing: 0) {
                        navRow(icon: "bed.double.fill", title: "Sleep & Recovery", subtitle: "Sleep stages, HRV, recovery score", color: Theme.sleepIndigo) {
                            SleepRecoveryView()
                        }
                        Divider().overlay(Color.white.opacity(0.05))
                        navRow(icon: "figure.stand", title: "Body Composition", subtitle: "DEXA scan data", color: Theme.accent) {
                            DEXAOverviewView()
                        }
                        Divider().overlay(Color.white.opacity(0.05))
                        navRow(icon: "waveform.path.ecg", title: "Glucose", subtitle: "Lingo CGM data", color: Theme.calorieBlue) {
                            GlucoseTabView()
                        }
                    }
                    .card()

                    // Settings
                    VStack(spacing: 0) {
                        navRow(icon: "gear", title: "Settings", subtitle: "Units, Health access", color: .secondary) {
                            SettingsView()
                        }
                        Divider().overlay(Color.white.opacity(0.05))
                        navRow(icon: "slider.horizontal.3", title: "Algorithm", subtitle: "Tune deficit calculation", color: Theme.accent) {
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
                    Text("Drift v0.1.0")
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
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
}

struct SettingsView: View {
    @State private var weightUnit: WeightUnit = Preferences.weightUnit
    @State private var showingFactoryReset = false
    @State private var resetDone = false

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
                        Task { try? await HealthKitService.shared.requestAuthorization() }
                    } label: {
                        HStack {
                            Image(systemName: "heart.fill").foregroundStyle(Theme.heartRed)
                            Text("Request Health Access")
                            Spacer()
                        }
                    }

                    Button {
                        Task { _ = try? await HealthKitService.shared.syncWeight() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.accent)
                            Text("Sync Weight")
                            Spacer()
                        }
                    }

                    Button {
                        Task { _ = try? await HealthKitService.shared.fullResyncWeight() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise").foregroundStyle(.orange)
                            Text("Full Re-sync (all history)")
                            Spacer()
                        }
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
                    Text("This deletes ALL local data: weight entries, food logs, supplements, DEXA scans, glucose data, barcode cache, goals, and algorithm settings. Apple Health data is NOT affected. This cannot be undone.")
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

    private func performFactoryReset() {
        do {
            try AppDatabase.shared.factoryReset()
            WeightGoal.clear()
            WeightTrendCalculator.saveConfig(.default)
            UserDefaults.standard.removeObject(forKey: "weight_unit")
            Log.app.info("Factory reset performed")
            resetDone = true
        } catch {
            Log.app.error("Factory reset failed: \(error.localizedDescription)")
        }
    }
}
