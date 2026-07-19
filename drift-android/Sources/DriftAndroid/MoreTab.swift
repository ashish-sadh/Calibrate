import SwiftUI
import DriftCore

/// Minimal More tab (#1067 tracks the full iOS settings hub). Weight-unit
/// preference is live; the rest lists what's coming so nothing looks broken.
struct MoreTab: View {
    @State var unit = Preferences.weightUnit

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PREFERENCES").sectionHeading()
                        HStack {
                            Text("Weight unit").font(.subheadline)
                            Spacer()
                            Picker("", selection: $unit) {
                                Text("lbs").tag(WeightUnit.lbs)
                                Text("kg").tag(WeightUnit.kg)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 140)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRIVACY").sectionHeading()
                        HStack(spacing: 6) {
                            Image(systemName: "lock.fill").font(.caption).foregroundStyle(Theme.deficit)
                            Text("Everything is stored on this device. No cloud, no accounts, no analytics.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("COMING TO ANDROID").sectionHeading()
                        ForEach(["Drift Coach chat + voice", "Photo & barcode logging",
                                 "Health Connect sync", "Sleep, cycle & biomarkers",
                                 "Backup & restore"], id: \.self) { item in
                            HStack(spacing: 6) {
                                Circle().fill(Theme.textQuaternary).frame(width: 5, height: 5)
                                Text(item).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("More")
            .onChange(of: unit) { _, newValue in
                Preferences.weightUnit = newValue
            }
        }
    }
}
