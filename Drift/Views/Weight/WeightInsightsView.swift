import SwiftUI
import Charts

struct WeightInsightsView: View {
    let trend: WeightTrendCalculator.WeightTrend
    let unit: WeightUnit
    let entries: [WeightEntry]
    var isLosing: Bool = true
    var onAddWeight: (() -> Void)? = nil
    var onAddBodyComp: (() -> Void)? = nil
    @State private var bodyCompEntries: [BodyComposition] = []
    @State private var showingBodyFatChart = false
    @State private var showingBMIChart = false
    @State private var showingWaterChart = false
    private func changeColor(_ value: Double) -> Color {
        let isDecrease = value < -0.01
        let isIncrease = value > 0.01
        if isLosing {
            return isDecrease ? Theme.deficit : isIncrease ? Theme.surplus : .secondary
        } else {
            return isIncrease ? Theme.deficit : isDecrease ? Theme.surplus : .secondary
        }
    }

    private func directionIcon(_ value: Double) -> String {
        value < -0.01 ? "arrow.down.right" : value > 0.01 ? "arrow.up.right" : "arrow.right"
    }

    var body: some View {
        VStack(spacing: 8) {
            // Key metrics — 2×2 compact grid
            HStack(spacing: 8) {
                Button { onAddWeight?() } label: {
                    VStack(spacing: 2) {
                        // Latest entry (raw — what user logged)
                        if let latest = WeightTrendService.shared.latestWeightKg {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", unit.convert(fromKg: latest)))
                                    .font(.title3.weight(.bold).monospacedDigit())
                                Text(unit.displayName).font(.caption2).foregroundStyle(.tertiary)
                            }
                            Text("Latest").font(.caption2).foregroundStyle(.secondary)
                        }
                        // Trend (EMA smoothed)
                        HStack(alignment: .firstTextBaseline, spacing: 2) {
                            Text(String(format: "%.1f", unit.convert(fromKg: trend.currentEMA)))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text("trend").font(.caption2).foregroundStyle(.quaternary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                let rate = trend.weeklyRateKg
                metricCell(
                    id: "weekly",
                    label: "Weekly",
                    value: String(format: "%+.2f", unit.convert(fromKg: rate)),
                    valueUnit: "\(unit.displayName)/wk",
                    color: changeColor(rate),
                    direction: directionIcon(rate),
                    directionColor: changeColor(rate),
                    tooltip: "Your typical weekly rate of change over the past \(WeightTrendCalculator.loadConfig().regressionWindowDays) days.",
                    nudge: "Based on last \(trend.config.regressionWindowDays) days"
                )
            }

            HStack(spacing: 8) {
                let deficit = trend.estimatedDailyDeficit
                let deficitColor = isLosing
                    ? (deficit < 0 ? Theme.deficit : Theme.surplus)
                    : (deficit > 0 ? Theme.deficit : Theme.surplus)
                metricCell(
                    id: "deficit",
                    label: deficit < 0 ? "Est. Deficit" : "Est. Surplus",
                    value: String(format: "%+.0f", deficit),
                    valueUnit: "kcal/day",
                    color: deficitColor,
                    direction: directionIcon(deficit),
                    directionColor: deficitColor,
                    tooltip: "Estimated daily caloric \(deficit < 0 ? "deficit" : "surplus") based on your weight trend over the past \(WeightTrendCalculator.loadConfig().regressionWindowDays) days.",
                    nudge: "Based on last \(trend.config.regressionWindowDays) days"
                )

                if let proj = trend.projection30Day {
                    metricCell(
                        id: "projected",
                        label: "Projected",
                        labelIcon: "chart.line.flattrend.xyaxis",
                        value: String(format: "%.1f", unit.convert(fromKg: proj)),
                        valueUnit: "\(unit.displayName) in 30d",
                        color: .primary,
                        tooltip: "Your projected weight in 30 days if your current rate continues."
                    )
                } else {
                    metricCell(
                        id: "projected",
                        label: "Projected",
                        labelIcon: "chart.line.flattrend.xyaxis",
                        value: "--",
                        valueUnit: "",
                        color: .secondary,
                        tooltip: "Not enough data yet. Keep logging for a few weeks."
                    )
                }
            }

            // Compact weight-change chips
            weightChangesRow

            // Body composition cards (from body_composition table)
            bodyCompositionSection
                .onAppear { bodyCompEntries = (try? AppDatabase.shared.fetchBodyComposition()) ?? [] }

            // Weekday pattern insight
            if trend.dataPoints.count >= 14 {
                weekdayInsight
            }
        }
    }

    // MARK: - Body Composition

    private var bodyCompositionSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Body Composition")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let onAdd = onAddBodyComp {
                    Button { onAdd() } label: {
                        Label("Add", systemImage: "plus.circle")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
            .padding(.horizontal, 4)

            if bodyCompEntries.isEmpty {
                // Empty state — invite user to add
                Button { onAddBodyComp?() } label: {
                    HStack {
                        Image(systemName: "figure.arms.open").foregroundStyle(.secondary)
                        Text("Track body fat, BMI, water % — tap to add")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 8) {
                    if let latest = bodyCompEntries.first(where: { $0.bodyFatPct != nil }) {
                        let prev = bodyCompEntries.dropFirst().first(where: { $0.bodyFatPct != nil })?.bodyFatPct
                        bodyCompCard(label: "Body Fat", value: latest.bodyFatPct!, unit: "%", previous: prev)
                            .onTapGesture { showingBodyFatChart = true }
                    }
                    if let latest = bodyCompEntries.first(where: { $0.bmi != nil }) {
                        let prev = bodyCompEntries.dropFirst().first(where: { $0.bmi != nil })?.bmi
                        bodyCompCard(label: "BMI", value: latest.bmi!, unit: "", previous: prev)
                            .onTapGesture { showingBMIChart = true }
                    }
                    if let latest = bodyCompEntries.first(where: { $0.waterPct != nil }) {
                        let prev = bodyCompEntries.dropFirst().first(where: { $0.waterPct != nil })?.waterPct
                        bodyCompCard(label: "Water", value: latest.waterPct!, unit: "%", previous: prev)
                            .onTapGesture { showingWaterChart = true }
                    }
                }
            }
        }
        .sheet(isPresented: $showingBodyFatChart) {
            bodyCompChartSheet(title: "Body Fat %", entries: bodyCompEntries.compactMap { e in
                e.bodyFatPct.map { (date: e.date, value: $0) }
            })
        }
        .sheet(isPresented: $showingBMIChart) {
            bodyCompChartSheet(title: "BMI", entries: bodyCompEntries.compactMap { e in
                e.bmi.map { (date: e.date, value: $0) }
            })
        }
        .sheet(isPresented: $showingWaterChart) {
            bodyCompChartSheet(title: "Water %", entries: bodyCompEntries.compactMap { e in
                e.waterPct.map { (date: e.date, value: $0) }
            })
        }
    }

    private func bodyCompCard(label: String, value: Double, unit: String, previous: Double?) -> some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.title3.weight(.bold).monospacedDigit())
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(.tertiary) }
            }
            if let prev = previous {
                let delta = value - prev
                HStack(spacing: 2) {
                    Image(systemName: delta < 0 ? "arrow.down.right" : delta > 0 ? "arrow.up.right" : "arrow.right")
                    Text(String(format: "%+.1f", delta))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(delta < 0 ? Theme.deficit : delta > 0 ? Theme.surplus : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private func bodyCompChartSheet(title: String, entries: [(date: String, value: Double)]) -> some View {
        let parsed = entries.compactMap { e -> (date: Date, value: Double)? in
            DateFormatters.dateOnly.date(from: e.date).map { ($0, e.value) }
        }.sorted { $0.date < $1.date }

        return NavigationStack {
            if parsed.count < 2 {
                ContentUnavailableView("Not enough data", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Log at least 2 entries to see a trend."))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Header — matches weight chart style
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Latest").font(.caption2).foregroundStyle(.tertiary)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(format: "%.1f", parsed.last?.value ?? 0))
                                    .font(.title2.weight(.bold).monospacedDigit())
                                Text(title.contains("%") ? "%" : "")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let first = parsed.first?.value, let last = parsed.last?.value {
                            let diff = last - first
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Change").font(.caption2).foregroundStyle(.tertiary)
                                Text(String(format: "%+.1f", diff))
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(diff < 0 ? Theme.deficit : diff > 0 ? Theme.surplus : .secondary)
                            }
                        }
                    }

                    // Date range
                    if let f = parsed.first?.date, let l = parsed.last?.date {
                        Text("\(DateFormatters.shortDisplay.string(from: f)) – \(DateFormatters.shortDisplay.string(from: l))")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }

                    // Chart — matches weight chart styling
                    Chart {
                        if let current = parsed.last?.value {
                            RuleMark(y: .value("", current))
                                .foregroundStyle(Theme.accent.opacity(0.4))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .annotation(position: .trailing, spacing: 4) {
                                    Text(String(format: "%.1f", current))
                                        .font(.caption.weight(.bold).monospacedDigit())
                                        .foregroundStyle(Theme.accent)
                                }
                        }
                        ForEach(parsed.indices, id: \.self) { i in
                            LineMark(x: .value("Date", parsed[i].date), y: .value(title, parsed[i].value))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Date", parsed[i].date), y: .value(title, parsed[i].value))
                                .foregroundStyle(.white.opacity(0.8))
                                .symbolSize(20)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) {
                            AxisValueLabel().foregroundStyle(.tertiary)
                        }
                    }
                    .frame(height: 220)
                }
                .padding()
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
        .navigationTitle(title)
        .presentationDetents([.medium, .large])
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    // MARK: - Weekday Pattern

    private var weekdayInsight: some View {
        let cal = Calendar.current
        var byDay: [Int: [Double]] = [:] // 1=Sun ... 7=Sat
        for p in trend.dataPoints {
            guard let w = p.actualWeight else { continue }
            let weekday = cal.component(.weekday, from: p.date)
            byDay[weekday, default: []].append(w)
        }
        let averages = byDay.compactMapValues { vals -> Double? in
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }
        guard averages.count >= 5 else { return AnyView(EmptyView()) } // need most days

        let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let lightest = averages.min(by: { $0.value < $1.value })
        let heaviest = averages.max(by: { $0.value < $1.value })

        guard let light = lightest, let heavy = heaviest, light.key != heavy.key else {
            return AnyView(EmptyView())
        }

        return AnyView(
            Text("You tend to weigh least on \(dayNames[light.key])s and most on \(dayNames[heavy.key])s")
                .font(.caption2).foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
        )
    }

    // MARK: - Metric Cell

    private func metricCell(
        id: String,
        label: String,
        labelIcon: String? = nil,
        value: String,
        valueUnit: String,
        color: Color,
        direction: String? = nil,
        directionColor: Color? = nil,
        tooltip: String,
        nudge: String? = nil
    ) -> some View {
        VStack(spacing: 4) {
            // Label + direction arrow
            HStack(spacing: 4) {
                if let labelIcon {
                    Image(systemName: labelIcon)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if let direction {
                    Image(systemName: direction)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(directionColor ?? color)
                }
            }

            // Value
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(color)
                if !valueUnit.isEmpty {
                    Text(valueUnit)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            // Nudge
            if let nudge {
                Text(nudge)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Weight Changes Row

    private var weightChangesRow: some View {
        HStack(spacing: 0) {
            changeChip("3d", value: trend.weightChanges.threeDay)
            changeChip("7d", value: trend.weightChanges.sevenDay)
            changeChip("14d", value: trend.weightChanges.fourteenDay)
            changeChip("30d", value: trend.weightChanges.thirtyDay)
            changeChip("90d", value: trend.weightChanges.ninetyDay)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private func changeChip(_ period: String, value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(period)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let value {
                let d = unit.convert(fromKg: value)
                HStack(spacing: 1) {
                    Image(systemName: directionIcon(value))
                        .font(.caption2.weight(.bold))
                    Text(String(format: "%+.1f", d))
                        .font(.caption.weight(.semibold).monospacedDigit())
                }
                .foregroundStyle(changeColor(value))
            } else {
                Text("--")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
