import SwiftUI
import Charts
import UniformTypeIdentifiers

struct DEXAOverviewView: View {
    @State private var scans: [DEXAScan] = []
    @State private var selectedScanRegions: [DEXARegion] = []
    @State private var showingImportPDF = false
    @State private var showingManualEntry = false
    @State private var isImporting = false
    @State private var importMessage: ImportMessage?
    private let database = AppDatabase.shared

    struct ImportMessage: Identifiable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let latest = scans.first {
                    let previous = scans.count > 1 ? scans[1] : nil
                    overviewCards(latest: latest, previous: previous)

                    if !selectedScanRegions.isEmpty {
                        regionalBreakdown
                        muscleBalance
                    }

                    if scans.count > 1 {
                        trendCharts
                        scanComparison
                    }

                    scanHistory
                } else if !isImporting {
                    emptyState
                }

                // Import area
                VStack(spacing: 10) {
                    if isImporting {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Analysing PDF...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .card()
                    }

                    if let msg = importMessage {
                        HStack(spacing: 8) {
                            Image(systemName: msg.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(msg.isError ? Theme.surplus : Theme.deficit)
                            Text(msg.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    importButtons
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
                Text("Latest Scan").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(formatDate(latest.scanDate)).font(.caption).foregroundStyle(.tertiary)
                if let loc = latest.location {
                    Text("· \(loc)").font(.caption2).foregroundStyle(.tertiary)
                }
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

            // Extra info row
            HStack(spacing: 12) {
                if let rmr = latest.rmrCalories {
                    miniStat("RMR", value: "\(Int(rmr)) cal/day")
                }
                if let ag = latest.agRatio {
                    miniStat("A/G Ratio", value: String(format: "%.2f", ag))
                }
                if let total = latest.totalMassLbs {
                    miniStat("Total", value: String(format: "%.1f lbs", total))
                }
            }
        }
    }

    private func overviewCard(_ title: String, value: String, delta: Double?, deltaUnit: String, lowerBetter: Bool) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold).monospacedDigit())
            if let d = delta {
                let good = lowerBetter ? d < -0.01 : d > 0.01
                let neutral = abs(d) < 0.01
                let arrow = d < -0.01 ? "\u{2193}" : d > 0.01 ? "\u{2191}" : ""
                Text("\(arrow) \(abs(d) < 0.05 ? "no change" : "\(String(format: "%.1f", abs(d))) \(deltaUnit)")")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(neutral ? .secondary : good ? Theme.deficit : Theme.surplus)
            } else {
                Text("vs prev scan")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity).card()
    }

    private func miniStat(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.caption.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity).card()
    }

    // MARK: - Regional Breakdown

    private var regionalBreakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Regional Breakdown").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            let arms = selectedScanRegions.first { $0.region == "arms" }
            let legs = selectedScanRegions.first { $0.region == "legs" }
            let trunk = selectedScanRegions.first { $0.region == "trunk" }
            let android = selectedScanRegions.first { $0.region == "android" }
            let gynoid = selectedScanRegions.first { $0.region == "gynoid" }

            VStack(spacing: 0) {
                regionRow("Arms", region: arms)
                Divider().overlay(Color.white.opacity(0.05))
                regionRow("Trunk", region: trunk)
                Divider().overlay(Color.white.opacity(0.05))
                regionRow("Legs", region: legs)
                Divider().overlay(Color.white.opacity(0.05))
                regionRow("Android", region: android)
                Divider().overlay(Color.white.opacity(0.05))
                regionRow("Gynoid", region: gynoid)
            }
            .card()
        }
    }

    private func regionRow(_ label: String, region: DEXARegion?) -> some View {
        HStack {
            Text(label).font(.subheadline.weight(.medium)).frame(width: 70, alignment: .leading)
            Spacer()
            if let r = region {
                Text(r.fatPct.map { String(format: "%.1f%%", $0) } ?? "--")
                    .font(.subheadline.weight(.bold).monospacedDigit()).frame(width: 45)
                HStack(spacing: 6) {
                    VStack(spacing: 1) {
                        Text(r.fatMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.surplus)
                        Text("fat").font(.caption2).foregroundStyle(.tertiary)
                    }
                    VStack(spacing: 1) {
                        Text(r.leanMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.deficit)
                        Text("lean").font(.caption2).foregroundStyle(.tertiary)
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

        let hasData = [rArm, lArm, rLeg, lLeg].compactMap({ $0 }).count > 0

        return Group {
            if hasData {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Muscle Balance (L/R)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        balanceHeader
                        Divider().overlay(Color.white.opacity(0.05))
                        balanceRow("R Arm", region: rArm)
                        Divider().overlay(Color.white.opacity(0.05))
                        balanceRow("L Arm", region: lArm)
                        Divider().overlay(Color.white.opacity(0.05))
                        balanceRow("R Leg", region: rLeg)
                        Divider().overlay(Color.white.opacity(0.05))
                        balanceRow("L Leg", region: lLeg)
                    }
                    .card()
                }
            }
        }
    }

    private var balanceHeader: some View {
        HStack {
            Text("").frame(width: 50)
            Spacer()
            Text("Fat%").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).frame(width: 40)
            Text("Fat").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).frame(width: 35)
            Text("Lean").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).frame(width: 35)
            Text("Total").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary).frame(width: 35)
        }
        .padding(.vertical, 4)
    }

    private func balanceRow(_ label: String, region: DEXARegion?) -> some View {
        HStack {
            Text(label).font(.subheadline.weight(.medium)).frame(width: 50, alignment: .leading)
            Spacer()
            if let r = region {
                Text(r.fatPct.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.caption.monospacedDigit()).frame(width: 40)
                Text(r.fatMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.surplus).frame(width: 35)
                Text(r.leanMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.deficit).frame(width: 35)
                Text(r.totalMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 35)
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Trend Charts

    private var trendCharts: some View {
        let sorted = scans.sorted { $0.scanDate < $1.scanDate }
        let df: DateFormatter = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
        }()

        return VStack(alignment: .leading, spacing: 14) {
            Text("Trends").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            trendChart("Body Fat %", data: sorted.compactMap { s in
                guard let d = df.date(from: s.scanDate), let v = s.bodyFatPct else { return nil }; return (d, v)
            }, unit: "%", color: Theme.stepsOrange)

            trendChart("Fat Mass", data: sorted.compactMap { s in
                guard let d = df.date(from: s.scanDate), let v = s.fatMassLbs else { return nil }; return (d, v)
            }, unit: "lbs", color: Theme.surplus)

            trendChart("Lean Mass", data: sorted.compactMap { s in
                guard let d = df.date(from: s.scanDate), let v = s.leanMassLbs else { return nil }; return (d, v)
            }, unit: "lbs", color: Theme.deficit)
        }
    }

    private func trendChart(_ title: String, data: [(Date, Double)], unit: String, color: Color) -> some View {
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
                            .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2))
                        PointMark(x: .value("", data[i].0), y: .value("", data[i].1))
                            .foregroundStyle(color).symbolSize(30)
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
            Text("All Scans").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            VStack(spacing: 0) {
                HStack {
                    Text("Date").font(.caption2.weight(.semibold)).frame(width: 65, alignment: .leading)
                    Text("BF%").font(.caption2.weight(.semibold)).frame(width: 38)
                    Text("Fat").font(.caption2.weight(.semibold)).frame(width: 38)
                    Text("Lean").font(.caption2.weight(.semibold)).frame(width: 38)
                    Text("Total").font(.caption2.weight(.semibold)).frame(width: 42)
                    Text("BMC").font(.caption2.weight(.semibold)).frame(width: 32)
                }
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)

                ForEach(scans, id: \.id) { scan in
                    HStack {
                        Text(formatDateShort(scan.scanDate))
                            .font(.caption.monospacedDigit()).frame(width: 65, alignment: .leading)
                        Text(scan.bodyFatPct.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.weight(.bold).monospacedDigit()).frame(width: 38)
                        Text(scan.fatMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.surplus).frame(width: 38)
                        Text(scan.leanMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.monospacedDigit()).foregroundStyle(Theme.deficit).frame(width: 38)
                        Text(scan.totalMassLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption.monospacedDigit()).frame(width: 42)
                        Text(scan.bmcLbs.map { String(format: "%.1f", $0) } ?? "--")
                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 32)
                    }
                    .padding(.vertical, 3)
                }
            }
            .card()
        }
    }


    // MARK: - Scan History (delete support)

    private var scanHistory: some View { EmptyView() } // Merged into scanComparison

    // MARK: - Empty + Import

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.stand")
                .font(.system(size: 48)).foregroundStyle(Theme.accent.opacity(0.5))
            Text("No DEXA Scans").font(.headline)
            Text("Upload a BodySpec PDF report to see your body composition data with trends and regional breakdown.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .padding(.top, 40)
    }

    private var importButtons: some View {
        HStack(spacing: 10) {
            Button { showingImportPDF = true } label: {
                Label(scans.isEmpty ? "Upload BodySpec PDF" : "Upload Another PDF", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            .disabled(isImporting)

            Button { showingManualEntry = true } label: {
                Label("Manual", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func handlePDFImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            isImporting = true
            importMessage = nil

            // Run parsing on background to not block UI
            Task {
                do {
                    let parsedScans = try BodySpecPDFParser.parse(url: url)

                    if parsedScans.isEmpty {
                        importMessage = ImportMessage(text: "No BodySpec scan data found in this PDF. Try manual entry instead.", isError: true)
                        isImporting = false
                        return
                    }

                    let scansWithData = parsedScans.filter { $0.bodyFatPct != nil || $0.fatMassLbs != nil }
                    let count = try database.importBodySpecScans(parsedScans)

                    let details = parsedScans.map { "\(formatDateShort($0.scanDate)): \($0.bodyFatPct.map { String(format: "%.1f%%", $0) } ?? "no BF%")" }.joined(separator: ", ")

                    importMessage = ImportMessage(
                        text: "Imported \(count) scans (\(details)). \(parsedScans.first?.regions.count ?? 0) regions for latest scan.",
                        isError: false
                    )

                    loadScans()
                } catch {
                    importMessage = ImportMessage(text: "Import failed: \(error.localizedDescription)", isError: true)
                    Log.bodyComp.error("PDF import failed: \(error.localizedDescription)")
                }
                isImporting = false
            }

        case .failure(let error):
            importMessage = ImportMessage(text: "Could not open file: \(error.localizedDescription)", isError: true)
        }
    }

    private func loadScans() {
        scans = (try? database.fetchDEXAScans()) ?? []
        if let latestId = scans.first?.id {
            selectedScanRegions = (try? database.fetchDEXARegions(forScanId: latestId)) ?? []
        } else {
            selectedScanRegions = []
        }
        Log.bodyComp.info("Loaded \(scans.count) scans, \(selectedScanRegions.count) regions for latest")
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
            .navigationTitle("Add DEXA Scan").navigationBarTitleDisplayMode(.inline)
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
            scanDate: DateFormatters.dateOnly.string(from: scanDate), location: "BodySpec",
            fatMassKg: Double(fatMassLbs).map { $0 / 2.20462 },
            leanMassKg: Double(leanMassLbs).map { $0 / 2.20462 },
            bodyFatPct: Double(bodyFatPct),
            visceralFatKg: Double(visceralFatLbs).map { $0 / 2.20462 },
            boneDensityTotal: Double(boneDensity)
        )
        if let fat = scan.fatMassKg, let lean = scan.leanMassKg { scan.totalMassKg = fat + lean }
        try? database.saveDEXAScan(&scan)
    }
}
