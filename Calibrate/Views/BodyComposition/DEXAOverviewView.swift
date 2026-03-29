import SwiftUI

struct DEXAOverviewView: View {
    @State private var scans: [DEXAScan] = []
    @State private var showingAddScan = false
    private let database = AppDatabase.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let latest = scans.first {
                    let previous = scans.count > 1 ? scans[1] : nil

                    // Overview cards (like BodySpec UI)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        overviewCard(
                            title: "Body Fat %",
                            value: latest.bodyFatPct.map { String(format: "%.1f %%", $0) } ?? "--",
                            delta: delta(latest.bodyFatPct, previous?.bodyFatPct),
                            deltaUnit: "%",
                            isLowerBetter: true
                        )
                        overviewCard(
                            title: "Lean Mass",
                            value: latest.leanMassLbs.map { String(format: "%.1f lbs", $0) } ?? "--",
                            delta: deltaLbs(latest.leanMassKg, previous?.leanMassKg),
                            deltaUnit: "lbs",
                            isLowerBetter: false
                        )
                        overviewCard(
                            title: "Fat Mass",
                            value: latest.fatMassLbs.map { String(format: "%.1f lbs", $0) } ?? "--",
                            delta: deltaLbs(latest.fatMassKg, previous?.fatMassKg),
                            deltaUnit: "lbs",
                            isLowerBetter: true
                        )
                        overviewCard(
                            title: "Visceral Fat",
                            value: latest.visceralFatLbs.map { String(format: "%.1f lbs", $0) } ?? "--",
                            delta: deltaLbs(latest.visceralFatKg, previous?.visceralFatKg),
                            deltaUnit: "lbs",
                            isLowerBetter: true
                        )
                    }

                    // Scan date
                    Text("Last scan: \(formatDate(latest.scanDate))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let location = latest.location {
                        Text(location)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } else {
                    ContentUnavailableView(
                        "No DEXA Scans",
                        systemImage: "figure.stand",
                        description: Text("Upload a BodySpec PDF or manually enter your scan data.")
                    )
                }

                // Scan history
                if scans.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scan History")
                            .font(.headline)

                        ForEach(scans) { scan in
                            HStack {
                                Text(formatDate(scan.scanDate))
                                    .font(.subheadline)
                                Spacer()
                                if let bf = scan.bodyFatPct {
                                    Text(String(format: "%.1f%%", bf))
                                        .font(.subheadline.monospacedDigit())
                                }
                                if let total = scan.totalMassLbs {
                                    Text(String(format: "%.1f lbs", total))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    showingAddScan = true
                } label: {
                    Label("Add DEXA Scan", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .navigationTitle("Body Composition")
        .sheet(isPresented: $showingAddScan) {
            DEXAEntryView(database: database) {
                loadScans()
            }
        }
        .onAppear { loadScans() }
    }

    private func overviewCard(title: String, value: String, delta: Double?, deltaUnit: String, isLowerBetter: Bool) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            if let delta {
                let isGood = isLowerBetter ? delta < 0 : delta > 0
                Text("\(delta >= 0 ? "+" : "")\(String(format: "%.1f", delta)) \(deltaUnit)")
                    .font(.caption.bold())
                    .foregroundStyle(isGood ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func delta(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return a - b
    }

    private func deltaLbs(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return (a - b) * 2.20462
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    private func loadScans() {
        scans = (try? database.fetchDEXAScans()) ?? []
    }
}

// MARK: - Manual DEXA Entry

struct DEXAEntryView: View {
    let database: AppDatabase
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scanDate = Date()
    @State private var bodyFatPct = ""
    @State private var fatMassLbs = ""
    @State private var leanMassLbs = ""
    @State private var visceralFatLbs = ""
    @State private var boneDensity = ""
    @State private var location = "BodySpec"

    var body: some View {
        NavigationStack {
            Form {
                Section("Scan Info") {
                    DatePicker("Date", selection: $scanDate, displayedComponents: .date)
                    TextField("Location", text: $location)
                }

                Section("Body Composition") {
                    field("Body Fat %", value: $bodyFatPct, unit: "%")
                    field("Fat Mass", value: $fatMassLbs, unit: "lbs")
                    field("Lean Mass", value: $leanMassLbs, unit: "lbs")
                    field("Visceral Fat", value: $visceralFatLbs, unit: "lbs")
                }

                Section("Bone") {
                    field("Bone Density", value: $boneDensity, unit: "g/cm2")
                }
            }
            .navigationTitle("Add DEXA Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveScan()
                        onSave()
                        dismiss()
                    }
                }
            }
        }
    }

    private func field(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 45, alignment: .leading)
        }
    }

    private func saveScan() {
        var scan = DEXAScan(
            scanDate: DateFormatters.dateOnly.string(from: scanDate),
            location: location.isEmpty ? nil : location,
            fatMassKg: Double(fatMassLbs).map { $0 / 2.20462 },
            leanMassKg: Double(leanMassLbs).map { $0 / 2.20462 },
            bodyFatPct: Double(bodyFatPct),
            visceralFatKg: Double(visceralFatLbs).map { $0 / 2.20462 },
            boneDensityTotal: Double(boneDensity)
        )

        if let fat = scan.fatMassKg, let lean = scan.leanMassKg {
            scan.totalMassKg = fat + lean + (scan.boneMassKg ?? 0)
        }

        try? database.saveDEXAScan(&scan)
    }
}
