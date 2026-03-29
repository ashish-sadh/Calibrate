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

                    // Version
                    Text("Drift v0.1.0")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
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
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Settings")
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}
