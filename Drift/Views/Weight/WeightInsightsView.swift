import SwiftUI
import DriftCore
import Charts

struct WeightInsightsView: View {
    let trend: WeightTrendCalculator.WeightTrend
    let unit: WeightUnit
    let entries: [WeightEntry]
    var isLosing: Bool = true
    var onAddWeight: (() -> Void)? = nil
    var onAddBodyComp: (() -> Void)? = nil
    @State private var bodyCompEntries: [BodyComposition] = []
    @State private var showTrendInfo = false
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
                    metricCell(
                        id: "current",
                        label: "Current",
                        labelIcon: "plus.circle.fill",
                        value: String(format: "%.1f", unit.convert(fromKg: WeightTrendService.shared.latestWeightKg ?? trend.currentEMA)),
                        valueUnit: unit.displayName,
                        color: .primary,
                        tooltip: "Your latest logged weight. Tap to log a new entry."
                    )
                }
                .buttonStyle(.plain)

                if trend.hasInsufficientData {
                    metricCell(
                        id: "weekly",
                        label: "Weekly",
                        value: "—",
                        valueUnit: "\(unit.displayName)/wk",
                        color: .secondary,
                        tooltip: "Need at least 4 weigh-ins across 2 weeks to estimate a weekly rate.",
                        nudge: "Log a few more days"
                    )
                } else if trend.trendDirection == .maintaining {
                    // Genuinely flat trend slope (below the maintaining band,
                    // ~±0.05 kg/wk) — "≈0" is the honest number here, not a
                    // gate hiding a real one (2026-07-07: the significance
                    // gate no longer zeroes the rate; only tiny slopes land
                    // in this branch).
                    metricCell(
                        id: "weekly",
                        label: "Weekly",
                        value: "≈0.0",
                        valueUnit: "\(unit.displayName)/wk",
                        color: Theme.textSecondary,
                        tooltip: "Your trend line is flat over the past \(trend.rateWindowDays) days (raw slope \(String(format: "%+.2f", unit.convert(fromKg: trend.rawWeeklyRateKg))) \(unit.displayName)/wk) — the day-to-day ups and downs are mostly water.",
                        nudge: "Holding steady"
                    )
                } else {
                    let rate = trend.weeklyRateKg
                    metricCell(
                        id: "weekly",
                        label: "Weekly",
                        value: String(format: "%+.2f", unit.convert(fromKg: rate)),
                        valueUnit: "\(unit.displayName)/wk",
                        color: changeColor(rate),
                        direction: directionIcon(rate),
                        directionColor: changeColor(rate),
                        tooltip: "The slope of your smoothed trend line over the past \(trend.rateWindowDays) days\(trend.trendIsSignificant ? "." : " — an early read; day-to-day scatter is still large relative to this trend, so expect it to firm up with more weigh-ins.")",
                        nudge: trend.trendIsSignificant ? "Based on last \(trend.rateWindowDays) days" : "Early trend — firming up"
                    )
                }
            }

            HStack(spacing: 8) {
                if trend.hasInsufficientData {
                    metricCell(
                        id: "deficit",
                        label: "Est. Balance",
                        value: "—",
                        valueUnit: "kcal/day",
                        color: .secondary,
                        tooltip: "Need at least 4 weigh-ins across 2 weeks to estimate your daily energy balance.",
                        nudge: "Log a few more days"
                    )
                } else if trend.trendDirection == .maintaining {
                    // Flat trend. When the raw (pre-gate) estimate is
                    // non-trivial, show it as a SOFT number (operator
                    // 2026-07-13: "rough number, soft") — gray, ~ prefix,
                    // rounded to 10s, never goal-colored: the confidence gate
                    // decided this is noise-level, so it must not wear the
                    // certainty costume of the significant branch below.
                    let softBalance = (trend.rawEstimatedDailyDeficit / 10).rounded() * 10
                    let showSoft = abs(softBalance) >= 30
                    metricCell(
                        id: "deficit",
                        label: "Est. Balance",
                        value: showSoft ? String(format: "~%+.0f", softBalance) : "≈0",
                        valueUnit: "kcal/day",
                        color: Theme.textSecondary,
                        tooltip: showSoft
                            ? "Roughly \(String(format: "%+.0f", softBalance)) kcal/day — within noise of maintenance over the past \(trend.rateWindowDays) days. A soft read, not a target."
                            : "Your trend line is flat over the past \(trend.rateWindowDays) days — no meaningful surplus or deficit is showing.",
                        nudge: "Holding steady"
                    )
                } else {
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
                        tooltip: "Estimated daily caloric \(deficit < 0 ? "deficit" : "surplus") based on your smoothed weight trend over the past \(trend.rateWindowDays) days.\(trend.trendIsSignificant ? "" : " Early read — it will firm up as weigh-ins accumulate.")",
                        nudge: trend.trendIsSignificant ? "Based on last \(trend.rateWindowDays) days" : "Early trend — firming up"
                    )
                }

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

            // Trend weight — always shown when we have a trend. The previous
            // "only when |latest − EMA| > 0.5kg" gate hid the row whenever the
            // EMA was close to current weight, which became most of the time
            // after the time-weighted EMA fix made the smoother more responsive.
            // Users reported the bar "disappeared" — restore it as an always-on
            // smoothed number, useful even when close to current.
            HStack(spacing: 6) {
                Image(systemName: "chart.line.downtrend.xyaxis").font(.caption2).foregroundStyle(Theme.textTertiary)
                Text("Trend Weight: \(String(format: "%.1f", unit.convert(fromKg: trend.currentEMA))) \(unit.displayName)")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                Button { showTrendInfo = true } label: {
                    Image(systemName: "info.circle").font(.caption2).foregroundStyle(Theme.textTertiary)
                }.buttonStyle(.plain)
                .accessibilityLabel("Trend weight info")
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .hairlineCard(cornerRadius: Theme.radiusChip)

            // Compact weight-change chips
            weightChangesRow

            // Body composition cards (from body_composition table)
            bodyCompositionSection
                .onAppear { bodyCompEntries = WeightServiceAPI.fetchBodyComposition() }

            // Weekday pattern insight
            if trend.dataPoints.count >= 14 {
                weekdayInsight
            }
        }
        .alert("Trend Weight", isPresented: $showTrendInfo) {
            Button("OK") {}
        } message: {
            Text("Your trend weight uses exponential moving average (EMA) to smooth out daily fluctuations from water retention, meal timing, and scale variance. It shows your true underlying weight direction.")
        }
    }

    // MARK: - Body Composition

    private var bodyCompositionSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Body Composition")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
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
                        Image(systemName: "figure.arms.open").foregroundStyle(Theme.textSecondary)
                        Text("Track body fat, BMI, water % — tap to add")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    // V7 light fix: was `Color.white.opacity(0.05)`
                    // which is effectively invisible on the white
                    // card. Theme.pillBackground gives the soft-grey
                    // inset that matches the rest of the V7 surfaces.
                    .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
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
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            HStack(spacing: 2) {
                Text(String(format: "%.1f", value))
                    .font(.title3.weight(.bold).monospacedDigit())
                if !unit.isEmpty { Text(unit).font(.caption2).foregroundStyle(Theme.textTertiary) }
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
        .hairlineCard(cornerRadius: Theme.radiusControl)
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
                            Text("Latest").font(.caption2).foregroundStyle(Theme.textTertiary)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(String(format: "%.1f", parsed.last?.value ?? 0))
                                    .font(.title2.weight(.bold).monospacedDigit())
                                Text(title.contains("%") ? "%" : "")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                        if let first = parsed.first?.value, let last = parsed.last?.value {
                            let diff = last - first
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("Change").font(.caption2).foregroundStyle(Theme.textTertiary)
                                Text(String(format: "%+.1f", diff))
                                    .font(.title3.weight(.bold).monospacedDigit())
                                    .foregroundStyle(diff < 0 ? Theme.deficit : diff > 0 ? Theme.surplus : .secondary)
                            }
                        }
                    }

                    // Date range
                    if let f = parsed.first?.date, let l = parsed.last?.date {
                        Text("\(DateFormatters.shortDisplay.string(from: f)) – \(DateFormatters.shortDisplay.string(from: l))")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
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
                        // V7 light fix: body-composition chart used
                        // `.white.opacity` for its line + points —
                        // invisible on the white card background. Same
                        // bug class as the main weight chart fix in
                        // commit 805a7dd4. Flipped to Theme.accent.
                        ForEach(parsed.indices, id: \.self) { i in
                            LineMark(x: .value("Date", parsed[i].date), y: .value(title, parsed[i].value))
                                .foregroundStyle(Theme.accent)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Date", parsed[i].date), y: .value(title, parsed[i].value))
                                .foregroundStyle(Theme.accent)
                                .symbolSize(20)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) {
                            AxisValueLabel().foregroundStyle(Theme.textTertiary)
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
                .font(.caption2).foregroundStyle(Theme.textTertiary)
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
        VStack(spacing: 6) {
            // V7 mobile pass: without the card hairlines around each
            // metric cell, the previous lowercase/medium label was
            // visually mushy on the Body screen — the four cells in
            // the 2x2 grid blurred into each other. Bumping the label
            // to the shared small-caps tracked style (matches the
            // section headings in MoreTabView) so each cell anchors
            // visually on its own without needing a border.
            HStack(spacing: 4) {
                if let labelIcon {
                    Image(systemName: labelIcon)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(label.uppercased())
                    .sectionHeading()
                if let direction {
                    Image(systemName: direction)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(directionColor ?? color)
                }
            }

            // Value
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                // V7 mobile fix: a Text value of "—" / "--" (no-data
                // placeholder) coming through `color: .secondary` was
                // rendering as ghost-grey on white card. Detect the
                // placeholder and bump to Theme.textSecondary semibold
                // so "no data yet" is *readable* instead of looking
                // like a broken render.
                let isPlaceholder = value == "—" || value == "--"
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(isPlaceholder ? Theme.textSecondary : color)
                if !valueUnit.isEmpty {
                    Text(valueUnit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Nudge — was Theme.textTertiary (too faint to read). The
            // whole point of a nudge is "do this to get useful data" —
            // it has to be legible.
            if let nudge {
                Text(nudge)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .hairlineCard(cornerRadius: Theme.radiusControl)
    }

    // MARK: - Weight Changes Row

    private var weightChangesRow: some View {
        VStack(spacing: 2) {
            changeRow("3-day", days: 3, value: trend.weightChanges.threeDay)
            changeRow("7-day", days: 7, value: trend.weightChanges.sevenDay)
            changeRow("14-day", days: 14, value: trend.weightChanges.fourteenDay)
            changeRow("30-day", days: 30, value: trend.weightChanges.thirtyDay)
            changeRow("90-day", days: 90, value: trend.weightChanges.ninetyDay)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .hairlineCard(cornerRadius: Theme.radiusControl)
    }

    /// One trend-change row: period · sparkline of the trend over that window ·
    /// signed value · Increase/Decrease. Goal-aware colour (green = toward goal).
    private func changeRow(_ period: String, days: Int, value: Double?) -> some View {
        let color = value.map { changeColor($0) } ?? Color.secondary
        return HStack(spacing: 12) {
            Text(period)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 46, alignment: .leading)
            changeSparkline(days: days, color: color)
            Spacer(minLength: 6)
            if let value {
                Text(String(format: "%+.1f %@", unit.convert(fromKg: value), unit.displayName))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                HStack(spacing: 3) {
                    Image(systemName: directionIcon(value)).font(.caption2.weight(.bold))
                    Text(directionWord(value)).font(.caption)
                }
                .foregroundStyle(color)
                .frame(width: 80, alignment: .leading)
            } else {
                Text("—")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 30)
    }

    private func directionWord(_ value: Double) -> String {
        value < -0.01 ? "Decrease" : value > 0.01 ? "Increase" : "Steady"
    }

    /// Tiny trend (EMA) sparkline over the trailing `days` window.
    @ViewBuilder
    private func changeSparkline(days: Int, color: Color) -> some View {
        let pts = emaWindow(days: days)
        if pts.count >= 2 {
            Chart {
                ForEach(pts.indices, id: \.self) { i in
                    LineMark(x: .value("i", i), y: .value("w", pts[i]))
                        .foregroundStyle(color.opacity(0.85))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(width: 58, height: 22)
        } else {
            Color.clear.frame(width: 58, height: 22)
        }
    }

    /// Trend (EMA) weights over the trailing `days` window, in display units.
    private func emaWindow(days: Int) -> [Double] {
        guard let last = trend.dataPoints.last,
              let start = Calendar.current.date(byAdding: .day, value: -days, to: last.date) else { return [] }
        return trend.dataPoints.filter { $0.date >= start }.map { unit.convert(fromKg: $0.emaWeight) }
    }
}

private extension View {
    /// White card surface + V7 hairline. The Body screen's stat tiles use a
    /// raw background (not `.card()`, so no shadow lift) — on the #EFEFF1 page
    /// a borderless white tile is near-invisible (the "poor render" the metric
    /// cells showed). The hairline gives each tile a defined edge so the 2×2
    /// grid reads as distinct cards, matching the bordered weight section we
    /// agreed on. Re-adds (scoped to this screen) the stroke V7's global
    /// `CardStyle` dropped.
    func hairlineCard(cornerRadius: CGFloat) -> some View {
        background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 1)
            )
    }
}
