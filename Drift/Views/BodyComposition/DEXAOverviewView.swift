import SwiftUI
import Charts
import UniformTypeIdentifiers

struct DEXAOverviewView: View {
    @State private var scans: [DEXAScan] = []
    @State private var selectedScanRegions: [DEXARegion] = []
    @State private var showingImportPDF = false
    @State private var showingManualEntry = false
    @State private var importResult: String?
    private let database = AppDatabase.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let latest = scans.first {
                    let previous = scans.count > 1 ? scans[1] : nil

                    // Overview cards
                    overviewCards(latest: latest, previous: previous)

                    // Regional breakdown
                    if !selectedScanRegions.isEmpty {
                        regionalBreakdown
                        muscleBalance
                    }

                    // Trend charts
                    if scans.count > 1 {
                        trendCharts
                        scanComparison
                    }

                    scanHistory
                } else {
                    emptyState
                }

                // Import buttons
                importButtons

                if let result = importResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Body Composition")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fileImporter(isPresented: $showingImportPDF, allowedContentTypes: [.pdf]) { handlePDFImport($0) }
        .sheet(isPresented: $showingManualEntry) {
            DEXAEntryView(database: database) { loadScans() }
        }
        .onAppear { loadScans() }
    }

    // MARK: - Overview Cards

    private func overviewCards(latest: DEXAScan, previous: DEXAScan?) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Latest Scan")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(formatDate(latest.scanDate))
                    .font(.caption).foregroundStyle(.tertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                overviewCard("Body Fat", value: latest.bodyFatPct.map { String(format: "%.1f%%", $0) } ?? "--",
                             delta: delta(latest.bodyFatPct, previous?.bodyFatPct), deltaUnit: "%", lowerBetter: true)
                overviewCard("Lean Mass", value: latest.leanMassLbs.map { String(format: "%.1f lbs", $0) } ?? "--",
                             delta: deltaLbs(latest.leanMassKg, previous?.leanMassKg), deltaUnit: "lbs", lowerBetter: false)
                overviewCard("Fat Mass", value: latest.fatMassLbs.map { String(format: "%.1f lbs", $0) } ?? "--",
                             delta: deltaLbs(latest.fatMassKg, previous?.fatMassKg), deltaUnit: "lbs", lowerBetter: true)
                overviewCard("Visceral Fat", value: latest.visceralFatLbs.map { String(format: "%.1f lbs", $0) } ?? "--",
                             delta: deltaLbs(latest.visceralFatKg, previous?.visceralFatKg), deltaUnit: "lbs", lowerBetter: true)
            }
        }
    }

    private func overviewCard(_ title: String, value: String, delta: Double?, deltaUnit: String, lowerBetter: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            if let d = delta {
                let good = lowerBetter ? d < 0 : d > 0
                Text("\(d >= 0 ? "+" : "")\(String(format: "%.1f", d)) \(deltaUnit)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(good ? Theme.deficit : Theme.surplus)
            }
        }
        .frame(maxWidth: .infinity).card()
    }

    // MARK: - Regional Breakdown (Upper/Lower Body)

    private var regionalBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Regional Breakdown")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            let arms = selectedScanRegions.first { $0.region == "arms" }
            let legs = selectedScanRegions.first { $0.region == "legs" }
            let trunk = selectedScanRegions.first { $0.region == "trunk" }

            VStack(spacing: 0) {
                regionRow("Arms (Upper)", region: arms)
                Divider().overlay(Color.white.opacity(0.05))
                regionRow("Trunk", region: trunk)
                Divider().overlay(Color.white.opacity(0.05))
                regionRow("Legs (Lower)", region: legs)
            }
            .card()
        }
    }

    private func regionRow(_ label: String, region: DEXARegion?) -> some View {
        HStack {
            Text(label).font(.subheadline.weight(.medium)).frame(width: 100, alignment: .leading)
            Spacer()
            if let r = region {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(r.fatPct.map { String(format: "%.1f%%", $0) } ?? "--")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    HStack(spacing: 8) {
                        Text("F: \(r.fatMassLbs.map { String(format: "%.1f", $0) } ?? "--")")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.surplus)
                        Text("L: \(r.leanMassLbs.map { String(format: "%.1f", $0) } ?? "--")")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.deficit)
                    }
                }
            } else {
                Text("--").foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Muscle Balance (L/R)

    private var muscleBalance: some View {
        let rArm = selectedScanRegions.first { $0.region == "r_arm" }
        let lArm = selectedScanRegions.first { $0.region == "l_arm" }
        let rLeg = selectedScanRegions.first { $0.region == "r_leg" }
        let lLeg = selectedScanRegions.first { $0.region == "l_leg" }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Muscle Balance (L/R)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            VStack(spacing: 0) {
                balanceRow("Right Arm", region: rArm)
                Divider().overlay(Color.white.opacity(0.05))
                balanceRow("Left Arm", region: lArm)
                Divider().overlay(Color.white.opacity(0.05))
                balanceRow("Right Leg", region: rLeg)
                Divider().overlay(Color.white.opacity(0.05))
                balanceRow("Left Leg", region: lLeg)
            }
            .card()
        }
    }

    private func balanceRow(_ label: String, region: DEXARegion?) -> some View {
        HStack {
            Text(label).font(.subheadline).frame(width: 80, alignment: .leading)
            Spacer()
            if let r = region {
                Text(r.fatPct.map { String(format: "%.1f%%", $0) } ?? "--")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 45)
                Text(r.fatMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.caption.monospacedDigit()).frame(width: 35).foregroundStyle(Theme.surplus)
                Text("F").font(.caption2).foregroundStyle(.tertiary)
                Text(r.leanMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.caption.weight(.bold).monospacedDigit()).frame(width: 35).foregroundStyle(Theme.deficit)
                Text("L").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Trend Charts

    private var trendCharts: some View {
        let sorted = scans.sorted { $0.scanDate < $1.scanDate }
        let dateFormatter: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
        }()

        return VStack(alignment: .leading, spacing: 14) {
            Text("Trends")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            // Body Fat % trend
            trendChart(title: "Body Fat %", data: sorted.compactMap { s in
                guard let d = dateFormatter.date(from: s.scanDate), let v = s.bodyFatPct else { return nil }
                return (d, v)
            }, unit: "%", color: Theme.stepsOrange)

            // Fat Mass trend
            trendChart(title: "Fat Mass", data: sorted.compactMap { s in
                guard let d = dateFormatter.date(from: s.scanDate), let v = s.fatMassLbs else { return nil }
                return (d, v)
            }, unit: "lbs", color: Theme.surplus)

            // Lean Mass trend
            trendChart(title: "Lean Mass", data: sorted.compactMap { s in
                guard let d = dateFormatter.date(from: s.scanDate), let v = s.leanMassLbs else { return nil }
                return (d, v)
            }, unit: "lbs", color: Theme.deficit)

            // Visceral Fat trend
            trendChart(title: "Visceral Fat", data: sorted.compactMap { s in
                guard let d = dateFormatter.date(from: s.scanDate), let v = s.visceralFatLbs else { return nil }
                return (d, v)
            }, unit: "lbs", color: Theme.fatYellow)
        }
    }

    private func trendChart(title: String, data: [(Date, Double)], unit: String, color: Color) -> some View {
        guard data.count >= 2 else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.caption.weight(.semibold))
                    Spacer()
                    if let first = data.first?.1, let last = data.last?.1 {
                        let diff = last - first
                        Text("\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff)) \(unit)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(diff < 0 ? Theme.deficit : Theme.surplus)
                    }
                }

                Chart {
                    ForEach(data.indices, id: \.self) { i in
                        LineMark(x: .value("", data[i].0), y: .value("", data[i].1))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("", data[i].0), y: .value("", data[i].1))
                            .foregroundStyle(color)
                            .symbolSize(30)
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits)).foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2))
                        AxisValueLabel().foregroundStyle(.secondary)
                    }
                }
                .frame(height: 120)
            }
            .card()
        )
    }

    // MARK: - Scan Comparison

    private var scanComparison: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Progress Over Time")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack {
                    Text("Date").font(.caption.weight(.semibold)).frame(width: 70, alignment: .leading)
                    Text("BF%").font(.caption.weight(.semibold)).frame(width: 40)
                    Text("Fat").font(.caption.weight(.semibold)).frame(width: 45)
                    Text("Lean").font(.caption.weight(.semibold)).frame(width: 45)
                    Text("Total").font(.caption.weight(.semibold)).frame(width: 50)
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

                ForEach(scans, id: \.id) { scan in
                    HStack {
                        Text(formatDateShort(scan.scanDate))
                            .font(.caption.monospacedDigit()).frame(width: 70, alignment: .leading)
                        Text(scan.bodyFatPct.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.weight(.bold).monospacedDigit()).frame(width: 40)
                        Text(scan.fatMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.monospacedDigit()).frame(width: 45).foregroundStyle(Theme.surplus)
                        Text(scan.leanMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.monospacedDigit()).frame(width: 45).foregroundStyle(Theme.deficit)
                        Text(scan.totalMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.monospacedDigit()).frame(width: 50)
                    }
                    .padding(.vertical, 4)
                }
            }
            .card()
        }
    }

    // MARK: - Scan History

    private var scanHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("All Scans (\(scans.count))")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            ForEach(scans, id: \.id) { scan in
                HStack {
                    Text(formatDate(scan.scanDate)).font(.subheadline)
                    Spacer()
                    if let bf = scan.bodyFatPct {
                        Text(String(format: "%.1f%%", bf)).font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    if let total = scan.totalMassLbs {
                        Text(String(format: "%.1f lbs", total)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .card()
        }
    }

    // MARK: - Empty + Import

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.stand")
                .font(.system(size: 48)).foregroundStyle(Theme.accent.opacity(0.5))
            Text("No DEXA Scans").font(.headline)
            Text("Upload a BodySpec PDF or manually enter scan data.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private var importButtons: some View {
        HStack(spacing: 10) {
            Button { showingImportPDF = true } label: {
                Label("Upload PDF", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)

            Button { showingManualEntry = true } label: {
                Label("Manual Entry", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func handlePDFImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let parsedScans = try BodySpecPDFParser.parse(url: url)
                guard !parsedScans.isEmpty else {
                    importResult = "No scan data found in PDF"
                    return
                }
                let count = try database.importBodySpecScans(parsedScans)
                importResult = "Imported \(count) scans from PDF"
                loadScans()
            } catch {
                importResult = "PDF import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            importResult = "File error: \(error.localizedDescription)"
        }
    }

    private func loadScans() {
        scans = (try? database.fetchDEXAScans()) ?? []
        if let latestId = scans.first?.id {
            selectedScanRegions = (try? database.fetchDEXARegions(forScanId: latestId)) ?? []
        }
    }

    // MARK: - Helpers

    private func delta(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }; return a - b
    }

    private func deltaLbs(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }; return (a - b) * 2.20462
    }

    private func formatDate(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        f.dateFormat = "MMM d, yyyy"; return f.string(from: d)
    }

    private func formatDateShort(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: s) else { return s }
        f.dateFormat = "M/d/yy"; return f.string(from: d)
    }
}

// MARK: - Manual Entry

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Scan Info") {
                    DatePicker("Date", selection: $scanDate, displayedComponents: .date)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(); onSave(); dismiss() } }
            }
        }
    }

    private func field(_ label: String, value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label); Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 45, alignment: .leading)
        }
    }

    private func save() {
        var scan = DEXAScan(
            scanDate: DateFormatters.dateOnly.string(from: scanDate),
            location: "BodySpec",
            fatMassKg: Double(fatMassLbs).map { $0 / 2.20462 },
            leanMassKg: Double(leanMassLbs).map { $0 / 2.20462 },
            bodyFatPct: Double(bodyFatPct),
            visceralFatKg: Double(visceralFatLbs).map { $0 / 2.20462 },
            boneDensityTotal: Double(boneDensity)
        )
        if let fat = scan.fatMassKg, let lean = scan.leanMassKg {
            scan.totalMassKg = fat + lean
        }
        try? database.saveDEXAScan(&scan)
    }
}
