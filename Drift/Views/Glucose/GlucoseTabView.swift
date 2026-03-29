import SwiftUI
import Charts
import UniformTypeIdentifiers

struct GlucoseTabView: View {
    @State private var readings: [GlucoseReading] = []
    @State private var showingImport = false
    @State private var importResult: String?
    @State private var selectedDate = Date()
    @State private var dataSource: DataSource = .appleHealth
    private let database = AppDatabase.shared

    enum DataSource: String, CaseIterable {
        case appleHealth = "Apple Health"
        case imported = "Imported"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Picker("Source", selection: $dataSource) {
                        ForEach(DataSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .onChange(of: dataSource) { _, _ in loadReadings() }

                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .onChange(of: selectedDate) { _, _ in loadReadings() }

                if readings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.accent.opacity(0.5))
                        Text("No Glucose Data")
                            .font(.headline)
                        Text(dataSource == .appleHealth
                             ? "No glucose data in Apple Health for this date."
                             : "Import a Lingo CSV to see glucose data.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                } else {
                    glucoseChart
                    statsCard
                }

                Button { showingImport = true } label: {
                    Label("Import Lingo CSV", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.bordered)

                if let result = importResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .background(Theme.background)
        .navigationTitle("Glucose")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.commaSeparatedText, .plainText]) { handleImport($0) }
        .onAppear { loadReadings() }
    }

    private var glucoseChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Glucose").font(.subheadline.weight(.semibold))
            Chart {
                RectangleMark(yStart: .value("", 70), yEnd: .value("", 100)).foregroundStyle(Theme.deficit.opacity(0.08))
                RectangleMark(yStart: .value("", 100), yEnd: .value("", 140)).foregroundStyle(Theme.fatYellow.opacity(0.08))
                RectangleMark(yStart: .value("", 140), yEnd: .value("", 200)).foregroundStyle(Theme.stepsOrange.opacity(0.08))
                ForEach(readings, id: \.timestamp) { reading in
                    if let date = ISO8601DateFormatter().date(from: reading.timestamp) {
                        LineMark(x: .value("", date), y: .value("", reading.glucoseMgdl))
                            .foregroundStyle(Theme.calorieBlue).lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .chartYScale(domain: 50...200)
            .chartYAxis {
                AxisMarks(values: [70, 100, 140, 180]) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(.secondary)
                }
            }
            .frame(height: 250)
            HStack(spacing: 12) {
                HStack(spacing: 3) { RoundedRectangle(cornerRadius: 2).fill(Theme.deficit.opacity(0.3)).frame(width: 10, height: 10); Text("Normal").font(.caption2).foregroundStyle(.secondary) }
                HStack(spacing: 3) { RoundedRectangle(cornerRadius: 2).fill(Theme.fatYellow.opacity(0.3)).frame(width: 10, height: 10); Text("Elevated").font(.caption2).foregroundStyle(.secondary) }
                HStack(spacing: 3) { RoundedRectangle(cornerRadius: 2).fill(Theme.stepsOrange.opacity(0.3)).frame(width: 10, height: 10); Text("High").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .card()
    }

    private var statsCard: some View {
        let v = readings.map(\.glucoseMgdl)
        let avg = v.reduce(0, +) / Double(v.count)
        let inRange = v.filter { $0 >= 70 && $0 <= 140 }.count
        return HStack(spacing: 10) {
            statPill("Avg", value: String(format: "%.0f", avg))
            statPill("Min", value: String(format: "%.0f", v.min() ?? 0))
            statPill("Max", value: String(format: "%.0f", v.max() ?? 0))
            statPill("In Range", value: String(format: "%.0f%%", Double(inRange) / Double(v.count) * 100))
        }
    }

    private func statPill(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).card()
    }

    private func loadReadings() {
        Task {
            if dataSource == .appleHealth {
                let cal = Calendar.current
                let start = cal.startOfDay(for: selectedDate)
                let end = cal.date(byAdding: .day, value: 1, to: start)!
                readings = (try? await HealthKitService.shared.fetchGlucoseReadings(from: start, to: end)) ?? []
            } else {
                let d = DateFormatters.dateOnly.string(from: selectedDate)
                let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                let dayAfter = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                let start = DateFormatters.dateOnly.string(from: dayBefore) + "T12:00:00Z"
                let end = DateFormatters.dateOnly.string(from: dayAfter) + "T12:00:00Z"
                readings = (try? database.fetchGlucoseReadings(from: start, to: end)) ?? []
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let r = try CGMImportService.importLingoCSV(url: url, database: database)
                importResult = "Imported \(r.imported), skipped \(r.skipped), errors \(r.errors)"
                dataSource = .imported
                loadReadings()
            } catch { importResult = "Failed: \(error.localizedDescription)" }
        case .failure(let error): importResult = "File error: \(error.localizedDescription)"
        }
    }
}
