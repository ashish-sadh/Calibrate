import SwiftUI

struct MoreTabView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Data") {
                    NavigationLink {
                        DEXAOverviewView()
                    } label: {
                        Label("Body Composition", systemImage: "figure.stand")
                    }

                    NavigationLink {
                        GlucoseTabView()
                    } label: {
                        Label("Glucose (CGM)", systemImage: "waveform.path.ecg")
                    }
                }

                Section("Settings") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("0.1.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("More")
        }
    }
}

struct SettingsView: View {
    @State private var weightUnit: WeightUnit = Preferences.weightUnit

    var body: some View {
        Form {
            Section("Units") {
                Picker("Weight Unit", selection: $weightUnit) {
                    Text("kg").tag(WeightUnit.kg)
                    Text("lbs").tag(WeightUnit.lbs)
                }
                .onChange(of: weightUnit) { _, newValue in
                    Preferences.weightUnit = newValue
                }
            }

            Section("Apple Health") {
                Button("Request HealthKit Access") {
                    Task {
                        try? await HealthKitService.shared.requestAuthorization()
                    }
                }

                Button("Sync Weight from Health") {
                    Task {
                        let count = try? await HealthKitService.shared.syncWeight()
                        print("Synced \(count ?? 0) weight entries")
                    }
                }
            }
        }
        .navigationTitle("Settings")
    }
}
