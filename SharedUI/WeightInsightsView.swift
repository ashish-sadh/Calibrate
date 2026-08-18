import SwiftUI
import DriftCore
#if !os(Android)
// Swift Charts is absent on SkipUI (skip_fuse_is_the_availability_tree) — the
// sparklines and the body-composition sheet draw `Path`s on Android instead.
import Charts
#endif

/// Which body-composition metric's trend sheet is open. iOS carried three
/// booleans and three `.sheet` modifiers; Fuse honours only ONE `.sheet` per
/// view (the trap `ProgressGalleryAndroid` ate), so the selection is a single
/// identifiable value driving a single `.sheet(item:)`. The `id` doubles as the
/// sheet title — same three sheets, same copy, one presentation.
struct BodyCompChartSelection: Identifiable {
    let id: String
}

struct WeightInsightsView: View {
    let trend: WeightTrendCalculator.WeightTrend
    let unit: WeightUnit
    var isLosing: Bool = true
    var onAddWeight: (() -> Void)? = nil
    var onAddBodyComp: (() -> Void)? = nil
    // Fuse cannot bridge `private` @State (skip_fuse_cannot_bridge_private_views_or_state).
    @State var bodyCompEntries: [BodyComposition] = []
    @State var showTrendInfo = false
    @State var bodyCompChart: BodyCompChartSelection?
    private func changeColor(_ value: Double) -> Color {
        let isDecrease = value < -0.01
        let isIncrease = value > 0.01
        if isLosing {
            return isDecrease ? Theme.deficit : isIncrease ? Theme.surplus : .secondary
        } else {
            return isIncrease ? Theme.deficit : isDecrease ? Theme.surplus : .secondary
        }
    }

    /// Soft-read display: "≈" (the app's established approx mark — the flat
    /// state shows "≈0") + typographic minus U+2212, because "~-0.34" mashes
    /// tilde into hyphen and reads as a typo (field report 2026-07-14).
    private func softNumber(_ signed: String) -> String {
        "≈" + signed.replacingOccurrences(of: "-", with: "−")
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
                } else if trend.energySignalConflicts {
                    // Short-window rate disagrees in sign with the 30-day
                    // change (water plunge vs monthly picture) — soft gray,
                    // ~ prefix, no goal colors until the signals agree.
                    metricCell(
                        id: "weekly",
                        label: "Weekly",
                        value: softNumber(String(format: "%+.2f", unit.convert(fromKg: trend.weeklyRateKg))),
                        valueUnit: "\(unit.displayName)/wk",
                        color: Theme.textSecondary,
                        tooltip: "The last \(trend.rateWindowDays) days point \(trend.weeklyRateKg < 0 ? "down" : "up"), but your longer trend points the other way — recent days are likely water. Treat this as a soft read until they agree.",
                        nudge: "Recent swing — firming up"
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
                        value: showSoft ? softNumber(String(format: "%+.0f", softBalance)) : "≈0",
                        valueUnit: "kcal/day",
                        color: Theme.textSecondary,
                        tooltip: showSoft
                            ? "Roughly \(String(format: "%+.0f", softBalance)) kcal/day — within noise of maintenance over the past \(trend.rateWindowDays) days. A soft read, not a target."
                            : "Your trend line is flat over the past \(trend.rateWindowDays) days — no meaningful surplus or deficit is showing.",
                        nudge: "Holding steady"
                    )
                } else if trend.energySignalConflicts {
                    // "−170 deficit" next to "30-day +1.0 Increase" is the
                    // contradiction class (field 2026-07-13) — soften until
                    // the windows agree.
                    let softBalance = (trend.estimatedDailyDeficit / 10).rounded() * 10
                    metricCell(
                        id: "deficit",
                        label: "Est. Balance",
                        value: softNumber(String(format: "%+.0f", softBalance)),
                        valueUnit: "kcal/day",
                        color: Theme.textSecondary,
                        tooltip: "The last \(trend.rateWindowDays) days suggest \(String(format: "%+.0f", softBalance)) kcal/day, but your longer trend disagrees — recent days are likely water. A soft read, not a target.",
                        nudge: "Recent dip — firming up"
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
                #if os(Android)
                BarChartShape().fill(Theme.textTertiary).frame(width: 11, height: 11)
                #else
                Image(systemName: "chart.line.downtrend.xyaxis").font(.caption2).foregroundStyle(Theme.textTertiary)
                #endif
                Text("Trend Weight: \(String(format: "%.1f", unit.convert(fromKg: trend.currentEMA))) \(unit.displayName)")
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                Button { showTrendInfo = true } label: {
                    Image(systemName: sym("info.circle")).font(.caption2).foregroundStyle(Theme.textTertiary)
                }.buttonStyle(.plain)
                .accessibilityLabel("Trend weight info")
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .hairlineCard(cornerRadius: Theme.radiusChip)

            // Compact weight-change chips
            weightChangesRow

            // Body composition cards (from body_composition table)
            #if os(Android)
            // The read crosses JNI — off the first compositions, and only once
            // the store is open (standing rule: no synchronous DB work in an
            // Android view, directive 0e).
            bodyCompositionSection
                .task {
                    await CoreResourcesBootstrap.warmUpDatabase()
                    bodyCompEntries = WeightServiceAPI.fetchBodyComposition()
                }
            #else
            bodyCompositionSection
                .onAppear { bodyCompEntries = WeightServiceAPI.fetchBodyComposition() }
            #endif

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
                        Label("Add", systemImage: sym("plus.circle"))
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
                        Image(systemName: sym("figure.arms.open")).foregroundStyle(Theme.textSecondary)
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
                            .onTapGesture { bodyCompChart = BodyCompChartSelection(id: "Body Fat %") }
                    }
                    if let latest = bodyCompEntries.first(where: { $0.bmi != nil }) {
                        let prev = bodyCompEntries.dropFirst().first(where: { $0.bmi != nil })?.bmi
                        bodyCompCard(label: "BMI", value: latest.bmi!, unit: "", previous: prev)
                            .onTapGesture { bodyCompChart = BodyCompChartSelection(id: "BMI") }
                    }
                    if let latest = bodyCompEntries.first(where: { $0.waterPct != nil }) {
                        let prev = bodyCompEntries.dropFirst().first(where: { $0.waterPct != nil })?.waterPct
                        bodyCompCard(label: "Water", value: latest.waterPct!, unit: "%", previous: prev)
                            .onTapGesture { bodyCompChart = BodyCompChartSelection(id: "Water %") }
                    }
                }
            }
        }
        .sheet(item: $bodyCompChart) { selection in
            bodyCompChartSheet(title: selection.id, entries: bodyCompSeries(for: selection.id))
        }
    }

    /// The (date, value) pairs behind one body-composition metric's sheet.
    private func bodyCompSeries(for title: String) -> [(date: String, value: Double)] {
        switch title {
        case "Body Fat %": return bodyCompEntries.compactMap { e in e.bodyFatPct.map { (date: e.date, value: $0) } }
        case "BMI": return bodyCompEntries.compactMap { e in e.bmi.map { (date: e.date, value: $0) } }
        default: return bodyCompEntries.compactMap { e in e.waterPct.map { (date: e.date, value: $0) } }
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
                    Image(systemName: sym(delta < 0 ? "arrow.down.right" : delta > 0 ? "arrow.up.right" : "arrow.right"))
                    Text(String(format: "%+.1f", delta))
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(delta < 0 ? Theme.deficit : delta > 0 ? Theme.surplus : .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .hairlineCard(cornerRadius: Theme.radiusControl)
        // Without an explicit hit shape the tap only lands on the drawn text on
        // Fuse (harness_dead_synthetic_tap_means_contentshape) — the whole tile
        // opens the trend sheet.
        .contentShape(Rectangle())
    }

    private func bodyCompChartSheet(title: String, entries: [(date: String, value: Double)]) -> some View {
        let parsed = entries.compactMap { e -> (date: Date, value: Double)? in
            DateFormatters.dateOnly.date(from: e.date).map { ($0, e.value) }
        }.sorted { $0.date < $1.date }

        #if os(Android)
        // No NavigationStack wrapper: iOS's `.navigationTitle` here sits on the
        // stack rather than its content and is inert on BOTH platforms (the
        // sheet draws no title bar), and on Fuse the wrapper also swallows
        // `.presentationDetents` — the sheet then took the full screen and left
        // two thirds of it barren under a 220pt chart. ScrollView root +
        // detents matches iOS's half-height sheet, and the scroll keeps the
        // detent from squashing the card (skipui_sheet_detent_compresses).
        // ContentUnavailableView is not in the Fuse availability tree either,
        // so the empty branch is a plain VStack.
        return ScrollView {
            Group {
                if parsed.count < 2 {
                    VStack(spacing: 8) {
                        BarChartShape().fill(Theme.textTertiary).frame(width: 34, height: 34)
                        Text("Not enough data").font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("Log at least 2 entries to see a trend.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        bodyCompSheetHeader(title: title, parsed: parsed)
                        BodyCompChartAndroid(points: parsed)
                            .frame(height: 220)
                    }
                    .padding()
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .background(Theme.background)
        #else
        return NavigationStack {
            if parsed.count < 2 {
                ContentUnavailableView("Not enough data", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Log at least 2 entries to see a trend."))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    bodyCompSheetHeader(title: title, parsed: parsed)

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
        #endif
    }

    /// Latest value + net change + date range — identical on both platforms;
    /// only the plot below it differs (Charts vs `Path`).
    private func bodyCompSheetHeader(title: String, parsed: [(date: Date, value: Double)]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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
        }
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

        // Full weekday names, localized. Pluralising the 3-letter abbreviation
        // produced "Thus" (reads as the word "thus"), "Weds", "Tues" — the
        // abbreviation is not a noun you can add "s" to.
        let dayNames = [""] + DateFormatters.weekdayNames
        let lightest = averages.min(by: { $0.value < $1.value })
        let heaviest = averages.max(by: { $0.value < $1.value })

        guard let light = lightest, let heavy = heaviest, light.key != heavy.key,
              light.key < dayNames.count, heavy.key < dayNames.count else {
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
                    #if os(Android)
                    // The chart-family names have no glyph under the pinned
                    // skip-ui 1.58 (sym() targets chart.bar.xaxis, a 1.59+
                    // name) — drawn bars instead, same precedent as
                    // WorkoutView / ClientDetailView (ChartGlyph.swift).
                    if labelIcon.hasPrefix("chart.") {
                        BarChartShape().fill(Theme.textSecondary).frame(width: 11, height: 11)
                    } else {
                        Image(systemName: sym(labelIcon))
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    #else
                    Image(systemName: labelIcon)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                    #endif
                }
                Text(label.uppercased())
                    .sectionHeading()
                if let direction {
                    Image(systemName: sym(direction))
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
                    Image(systemName: sym(directionIcon(value))).font(.caption2.weight(.bold))
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
            #if os(Android)
            // Charts is absent on SkipUI — a polyline `Path` instead, decimated
            // to at most 24 vertices: every Path command is one JNI hop
            // (skipui_fuse_perf_facts) and the 90-day row alone would push 90.
            SparklineShape(values: Self.decimate(pts, to: 24))
                .stroke(color.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 58, height: 22)
            #else
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
            #endif
        } else {
            Color.clear.frame(width: 58, height: 22)
        }
    }

    /// Evenly-sampled subset of `values` (endpoints always kept) so a long
    /// window still draws a bounded number of `Path` commands.
    static func decimate(_ values: [Double], to maxCount: Int) -> [Double] {
        guard values.count > maxCount, maxCount >= 2 else { return values }
        let step = Double(values.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { values[Int((Double($0) * step).rounded())] }
    }

    /// Trend (EMA) weights over the trailing `days` window, in display units.
    private func emaWindow(days: Int) -> [Double] {
        guard let last = trend.dataPoints.last,
              let start = Calendar.current.date(byAdding: .day, value: -days, to: last.date) else { return [] }
        return trend.dataPoints.filter { $0.date >= start }.map { unit.convert(fromKg: $0.emaWeight) }
    }
}

// Not `private`: Fuse cannot bridge private declarations
// (skip_fuse_cannot_bridge_private_views_or_state).
extension View {
    /// White card surface + V7 hairline. The Body screen's stat tiles use a
    /// raw background (not `.card()`, so no shadow lift) — on the #EFEFF1 page
    /// a borderless white tile is near-invisible (the "poor render" the metric
    /// cells showed). The hairline gives each tile a defined edge so the 2×2
    /// grid reads as distinct cards, matching the bordered weight section we
    /// agreed on. Re-adds (scoped to this screen) the stroke V7's global
    /// `CardStyle` dropped.
    func hairlineCard(cornerRadius: CGFloat) -> some View {
        background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(hairlineBorder(cornerRadius: cornerRadius))
    }

    /// iOS keeps `strokeBorder`; Fuse declares two `strokeBorder` overload
    /// families and the call goes ambiguous, so Android draws a plain stroke
    /// (half a point of inset on a 1pt hairline — imperceptible; house
    /// precedent MealCalendarPicker.todayRing / ExerciseVoiceLogSheet).
    @ViewBuilder
    func hairlineBorder(cornerRadius: CGFloat) -> some View {
        #if os(Android)
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(Theme.separator, lineWidth: 1)
        #else
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(Theme.separator, lineWidth: 1)
        #endif
    }
}

#if os(Android)

/// The change table's sparkline as a `Path`: Swift Charts has no SkipUI
/// equivalent, and a 58×22 polyline is the whole mark iOS draws.
struct SparklineShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard values.count >= 2 else { return p }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        // A perfectly flat window would divide by zero — draw it mid-height.
        let span = max(0.0001, hi - lo)
        let dx = rect.width / CGFloat(values.count - 1)
        for (i, v) in values.enumerated() {
            let y = hi == lo ? rect.midY
                : rect.maxY - CGFloat((v - lo) / span) * rect.height
            let pt = CGPoint(x: rect.minX + CGFloat(i) * dx, y: y)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}

/// Android's stand-in for the body-composition trend `Chart`: accent polyline +
/// point dots, a dashed rule at the latest value, and that value labelled at
/// the trailing edge — the same reading the iOS `RuleMark` annotation gives.
/// Deliberately NOT extracted into a shared chart type with `WeightChartPlot`:
/// this is occurrence two, and the tenet is three similar lines before
/// abstracting (#1147's biomarker chart is the third).
struct BodyCompChartAndroid: View {
    let points: [(date: Date, value: Double)]

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            GeometryReader { geo in
                plot(in: geo.size)
            }
            .drawingGroup()
            VStack {
                Text(String(format: "%.1f", domain.hi))
                Spacer()
                Text(String(format: "%.1f", domain.lo))
            }
            .font(.caption2).foregroundStyle(Theme.textTertiary)
            .frame(width: 34)
        }
    }

    private var domain: (lo: Double, hi: Double) {
        let values = points.map(\.value)
        let lo = values.min() ?? 0
        let hi = values.max() ?? 0
        let pad = max(0.2, (hi - lo) * 0.12)
        return (lo - pad, hi + pad)
    }

    @ViewBuilder
    private func plot(in size: CGSize) -> some View {
        if size.width > 0, size.height > 0, points.count >= 2 {
            let d = domain
            let range = max(0.001, d.hi - d.lo)
            let first = points[0].date
            let span = max(1, points[points.count - 1].date.timeIntervalSince(first))
            let xs = points.map { CGFloat($0.date.timeIntervalSince(first) / span) * size.width }
            let ys = points.map { size.height - CGFloat(($0.value - d.lo) / range) * size.height }
            ZStack(alignment: .topLeading) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: ys[ys.count - 1]))
                    p.addLine(to: CGPoint(x: size.width, y: ys[ys.count - 1]))
                }
                .stroke(Theme.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4]))

                Path { p in
                    for i in xs.indices {
                        let pt = CGPoint(x: xs[i], y: ys[i])
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                Path { p in
                    for i in xs.indices {
                        p.addEllipse(in: CGRect(x: xs[i] - 2.5, y: ys[i] - 2.5, width: 5, height: 5))
                    }
                }
                .fill(Theme.accent)

                Text(String(format: "%.1f", points[points.count - 1].value))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
                    .fixedSize()
                    .position(x: max(size.width - 22, 22),
                              y: max(ys[ys.count - 1] - 20, 10))
            }
        }
    }
}

#endif
