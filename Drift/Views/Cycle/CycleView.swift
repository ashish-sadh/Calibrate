import SwiftUI
import Charts

struct CycleView: View {
    @State private var entries: [HealthKitService.CycleEntry] = []
    @State private var ovulationEntries: [HealthKitService.OvulationEntry] = []
    @State private var bbtEntries: [HealthKitService.BBTEntry] = []
    @State private var spottingEntries: [HealthKitService.SpottingEntry] = []
    @State private var hrvHistory: [(date: Date, ms: Double)] = []
    @State private var rhrHistory: [(date: Date, bpm: Double)] = []
    @State private var sleepHistory: [(date: Date, hours: Double)] = []
    @State private var isLoading = true
    @State private var showFertileWindow = Preferences.cycleFertileWindow

    private var periods: [CyclePeriod] {
        CycleCalculations.groupIntoPeriods(entries)
    }

    private var cycleLengths: [Int] {
        cycleLengthsWithDates.map(\.length)
    }

    private var averageCycleLength: Int? {
        CycleCalculations.averageCycleLength(periods: periods)
    }

    private var currentCycleDay: Int? {
        CycleCalculations.currentCycleDay(periods: periods)
    }

    private var nextPeriodEstimate: Date? {
        guard let lastStart = periods.last?.startDate,
              let avg = averageCycleLength else { return nil }
        return Calendar.current.date(byAdding: .day, value: avg, to: lastStart)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isLoading {
                    Color.clear.frame(height: 200)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    // Section 1: Hero
                    summaryCard
                    // Section 2: Phase Timeline
                    if let day = currentCycleDay, let avg = averageCycleLength {
                        timelineCard(cycleDay: day, cycleLength: avg)
                    }
                    // Section 3: Biometric Correlation (WHOOP-style)
                    if periods.count >= 2 && !biometricCyclePoints.isEmpty {
                        biometricCard
                    }
                    // Section 4: Cycle Length Trend (Flo-style)
                    if cycleLengthsWithDates.count >= 2 {
                        cycleLengthTrendCard
                    }
                    // Section 5: History
                    historyCard
                    // Section 6: Advanced Insights (opt-in)
                    advancedInsightsToggle
                    if showFertileWindow {
                        fertileWindowCard
                    }
                    // Privacy
                    privacyNote
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Cycle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadData() }
    }

    // MARK: - Section 1: Hero / Summary

    private var summaryCard: some View {
        VStack(spacing: 12) {
            if let day = currentCycleDay {
                Text("Day \(day)")
                    .font(.system(size: 48, weight: .bold).monospacedDigit())
                    .foregroundStyle(.pink)

                if let avg = averageCycleLength {
                    if let phase = CycleCalculations.currentPhase(cycleDay: day, cycleLength: avg) {
                        Text(phase)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 8) {
                if let lastPeriod = periods.last {
                    summaryRow(label: "Last period", value: formatPeriodRange(lastPeriod))
                }
                if let avg = averageCycleLength {
                    summaryRow(label: "Average cycle", value: "\(avg) days")
                }
                if let next = nextPeriodEstimate {
                    summaryRow(label: "Next period", value: "~\(DateFormatters.shortDisplay.string(from: next))")
                }
            }
            .padding(.top, 4)
        }
        .card()
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    // MARK: - Section 2: Phase Timeline

    private func timelineCard(cycleDay: Int, cycleLength: Int) -> some View {
        let phases = cyclePhases(cycleLength: cycleLength)
        let progress = min(Double(cycleDay) / Double(cycleLength), 1.0)
        let currentId = CycleCalculations.currentPhaseId(cycleDay: cycleDay, cycleLength: cycleLength)
        let fertileRange = fertileWindowDayRange(cycleLength: cycleLength)

        return VStack(alignment: .leading, spacing: 10) {
            Text("Cycle Timeline")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    // Phase segments — current phase brighter
                    HStack(spacing: 0) {
                        ForEach(phases) { phase in
                            Rectangle()
                                .fill(phase.color.opacity(phase.id == currentId ? 0.6 : 0.25))
                                .frame(width: width * phase.fraction)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .frame(height: 8)

                    // Fertile window indicator (only when opted in)
                    if showFertileWindow, let range = fertileRange {
                        let startFrac = Double(range.lowerBound) / Double(cycleLength)
                        let endFrac = Double(range.upperBound) / Double(cycleLength)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.purple.opacity(0.4))
                            .frame(width: width * (endFrac - startFrac), height: 8)
                            .offset(x: width * startFrac)
                    }

                    // Current position
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .offset(x: width * progress - 6)
                }
            }
            .frame(height: 12)

            // Phase labels with day ranges
            HStack(spacing: 0) {
                ForEach(phases) { phase in
                    VStack(spacing: 2) {
                        Text(phase.name)
                            .font(.system(size: 11, weight: phase.id == currentId ? .semibold : .regular))
                            .foregroundStyle(phase.color)
                        Text(phase.dayRange)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    // MARK: - Section 3: Biometric Correlation Chart

    /// Use the most recent COMPLETE cycle for biometric chart (not the in-progress one).
    private var biometricCyclePoints: [BiometricCyclePoint] {
        guard periods.count >= 2, let avg = averageCycleLength else { return [] }
        // Use second-to-last period as cycle start (most recent complete cycle)
        let cycleStart = periods[periods.count - 2].startDate
        let cycleEnd = periods.last!.startDate
        let cal = Calendar.current

        guard let totalDays = cal.dateComponents([.day], from: cycleStart, to: cycleEnd).day,
              totalDays > 0 else { return [] }

        var points: [BiometricCyclePoint] = []
        for day in 0..<totalDays {
            guard let date = cal.date(byAdding: .day, value: day, to: cycleStart) else { continue }
            let cycleDay = day + 1
            let dateStart = cal.startOfDay(for: date)
            let dateEnd = cal.date(byAdding: .day, value: 1, to: dateStart)!

            let hrvVal = hrvHistory.first { $0.date >= dateStart && $0.date < dateEnd }?.ms
            let rhrVal = rhrHistory.first { $0.date >= dateStart && $0.date < dateEnd }?.bpm

            if hrvVal != nil || rhrVal != nil {
                let phase = CycleCalculations.currentPhaseId(cycleDay: cycleDay, cycleLength: avg)
                points.append(BiometricCyclePoint(
                    cycleDay: cycleDay, phase: phase,
                    hrvMs: hrvVal, rhrBpm: rhrVal
                ))
            }
        }
        return points
    }

    private var biometricCard: some View {
        let points = biometricCyclePoints
        let hasHRV = points.contains { $0.hrvMs != nil }
        let hasRHR = points.contains { $0.rhrBpm != nil }
        let maxDay = points.map(\.cycleDay).max() ?? 28

        return VStack(alignment: .leading, spacing: 10) {
            Text("Body Signals")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Chart(points) { point in
                if let hrv = point.hrvMs {
                    LineMark(
                        x: .value("Day", point.cycleDay),
                        y: .value("Value", hrv),
                        series: .value("Metric", "HRV")
                    )
                    .foregroundStyle(Theme.deficit)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                if let rhr = point.rhrBpm {
                    LineMark(
                        x: .value("Day", point.cycleDay),
                        y: .value("Value", rhr),
                        series: .value("Metric", "RHR")
                    )
                    .foregroundStyle(Theme.heartRed)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
            }
            .chartXScale(domain: 1...maxDay)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 160)

            // Legend
            HStack(spacing: 16) {
                if hasHRV { legendDot(color: Theme.deficit, label: "HRV (ms)") }
                if hasRHR { legendDot(color: Theme.heartRed, label: "RHR (bpm)") }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
        .card()
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }

    // MARK: - Section 4: Cycle Length Trend

    private var cycleLengthsWithDates: [(label: String, length: Int)] {
        CycleCalculations.cycleLengthsWithDates(periods: periods)
    }

    private var cycleLengthTrendCard: some View {
        let data = cycleLengthsWithDates
        let lengths = data.map(\.length)
        let avg = lengths.reduce(0, +) / lengths.count
        let minLen = lengths.min() ?? 0
        let maxLen = lengths.max() ?? 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Cycle Length")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Avg \(avg) days")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Chart {
                RuleMark(y: .value("Typical", 28))
                    .foregroundStyle(Color.white.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .trailing, alignment: .leading) {
                        Text("28")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }

                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    BarMark(
                        x: .value("Period", item.label),
                        y: .value("Days", item.length),
                        width: .fixed(32)
                    )
                    .foregroundStyle(item.length < 21 || item.length > 35 ? Theme.surplus.opacity(0.8) : Color.pink.opacity(0.5))
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text("\(item.length)d")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartYScale(domain: 0...max(maxLen + 4, 32))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 120)

            if lengths.count >= 2 {
                Text("Range \(minLen)–\(maxLen) days")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .card()
    }

    // MARK: - Section 5: Fertile Window

    @ViewBuilder
    private var fertileWindowCard: some View {
        if let window = estimatedFertileWindow() {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    Text("Fertile Window")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if !window.isFromOvulationTest {
                        Text("(estimated)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack {
                    Text("\(DateFormatters.shortDisplay.string(from: window.start)) – \(DateFormatters.shortDisplay.string(from: window.end))")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(fertileWindowStatus(window))
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
            .card()
        }
    }

    // MARK: - Section 6: History

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Periods")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            let reversedPeriods = Array(periods.reversed().prefix(6))
            ForEach(Array(reversedPeriods.enumerated()), id: \.element.startDate) { index, period in
                HStack {
                    Circle()
                        .fill(flowColor(period.dominantFlow))
                        .frame(width: 8, height: 8)
                    Text(formatPeriodRange(period))
                        .font(.subheadline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(period.days.count) days · \(period.dominantFlowDisplay)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Cycle length (gap to next period)
                        if index < reversedPeriods.count - 1 {
                            let nextPeriod = reversedPeriods[index + 1]
                            let gap = Calendar.current.dateComponents([.day], from: nextPeriod.startDate, to: period.startDate).day ?? 0
                            if gap > 0 {
                                Text("\(gap)-day cycle")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }
        .card()
    }

    // MARK: - Advanced Insights Toggle

    private var advancedInsightsToggle: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .foregroundStyle(.purple.opacity(0.6))
                .frame(width: 24)
            Text("Advanced Insights")
                .font(.subheadline.weight(.medium))
            Spacer()
            Toggle("", isOn: $showFertileWindow)
                .labelsHidden()
                .tint(.purple)
                .onChange(of: showFertileWindow) { _, val in
                    Preferences.cycleFertileWindow = val
                }
        }
        .card()
    }

    // MARK: - Privacy Note

    private var privacyNote: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Theme.deficit)
                    .font(.caption)
                Text("Your cycle data stays on your device")
                    .font(.caption.weight(.medium))
            }
            Text("Drift reads from Apple Health and stores nothing externally. No accounts, no cloud, no tracking.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.circle")
                .font(.system(size: 40))
                .foregroundStyle(.pink.opacity(0.4))
            Text("No Cycle Data")
                .font(.headline)
            Text("Track your cycle in the Health app or a connected app to see it here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .card()
    }

    // MARK: - Data Loading

    private func loadData() async {
        let hk = HealthKitService.shared

        // Fetch all data independently — one failure doesn't block others
        entries = (try? await hk.fetchCycleHistory(days: 180)) ?? []
        ovulationEntries = (try? await hk.fetchOvulationHistory(days: 180)) ?? []
        bbtEntries = (try? await hk.fetchBBTHistory(days: 180)) ?? []
        spottingEntries = (try? await hk.fetchSpottingHistory(days: 180)) ?? []

        // Biometric data for correlation chart
        #if targetEnvironment(simulator)
        let mockPeriods = CycleCalculations.groupIntoPeriods(entries)
        let periodInfo = mockPeriods.enumerated().compactMap { i, p -> (start: Date, length: Int)? in
            if i < mockPeriods.count - 1 {
                let gap = Calendar.current.dateComponents([.day], from: p.startDate, to: mockPeriods[i + 1].startDate).day ?? 28
                return (start: p.startDate, length: gap)
            }
            return (start: p.startDate, length: averageCycleLength ?? 28)
        }
        let mock = HealthKitService.mockCycleBiometrics(periodStarts: periodInfo)
        hrvHistory = mock.hrv
        rhrHistory = mock.rhr
        sleepHistory = mock.sleep
        #else
        hrvHistory = (try? await hk.fetchHRVHistory(days: 90)) ?? []
        rhrHistory = (try? await hk.fetchRestingHeartRateHistory(days: 90)) ?? []
        sleepHistory = (try? await hk.fetchSleepHistory(days: 90)) ?? []
        #endif

        isLoading = false
    }

    // MARK: - Helpers

    private func flowColor(_ flow: Int) -> Color {
        switch flow {
        case 1: .pink.opacity(0.5)
        case 2: .pink.opacity(0.7)
        case 3: .pink
        default: .pink.opacity(0.3)
        }
    }

    private struct FertileWindow {
        let start: Date
        let end: Date
        let isFromOvulationTest: Bool
    }

    private func estimatedFertileWindow() -> FertileWindow? {
        guard let lastStart = periods.last?.startDate,
              let avg = averageCycleLength else { return nil }
        let cal = Calendar.current

        // Check for actual ovulation test data in current cycle
        let currentCycleOvulation = ovulationEntries.filter {
            $0.date >= lastStart && $0.isPositive
        }
        if let ovDate = currentCycleOvulation.last?.date {
            let start = cal.date(byAdding: .day, value: -5, to: ovDate) ?? ovDate
            return FertileWindow(start: start, end: ovDate, isFromOvulationTest: true)
        }

        // Estimate from cycle length
        let ovDay = max(avg - 14, avg / 2)
        guard let ovDate = cal.date(byAdding: .day, value: ovDay, to: lastStart),
              let start = cal.date(byAdding: .day, value: -5, to: ovDate) else { return nil }
        return FertileWindow(start: start, end: ovDate, isFromOvulationTest: false)
    }

    private func fertileWindowStatus(_ window: FertileWindow) -> String {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.startOfDay(for: window.start)
        let end = Calendar.current.startOfDay(for: window.end)

        if today < start {
            let days = Calendar.current.dateComponents([.day], from: today, to: start).day ?? 0
            return "In \(days) days"
        } else if today <= end {
            return "Now"
        }
        return "Passed"
    }

    private func fertileWindowDayRange(cycleLength: Int) -> ClosedRange<Int>? {
        let ovDay = max(cycleLength - 14, cycleLength / 2)
        return max(1, ovDay - 5)...ovDay
    }
}

// MARK: - View-only helpers

private func formatPeriodRange(_ period: CyclePeriod) -> String {
    let start = DateFormatters.shortDisplay.string(from: period.startDate)
    let end = DateFormatters.shortDisplay.string(from: period.endDate)
    return start == end ? start : "\(start) – \(end)"
}

private struct BiometricCyclePoint: Identifiable {
    let id = UUID()
    let cycleDay: Int
    let phase: String
    let hrvMs: Double?
    let rhrBpm: Double?
}

private struct CyclePhase: Identifiable, Equatable {
    let id: String
    let name: String
    let color: Color
    let fraction: Double
    let dayRange: String
    static func == (lhs: CyclePhase, rhs: CyclePhase) -> Bool { lhs.id == rhs.id }
}

private func cyclePhases(cycleLength: Int) -> [CyclePhase] {
    let cl = Double(cycleLength)
    let periodDays = 5
    let ovDays = 2
    let ovDay = CycleCalculations.ovulationDay(cycleLength: cycleLength)
    let follicularDays = max(0, ovDay - periodDays - 1)
    let lutealDays = max(0, cycleLength - periodDays - follicularDays - ovDays)

    var dayStart = 1
    func range(_ count: Int) -> String {
        let end = dayStart + count - 1
        let s = count <= 0 ? "" : "\(dayStart)–\(end)"
        dayStart = end + 1
        return s
    }

    return [
        CyclePhase(id: "period", name: "Period", color: .pink, fraction: Double(periodDays) / cl, dayRange: range(periodDays)),
        CyclePhase(id: "follicular", name: "Follicular", color: .orange, fraction: Double(follicularDays) / cl, dayRange: range(follicularDays)),
        CyclePhase(id: "ovulation", name: "Ovulation", color: .purple, fraction: Double(ovDays) / cl, dayRange: range(ovDays)),
        CyclePhase(id: "luteal", name: "Luteal", color: .blue, fraction: Double(lutealDays) / cl, dayRange: range(lutealDays)),
    ]
}

