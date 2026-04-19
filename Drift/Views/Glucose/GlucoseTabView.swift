import SwiftUI
import Charts
import UniformTypeIdentifiers

struct GlucoseTabView: View {
    @State private var readings: [GlucoseReading] = []
    @State private var showingImport = false
    @State private var importResult: String?
    @State private var selectedRange: GlucoseRange = .threeDays
    @State private var dataSource: DataSource = .appleHealth

    enum DataSource: String, CaseIterable {
        case appleHealth = "Apple Health"
        case imported = "Imported"
    }

    enum GlucoseRange: String, CaseIterable {
        case oneDay = "1D"
        case threeDays = "3D"
        case oneWeek = "1W"
        case twoWeeks = "2W"
        case oneMonth = "1M"
        case all = "All"

        var days: Int? {
            switch self {
            case .oneDay: 1
            case .threeDays: 3
            case .oneWeek: 7
            case .twoWeeks: 14
            case .oneMonth: 30
            case .all: nil
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Source toggle
                Picker("Source", selection: $dataSource) {
                    ForEach(DataSource.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: dataSource) { _, _ in loadReadings() }

                // Time range slider
                HStack(spacing: 0) {
                    ForEach(GlucoseRange.allCases, id: \.self) { range in
                        Button {
                            selectedRange = range
                            loadReadings()
                        } label: {
                            Text(range.rawValue)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(selectedRange == range ? Theme.calorieBlue.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                .foregroundStyle(selectedRange == range ? .white : .secondary)
                        }
                    }
                }

                if readings.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.accent.opacity(0.5))
                        Text("No Glucose Data").font(.headline)
                        Text(dataSource == .appleHealth
                             ? "No glucose data in Apple Health for this period."
                             : "Import a CSV file to see glucose data.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                } else {
                    glucoseChart
                    statsCard
                    fastingCard
                    if !spikes.isEmpty {
                        spikesCard
                    }
                }

                if let result = importResult {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Glucose")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingImport = true } label: {
                    Image(systemName: "doc.badge.plus").foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Import glucose data")
            }
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.commaSeparatedText, .plainText]) { handleImport($0) }
        .onAppear { AIScreenTracker.shared.currentScreen = .glucose; loadReadings() }
    }

    // MARK: - Chart with zone coloring

    private var parsedReadings: [(date: Date, value: Double)] {
        let iso = ISO8601DateFormatter()
        return readings.compactMap { r in
            guard let d = iso.date(from: r.timestamp) else { return nil }
            return (d, r.glucoseMgdl)
        }.sorted { $0.date < $1.date }
    }

    private var glucoseChart: some View {
        let data = parsedReadings
        // Wider chart for more days of data
        let dayCount = max(1, Set(data.map { Calendar.current.startOfDay(for: $0.date) }).count)
        let chartWidth = max(UIScreen.main.bounds.width - 64, CGFloat(dayCount) * 120)

        return VStack(alignment: .leading, spacing: 8) {
            if let first = data.first?.date, let last = data.last?.date {
                HStack {
                    Text("Glucose").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(data.count) readings · \(DateFormatters.shortDisplay.string(from: first)) – \(DateFormatters.shortDisplay.string(from: last))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            ScrollView(.horizontal, showsIndicators: true) {

            Chart {
                // Zone backgrounds
                RectangleMark(yStart: .value("", 70), yEnd: .value("", 100))
                    .foregroundStyle(Theme.deficit.opacity(0.06))
                RectangleMark(yStart: .value("", 100), yEnd: .value("", 140))
                    .foregroundStyle(Theme.fatYellow.opacity(0.06))
                RectangleMark(yStart: .value("", 140), yEnd: .value("", 200))
                    .foregroundStyle(Theme.stepsOrange.opacity(0.06))

                // Line colored by zone
                ForEach(data.indices, id: \.self) { i in
                    let color = zoneColor(data[i].value)
                    LineMark(
                        x: .value("", data[i].date),
                        y: .value("", data[i].value)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                // Mark spikes with points
                ForEach(spikeIndices, id: \.self) { i in
                    if i < data.count {
                        PointMark(x: .value("", data[i].date), y: .value("", data[i].value))
                            .foregroundStyle(Theme.surplus)
                            .symbolSize(25)
                    }
                }

                // Mark dips
                ForEach(dipIndices, id: \.self) { i in
                    if i < data.count {
                        PointMark(x: .value("", data[i].date), y: .value("", data[i].value))
                            .foregroundStyle(Theme.calorieBlue)
                            .symbolSize(25)
                    }
                }
            }
            .chartYScale(domain: chartYRange)
            .chartYAxis {
                AxisMarks(values: [70, 100, 140, 180]) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel(format: xAxisFormat).foregroundStyle(.secondary)
                }
            }
            .frame(width: chartWidth, height: 250)
            } // end ScrollView

            // Legend
            HStack(spacing: 10) {
                legendDot("Normal (70-100)", color: Theme.deficit)
                legendDot("Elevated (100-140)", color: Theme.fatYellow)
                legendDot("High (>140)", color: Theme.stepsOrange)
            }
            if !spikes.isEmpty || !dips.isEmpty {
                HStack(spacing: 10) {
                    if !spikes.isEmpty {
                        legendDot("\(spikes.count) spike\(spikes.count == 1 ? "" : "s")", color: Theme.surplus)
                    }
                    if !dips.isEmpty {
                        legendDot("\(dips.count) dip\(dips.count == 1 ? "" : "s")", color: Theme.calorieBlue)
                    }
                }
            }
        }
        .card()
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func zoneColor(_ value: Double) -> Color {
        switch value {
        case ..<70: Theme.calorieBlue
        case 70..<100: Theme.deficit
        case 100..<140: Theme.fatYellow
        default: Theme.stepsOrange
        }
    }

    private var chartYRange: ClosedRange<Double> {
        let vals = parsedReadings.map(\.value)
        let lo = max(50, (vals.min() ?? 60) - 10)
        let hi = min(250, (vals.max() ?? 180) + 10)
        return lo...hi
    }

    private var xAxisFormat: Date.FormatStyle {
        if selectedRange == .oneDay { return .dateTime.hour().minute() }
        if selectedRange == .threeDays { return .dateTime.weekday(.abbreviated).hour() }
        return .dateTime.month(.abbreviated).day()
    }

    // MARK: - Spike / Dip Detection

    /// A spike is a reading >30 mg/dL above the local average (±5 readings)
    /// A dip is a reading >20 mg/dL below the local average
    private struct GlucoseEvent: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let deviation: Double // positive = spike, negative = dip
    }

    private var spikes: [GlucoseEvent] { detectEvents(threshold: 30, direction: .up) }
    private var dips: [GlucoseEvent] { detectEvents(threshold: 20, direction: .down) }

    private var spikeIndices: [Int] { detectEventIndices(threshold: 30, direction: .up) }
    private var dipIndices: [Int] { detectEventIndices(threshold: 20, direction: .down) }

    private enum Direction { case up, down }

    private func detectEventIndices(threshold: Double, direction: Direction) -> [Int] {
        let data = parsedReadings
        guard data.count > 10 else { return [] }
        let windowSize = 5
        var indices: [Int] = []

        for i in windowSize..<(data.count - windowSize) {
            let window = data[(i - windowSize)...(i + windowSize)]
            let avg = window.map(\.value).reduce(0, +) / Double(window.count)
            let deviation = data[i].value - avg

            if direction == .up && deviation > threshold {
                // Only mark if it's a local max
                if data[i].value >= data[max(0, i-1)].value && data[i].value >= data[min(data.count-1, i+1)].value {
                    indices.append(i)
                }
            } else if direction == .down && deviation < -threshold {
                if data[i].value <= data[max(0, i-1)].value && data[i].value <= data[min(data.count-1, i+1)].value {
                    indices.append(i)
                }
            }
        }

        // Deduplicate close indices (within 3 readings)
        var filtered: [Int] = []
        for idx in indices {
            if filtered.isEmpty || idx - (filtered.last ?? 0) > 3 {
                filtered.append(idx)
            }
        }
        return filtered
    }

    private func detectEvents(threshold: Double, direction: Direction) -> [GlucoseEvent] {
        let data = parsedReadings
        return detectEventIndices(threshold: threshold, direction: direction).compactMap { i in
            guard i < data.count else { return nil }
            let windowSize = 5
            let window = data[max(0, i - windowSize)...min(data.count - 1, i + windowSize)]
            let avg = window.map(\.value).reduce(0, +) / Double(window.count)
            return GlucoseEvent(date: data[i].date, value: data[i].value, deviation: data[i].value - avg)
        }
    }

    // MARK: - Stats

    private var statsCard: some View {
        let v = readings.map(\.glucoseMgdl)
        let avg = v.isEmpty ? 0 : v.reduce(0, +) / Double(v.count)
        let inRange = v.filter { $0 >= 70 && $0 <= 140 }.count
        let inRangePct = v.isEmpty ? 0 : Double(inRange) / Double(v.count) * 100
        return HStack(spacing: 10) {
            statPill("Average", value: String(format: "%.0f", avg), unit: "mg/dL")
            statPill("Range", value: "\(Int(v.min() ?? 0))-\(Int(v.max() ?? 0))", unit: "mg/dL")
            statPill("In Zone", value: String(format: "%.0f%%", inRangePct), unit: "70-140")
        }
    }

    private func statPill(_ label: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.bold).monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).card()
    }

    // MARK: - Fasting Analysis

    private var fastingCard: some View {
        let data = parsedReadings
        guard data.count > 10 else { return AnyView(EmptyView()) }

        // Find windows where glucose < 100 mg/dL for 1+ hour
        // Ignore gaps >15 min between readings (no data = not fasting)
        var fastingWindows: [(start: Date, end: Date, avgGlucose: Double)] = []
        var windowStart: Date? = nil
        var windowValues: [Double] = []
        var lastDate: Date? = nil

        for (date, value) in data {
            // If gap > 15 min from last reading, break the window (no data ≠ fasting)
            if let prev = lastDate, date.timeIntervalSince(prev) > 900 {
                if let start = windowStart, windowValues.count >= 12 {
                    fastingWindows.append((start, prev, windowValues.reduce(0, +) / Double(windowValues.count)))
                }
                windowStart = nil; windowValues = []
            }
            lastDate = date

            if value < 100 {
                if windowStart == nil { windowStart = date }
                windowValues.append(value)
            } else {
                if let start = windowStart, windowValues.count >= 12 {
                    fastingWindows.append((start, date, windowValues.reduce(0, +) / Double(windowValues.count)))
                }
                windowStart = nil; windowValues = []
            }
        }
        if let start = windowStart, windowValues.count >= 12, let last = data.last?.date {
            fastingWindows.append((start, last, windowValues.reduce(0, +) / Double(windowValues.count)))
        }

        let totalFastingHours = fastingWindows.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) / 3600 }
        // Only count time where we have data (not gaps)
        var monitoredHours = 0.0
        for i in 1..<data.count {
            let gap = data[i].date.timeIntervalSince(data[i-1].date)
            if gap <= 900 { monitoredHours += gap / 3600 } // only count continuous data
        }
        let fastingPct = monitoredHours > 0 ? totalFastingHours / monitoredHours * 100 : 0

        // Daily average: total fasting divided by ALL monitored days (not just fasting days)
        let cal = Calendar.current
        let allDays = Set(data.map { cal.startOfDay(for: $0.date) })
        let totalDays = max(1, allDays.count)
        let avgDailyFasting = totalFastingHours / Double(totalDays)

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Fasting / Fat Burning").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.0f%%", fastingPct))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(fastingPct > 50 ? Theme.deficit : Theme.fatYellow)
                    Text("of monitored time").font(.caption2).foregroundStyle(.tertiary)
                }

                HStack(spacing: 8) {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1fh", avgDailyFasting)).font(.subheadline.weight(.bold).monospacedDigit())
                        Text("Avg Daily").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).card()

                    VStack(spacing: 2) {
                        Text(String(format: "%.1fh", totalFastingHours)).font(.subheadline.weight(.bold).monospacedDigit())
                        Text("Total").font(.caption2).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).card()

                    if let longest = fastingWindows.max(by: { $0.end.timeIntervalSince($0.start) < $1.end.timeIntervalSince($1.start) }) {
                        VStack(spacing: 2) {
                            Text(String(format: "%.1fh", longest.end.timeIntervalSince(longest.start) / 3600))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                            Text("Longest").font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).card()
                    }
                }

                Text("Periods where glucose stayed below 100 mg/dL for 1+ hour. Your body is likely burning fat during these windows.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .card()
        )
    }

    // MARK: - Spikes Card

    private var spikesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Glucose Events").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            ForEach(spikes.prefix(5)) { spike in
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(Theme.surplus).font(.caption)
                    Text("Spike to \(Int(spike.value)) mg/dL")
                        .font(.caption)
                    Spacer()
                    Text("+\(Int(spike.deviation)) above avg")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.surplus)
                    Text(formatEventTime(spike.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }

            ForEach(dips.prefix(3)) { dip in
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(Theme.calorieBlue).font(.caption)
                    Text("Dip to \(Int(dip.value)) mg/dL")
                        .font(.caption)
                    Spacer()
                    Text("\(Int(abs(dip.deviation))) below avg")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.calorieBlue)
                    Text(formatEventTime(dip.date))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .card()
    }

    private func formatEventTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = selectedRange == .oneDay ? "h:mm a" : "M/d h:mm a"
        return f.string(from: date)
    }

    // MARK: - Data Loading

    private func loadReadings() {
        Task {
            let cal = Calendar.current
            let end = Date()
            let start: Date

            if let days = selectedRange.days, let d = cal.date(byAdding: .day, value: -days, to: end) {
                start = d
            } else {
                start = cal.date(byAdding: .year, value: -1, to: end) ?? end
            }

            if dataSource == .appleHealth {
                readings = (try? await HealthKitService.shared.fetchGlucoseReadings(from: start, to: end)) ?? []
            } else {
                let startStr = ISO8601DateFormatter().string(from: start)
                let endStr = ISO8601DateFormatter().string(from: end)
                readings = GlucoseService.fetchReadings(from: startStr, to: endStr)
            }
            Log.glucose.info("Loaded \(readings.count) glucose readings for \(selectedRange.rawValue)")
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            do {
                let r = try GlucoseService.importLingoCSV(url: url)
                importResult = "Imported \(r.imported), skipped \(r.skipped), errors \(r.errors)"
                dataSource = .imported
                loadReadings()
            } catch { importResult = "Failed: \(error.localizedDescription)" }
        case .failure(let error): importResult = "File error: \(error.localizedDescription)"
        }
    }
}
