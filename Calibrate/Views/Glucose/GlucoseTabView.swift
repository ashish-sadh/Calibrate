import SwiftUI
import Charts
import UniformTypeIdentifiers

struct GlucoseTabView: View {
    @State private var readings: [GlucoseReading] = []
    @State private var showingImport = false
    @State private var importResult: String?
    private let database = AppDatabase.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if readings.isEmpty {
                    ContentUnavailableView(
                        "No Glucose Data",
                        systemImage: "waveform.path.ecg",
                        description: Text("Import a Lingo CSV export to see your glucose data.")
                    )
                } else {
                    glucoseChart
                }

                Button {
                    showingImport = true
                } label: {
                    Label("Import Lingo CSV", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                if let result = importResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding()
                }
            }
            .padding()
        }
        .navigationTitle("Glucose")
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            handleImport(result)
        }
        .onAppear { loadReadings() }
    }

    private var glucoseChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Glucose")
                .font(.headline)

            Chart {
                // Color band reference zones
                RectangleMark(yStart: .value("", 70), yEnd: .value("", 100))
                    .foregroundStyle(.green.opacity(0.1))
                RectangleMark(yStart: .value("", 100), yEnd: .value("", 140))
                    .foregroundStyle(.yellow.opacity(0.1))
                RectangleMark(yStart: .value("", 140), yEnd: .value("", 200))
                    .foregroundStyle(.orange.opacity(0.1))

                ForEach(readings, id: \.id) { reading in
                    if let date = ISO8601DateFormatter().date(from: reading.timestamp) {
                        LineMark(
                            x: .value("Time", date),
                            y: .value("Glucose", reading.glucoseMgdl)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .chartYScale(domain: 60...200)
            .chartYAxis {
                AxisMarks(values: [70, 100, 140, 180]) { value in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 250)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }

            do {
                let importResult = try CGMImportService.importLingoCSV(url: url, database: database)
                self.importResult = "Imported \(importResult.imported) readings, skipped \(importResult.skipped), errors \(importResult.errors)"
                loadReadings()
            } catch {
                self.importResult = "Import failed: \(error.localizedDescription)"
            }
        case .failure(let error):
            self.importResult = "Failed to open file: \(error.localizedDescription)"
        }
    }

    private func loadReadings() {
        let today = DateFormatters.todayString
        let start = today + "T00:00:00Z"
        let end = today + "T23:59:59Z"
        readings = (try? database.fetchGlucoseReadings(from: start, to: end)) ?? []

        // If no today data, load last 24 hours
        if readings.isEmpty {
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            let yStart = ISO8601DateFormatter().string(from: yesterday)
            let yEnd = ISO8601DateFormatter().string(from: Date())
            readings = (try? database.fetchGlucoseReadings(from: yStart, to: yEnd)) ?? []
        }
    }
}
