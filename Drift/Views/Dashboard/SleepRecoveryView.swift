import SwiftUI
import DriftCore
import Charts

struct SleepRecoveryView: View {
    @State private var recovery: RecoveryEstimator.DailyRecovery?
    @State private var sleepHistory: [(date: Date, hours: Double)] = []
    @State private var hrvHistory: [(date: Date, ms: Double)] = []
    @State private var rhrHistory: [(date: Date, bpm: Double)] = []
    @State private var respHistory: [(date: Date, rpm: Double)] = []
    @State private var recoveryScoreHistory: [(date: Date, score: Int)] = []
    @State private var isLoading = true
    @State private var expandedVital: String?
    /// History window for the trend charts (7 / 14 / 30 days). Data is
    /// fetched once at 30 and sliced.
    @State private var historyDays = 7

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let r = recovery {
                    // Always show recovery if we have ANY data (HRV, RHR, or sleep)
                    if r.recoveryScore > 0 || r.hrvMs > 0 || r.restingHR > 0 {
                        recoveryHero(r)
                    }
                    if r.hrvMs > 0 || r.restingHR > 0 || r.respiratoryRate > 0 {
                        vitalsCard(r)
                    }
                    if r.sleepHours > 0 {
                        sleepScoreSection(r)
                    }
                    if recoveryScoreHistory.count > 3 || sleepHistory.count > 3 {
                        historySection(r)
                    }
                    activityLoadCard(r)
                    insightsCard(r)

                    // Hint if missing data
                    if r.sleepHours == 0 && r.hrvMs == 0 {
                        emptyState
                    } else if r.hrvMs == 0 {
                        Text("A fitness-tracking watch that syncs with Apple Health provides HRV and resting heart rate data.")
                            .font(.caption).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center)
                    } else if r.sleepHours == 0 {
                        Text("No sleep data detected. Use a sleep tracker that writes to Apple Health.")
                            .font(.caption).foregroundStyle(Theme.textTertiary).multilineTextAlignment(.center)
                    }
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView().tint(.secondary)
                        Text("Loading health data...").font(.caption).foregroundStyle(Theme.textTertiary)
                    }.frame(height: 200)
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Body Rhythm").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.light, for: .navigationBar)
        .onAppear { AIScreenTracker.shared.currentScreen = .bodyRhythm }
        .task { await loadData() }
    }

    // MARK: - Recovery Hero (big number + bar, no ring)

    private func recoveryHero(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        VStack(spacing: 8) {
            Text("Recovery").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            Text("\(r.recoveryScore)")
                .font(.system(size: Theme.FontSize.hero, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.scoreColor(r.recoveryScore))

            // Thin gradient progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.cardBackgroundElevated)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.scoreColor(r.recoveryScore))
                        .frame(width: geo.size.width * Double(r.recoveryScore) / 100, height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 40)

            if let baselines = r.baselines, baselines.isEstablished {
                let avgRecovery = RecoveryEstimator.calculateRecovery(
                    hrvMs: baselines.hrvMs, restingHR: baselines.restingHR,
                    sleepHours: baselines.sleepHours, baselines: baselines)
                Text("Your avg: \(avgRecovery)")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .card()
    }

    // MARK: - Vitals

    private func vitalsCard(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            vitalRow("HRV", value: r.hrvMs, unit: "ms", baseline: r.baselines?.hrvMs,
                     higherIsBetter: true, icon: "waveform.path", color: Theme.deficit,
                     history: hrvHistory.map { ($0.date, $0.ms) }, id: "hrv")

            Divider().overlay(Theme.separator)

            vitalRow("Resting HR", value: r.restingHR, unit: "bpm", baseline: r.baselines?.restingHR,
                     higherIsBetter: false, icon: "heart.fill", color: Theme.heartRed,
                     history: rhrHistory.map { ($0.date, $0.bpm) }, id: "rhr")

            Divider().overlay(Theme.separator)

            vitalRow("Respiratory", value: r.respiratoryRate, unit: "rpm", baseline: r.baselines?.respiratoryRate,
                     higherIsBetter: false, icon: "lungs.fill", color: Theme.calorieBlue,
                     history: respHistory.map { ($0.date, $0.rpm) }, id: "resp")
        }
        .card()
    }

    private func vitalRow(_ name: String, value: Double, unit: String, baseline: Double?,
                          higherIsBetter: Bool, icon: String, color: Color,
                          history: [(Date, Double)], id: String) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedVital = expandedVital == id ? nil : id
                }
            } label: {
                HStack {
                    Image(systemName: icon).font(.caption).foregroundStyle(color).frame(width: 20)
                    Text(name).font(.subheadline)
                    Spacer()
                    if value > 0 {
                        Text(name == "Respiratory" ? String(format: "%.1f", value) : "\(Int(value))")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                        Text(unit).font(.caption2).foregroundStyle(Theme.textTertiary)
                        if let bl = baseline, bl > 0 {
                            let dev = RecoveryEstimator.deviation(current: value, baseline: bl, higherIsBetter: higherIsBetter)
                            Text("\(dev.arrow)\(dev.pct)%")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(dev.favorable ? Theme.deficit : Theme.surplus)
                        }
                    } else {
                        Text("--").font(.subheadline.weight(.bold)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            // Expandable 7-day sparkline
            if expandedVital == id && history.count >= 3 {
                Chart {
                    ForEach(history.indices, id: \.self) { i in
                        LineMark(x: .value("", history[i].0), y: .value("", history[i].1))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.catmullRom)
                        PointMark(x: .value("", history[i].0), y: .value("", history[i].1))
                            .foregroundStyle(color)
                            .symbolSize(20)
                    }
                    if let bl = baseline {
                        RuleMark(y: .value("", bl))
                            .foregroundStyle(.secondary.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { AxisValueLabel(format: .dateTime.weekday(.abbreviated)).foregroundStyle(Theme.textSecondary) } }
                .chartYAxis { AxisMarks(position: .trailing) { AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
                .frame(height: 80)
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Sleep Score

    private func sleepScoreSection(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sleep").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(r.sleepScore)")
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.scoreColor(r.sleepScore))
            }

            // Score bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.cardBackgroundElevated).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(Theme.scoreColor(r.sleepScore))
                        .frame(width: geo.size.width * Double(r.sleepScore) / 100, height: 6)
                }
            }
            .frame(height: 6)

            // Hours summary
            HStack(spacing: 16) {
                VStack(spacing: 1) {
                    Text(String(format: "%.1fh", r.sleepHours)).font(.subheadline.weight(.bold).monospacedDigit())
                    Text("slept").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                VStack(spacing: 1) {
                    Text(String(format: "%.1fh", r.sleepNeeded)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    Text("needed").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                let diff = r.sleepHours - r.sleepNeeded
                VStack(spacing: 1) {
                    Text("\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff))h")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(diff >= 0 ? Theme.deficit : Theme.surplus)
                    Text("balance").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                if let start = r.sleepDetail?.bedStart, let end = r.sleepDetail?.bedEnd {
                    Spacer()
                    VStack(spacing: 1) {
                        Text("\(formatTime(start)) – \(formatTime(end))")
                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                        Text("bed time").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            // Explain sleep need breakdown
            let needExplain = sleepNeedExplanation(r)
            if !needExplain.isEmpty {
                Text(needExplain).font(.caption2).foregroundStyle(Theme.textTertiary)
            }

            // Sleep stages
            if let detail = r.sleepDetail, detail.totalHours > 0 {
                stageBar(detail)

                HStack(spacing: 8) {
                    stagePill("REM", hours: detail.remHours, total: detail.totalHours, color: Theme.accent)
                    stagePill("Deep", hours: detail.deepHours, total: detail.totalHours, color: Theme.sleepIndigo)
                    stagePill("Light", hours: detail.lightHours, total: detail.totalHours, color: Theme.calorieBlue.opacity(0.5))
                    stagePill("Awake", hours: detail.awakeHours, total: detail.totalHours + detail.awakeHours, color: Theme.surplus.opacity(0.5))
                }
            }
        }
        .card()
    }

    private func stageBar(_ d: SleepDetail) -> some View {
        let total = d.totalHours + d.awakeHours
        guard total > 0 else { return AnyView(EmptyView()) }
        return AnyView(
            GeometryReader { geo in
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: geo.size.width * d.remHours / total)
                    RoundedRectangle(cornerRadius: 2).fill(Theme.sleepIndigo).frame(width: geo.size.width * d.deepHours / total)
                    RoundedRectangle(cornerRadius: 2).fill(Theme.calorieBlue.opacity(0.5)).frame(width: geo.size.width * d.lightHours / total)
                    RoundedRectangle(cornerRadius: 2).fill(Theme.surplus.opacity(0.3)).frame(width: geo.size.width * d.awakeHours / total)
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        )
    }

    private func stagePill(_ name: String, hours: Double, total: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%.1fh", hours)).font(.caption2.weight(.bold).monospacedDigit())
            Text(name).font(.caption2).foregroundStyle(Theme.textSecondary)
            if total > 0 { Text("\(Int(hours / total * 100))%").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - History (recovery score + sleep, 7/14/30 days)

    /// The screen was a one-day snapshot (2026-07-14 operator ask) — this
    /// section is the story over time: per-day recovery scores and the sleep
    /// trend, over a selectable window.
    private func historySection(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Picker("Range", selection: $historyDays) {
                    Text("7d").tag(7)
                    Text("14d").tag(14)
                    Text("30d").tag(30)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            if recoveryScoreHistory.count > 3 {
                recoveryHistoryChart
            }
            if sleepHistory.count > 3 {
                sleepTrendChart(r)
            }
        }
    }

    private var recoveryHistoryChart: some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -historyDays, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let recent = recoveryScoreHistory.filter { $0.date > cutoff }
        let avg = recent.isEmpty ? 0 : recent.map(\.score).reduce(0, +) / recent.count
        func zoneColor(_ s: Int) -> Color {
            s >= 80 ? Theme.deficit : (s >= 40 ? Theme.fatYellow : Theme.surplus)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recovery").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("avg \(avg)").font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
            }
            Chart {
                ForEach(recent.indices, id: \.self) { i in
                    BarMark(
                        x: .value("Day", recent[i].date, unit: .day),
                        y: .value("Score", recent[i].score)
                    )
                    .foregroundStyle(zoneColor(recent[i].score).opacity(Calendar.current.isDateInToday(recent[i].date) ? 1.0 : 0.65))
                    .cornerRadius(2)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: historyDays == 7 ? 7 : 5)) {
                    AxisValueLabel(format: historyDays == 7 ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day())
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 110)
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
    }

    // MARK: - Sleep Trend

    private func sleepTrendChart(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        let recent = Array(sleepHistory.suffix(historyDays))
        let avg = recent.map(\.hours).reduce(0, +) / Double(max(1, recent.count))
        let need = r.sleepNeeded
        let todayStr = DateFormatters.dateOnly.string(from: Date())

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep Trend").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 3) { Circle().fill(Theme.deficit).frame(width: 6, height: 6); Text("Good").font(.caption2) }
                    HStack(spacing: 3) { Circle().fill(Theme.fatYellow).frame(width: 6, height: 6); Text("Fair").font(.caption2) }
                    HStack(spacing: 3) { Circle().fill(Theme.surplus).frame(width: 6, height: 6); Text("Low").font(.caption2) }
                }
                .foregroundStyle(Theme.textTertiary)
            }

            Chart {
                // Need reference line
                RuleMark(y: .value("", need))
                    .foregroundStyle(.secondary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .topTrailing, spacing: 2) {
                        Text("need").font(.caption2).foregroundStyle(Theme.textTertiary)
                    }

                ForEach(recent.indices, id: \.self) { i in
                    let hours = recent[i].hours
                    let isToday = Calendar.current.isDateInToday(recent[i].date)
                    let barColor: Color = hours >= need ? Theme.deficit
                        : hours >= need - 1 ? Theme.fatYellow
                        : Theme.surplus

                    BarMark(x: .value("", recent[i].date), y: .value("", hours))
                        .foregroundStyle(barColor.opacity(isToday ? 1.0 : 0.7))
                        .cornerRadius(3)
                        .annotation(position: .top, spacing: 2) {
                            Text(String(format: "%.1f", hours))
                                .font(.system(size: isToday ? 9 : 8, weight: isToday ? .bold : .regular).monospacedDigit())
                                .foregroundStyle(isToday ? .primary : .tertiary)
                        }
                }
            }
            .chartYScale(domain: 0...10)
            .chartYAxis { AxisMarks(values: [0, 5, 10]) { AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2)); AxisValueLabel().foregroundStyle(Theme.textSecondary) } }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 7)) {
                    AxisValueLabel(format: .dateTime.weekday(.narrow)).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(height: 140)

            Text("avg \(String(format: "%.1f", avg))h · need \(String(format: "%.1f", need))h")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    // MARK: - Activity Load

    private func activityLoadCard(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        let loadColor: Color = switch r.activityLoad {
        case .rest: .secondary
        case .light: Theme.calorieBlue
        case .moderate: Theme.deficit
        case .heavy: Theme.fatYellow
        case .extreme: Theme.surplus
        }

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity Load").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(r.activityLoad.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(loadColor)
            }

            // Visual bar (0-21 mapped to width)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.cardBackgroundElevated).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(loadColor)
                        .frame(width: geo.size.width * min(1, r.activityRaw / 21), height: 6)
                }
            }
            .frame(height: 6)

            HStack(spacing: 12) {
                HStack(spacing: 3) {
                    Image(systemName: "flame.fill").font(.caption).foregroundStyle(Theme.stepsOrange)
                    Text("\(Int(r.activeCalories)) cal").font(.caption2.monospacedDigit())
                }
                HStack(spacing: 3) {
                    Image(systemName: "figure.walk").font(.caption).foregroundStyle(Theme.deficit)
                    Text("\(Int(r.steps)) steps").font(.caption2.monospacedDigit())
                }
            }
            .foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    // MARK: - Insights

    private func insightsCard(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        let insights = RecoveryEstimator.generateInsights(
            recovery: r, hrvHistory: hrvHistory, sleepHistory: sleepHistory)

        return Group {
            if !insights.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lightbulb.fill").font(.caption2).foregroundStyle(Theme.fatYellow)
                            Text(insight).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.system(size: Theme.FontSize.display4)).foregroundStyle(Theme.sleepIndigo.opacity(0.5))
            Text("No Sleep Data").font(.headline)
            Text("Wear a fitness-tracking watch to bed or use a sleep tracker that syncs with Apple Health.")
                .font(.caption).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    // MARK: - Data Loading

    private func loadData() async {
        guard let hk = DriftPlatform.health else { return }
        let today = Date()

        try? await hk.requestAuthorization()

        // Fetch each source independently — one failure doesn't block others.
        // 30 days so the History section has a real window; baselines keep
        // their original 14-day span so today's score doesn't shift.
        hrvHistory = (try? await hk.fetchHRVHistory(days: 30)) ?? []
        rhrHistory = (try? await hk.fetchRestingHeartRateHistory(days: 30)) ?? []
        respHistory = (try? await hk.fetchRespiratoryRateHistory(days: 30)) ?? []
        let sleepHist = (try? await hk.fetchSleepHistory(days: 30)) ?? []
        sleepHistory = sleepHist

        let cutoff14 = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let baselines = RecoveryEstimator.calculateBaselines(
            hrvHistory: hrvHistory.filter { $0.date > cutoff14 },
            rhrHistory: rhrHistory.filter { $0.date > cutoff14 },
            respHistory: respHistory.filter { $0.date > cutoff14 },
            sleepHistory: sleepHist.filter { $0.date > cutoff14 })

        recoveryScoreHistory = RecoveryEstimator.recoveryHistory(
            hrvHistory: hrvHistory, rhrHistory: rhrHistory,
            sleepHistory: sleepHist, baselines: baselines)

        // Today's vitals (each independent)
        let sleepDetail = (try? await hk.fetchSleepDetail(for: today))
            ?? SleepDetail(totalHours: 0, remHours: 0, deepHours: 0, lightHours: 0, awakeHours: 0, bedStart: nil, bedEnd: nil)
        let hrv = (try? await hk.fetchHRV(for: today)) ?? 0
        let rhr = (try? await hk.fetchRestingHeartRate(for: today)) ?? 0
        let resp = (try? await hk.fetchRespiratoryRate(for: today)) ?? 0
        let calories = (try? await hk.fetchCaloriesBurned(for: today)) ?? CaloriesBurned(active: 0, basal: 0)
        let steps = (try? await hk.fetchSteps(for: today)) ?? 0

        // Use sleep hours from either fetchSleepDetail OR fetchSleepHours (whichever has data)
        var sleepHours = sleepDetail.totalHours
        if sleepHours == 0 {
            sleepHours = (try? await hk.fetchSleepHours(for: today)) ?? 0
        }

        // Activity load
        let (load, _) = RecoveryEstimator.calculateActivityLoad(activeCalories: calories.active, steps: steps)

        // Dynamic sleep need
        let previousDayLoad: Double
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) {
            let yCal = (try? await hk.fetchCaloriesBurned(for: yesterday))?.active ?? 0
            let ySteps = (try? await hk.fetchSteps(for: yesterday)) ?? 0
            previousDayLoad = RecoveryEstimator.calculateActivityLoad(activeCalories: yCal, steps: ySteps).raw
        } else {
            previousDayLoad = 0
        }
        let sleepDebt = RecoveryEstimator.sleepDebt(recentSleep: sleepHist, need: baselines.sleepHours)
        let sleepNeed = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: previousDayLoad, rollingDebtHours: sleepDebt)

        // Scores (work with whatever data is available)
        let recoveryScore = RecoveryEstimator.calculateRecovery(
            hrvMs: hrv, restingHR: rhr, sleepHours: sleepHours, baselines: baselines)
        let sleepScore = sleepHours > 0
            ? RecoveryEstimator.calculateSleepScore(
                totalHours: sleepHours, remHours: sleepDetail.remHours,
                deepHours: sleepDetail.deepHours, targetHours: sleepNeed)
            : 0

        recovery = RecoveryEstimator.DailyRecovery(
            date: today, recoveryScore: recoveryScore, sleepScore: sleepScore,
            activityLoad: load, activityRaw: RecoveryEstimator.calculateActivityLoad(activeCalories: calories.active, steps: steps).raw,
            activeCalories: calories.active, steps: steps,
            sleepHours: sleepHours, sleepNeeded: sleepNeed, sleepDebt: sleepDebt,
            hrvMs: hrv, restingHR: rhr, respiratoryRate: resp,
            sleepDetail: sleepDetail.totalHours > 0 ? sleepDetail : nil,
            baselines: baselines)

        // Extend sleep history for trend chart
        if sleepHistory.count < 30 {
            sleepHistory = (try? await hk.fetchSleepHistory(days: 30)) ?? sleepHistory
        }

        isLoading = false
    }

    private func sleepNeedExplanation(_ r: RecoveryEstimator.DailyRecovery) -> String {
        var parts = ["7.5h base"]
        let extra = r.sleepNeeded - 7.5
        if extra > 0.05 {
            if r.sleepDebt < -1 {
                parts.append("\(String(format: "+%.1f", min(0.5, abs(r.sleepDebt) * 0.15)))h sleep debt")
            }
            if r.activityRaw > 10 {
                parts.append("\(String(format: "+%.1f", min(0.5, (r.activityRaw - 10) * 0.05)))h activity")
            }
        }
        if r.sleepDebt < -0.5 {
            parts.append("debt: \(String(format: "%.1f", r.sleepDebt))h")
        }
        return parts.joined(separator: " · ")
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
    }
}
