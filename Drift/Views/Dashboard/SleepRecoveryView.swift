import SwiftUI
import Charts

struct SleepRecoveryView: View {
    @State private var recovery: RecoveryEstimator.DailyRecovery?
    @State private var sleepHistory: [(date: Date, hours: Double)] = []
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if isLoading {
                    ProgressView("Loading health data...")
                        .padding(.top, 40)
                } else if let r = recovery {
                    // Score rings (WHOOP-style)
                    scoreRings(r)

                    // Sleep detail
                    sleepDetailCard(r)

                    // Recovery detail
                    recoveryDetailCard(r)

                    // Sleep trend chart
                    if sleepHistory.count > 3 {
                        sleepTrendChart
                    }

                    // Vitals
                    vitalsCard(r)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "bed.double.fill")
                            .font(.system(size: 48)).foregroundStyle(Theme.sleepIndigo.opacity(0.5))
                        Text("No Sleep Data").font(.headline)
                        Text("Wear Apple Watch to bed or use a sleep tracker that writes to Apple Health.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Sleep & Recovery").navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await loadData() }
    }

    // MARK: - Score Rings

    private func scoreRings(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        HStack(spacing: 16) {
            scoreRing(
                value: r.sleepScore,
                label: "SLEEP",
                color: r.sleepScore >= 70 ? Theme.sleepIndigo : r.sleepScore >= 40 ? Theme.fatYellow : Theme.surplus
            )
            scoreRing(
                value: r.recoveryScore,
                label: "RECOVERY",
                color: r.recoveryLevel == .green ? Theme.deficit : r.recoveryLevel == .yellow ? Theme.fatYellow : Theme.surplus
            )
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .stroke(Theme.cardBackgroundElevated, lineWidth: 6)
                        .frame(width: 70, height: 70)
                    Circle()
                        .trim(from: 0, to: min(1, r.strainScore / 21))
                        .stroke(Theme.calorieBlue, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .frame(width: 70, height: 70)
                        .rotationEffect(.degrees(-90))
                    Text(String(format: "%.1f", r.strainScore))
                        .font(.title3.weight(.bold).monospacedDigit())
                }
                Text("STRAIN").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private func scoreRing(value: Int, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Theme.cardBackgroundElevated, lineWidth: 6)
                    .frame(width: 70, height: 70)
                Circle()
                    .trim(from: 0, to: Double(value) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 70, height: 70)
                    .rotationEffect(.degrees(-90))
                Text("\(value)%")
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Sleep Detail

    private func sleepDetailCard(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Sleep").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if let start = r.sleepDetail?.bedStart, let end = r.sleepDetail?.bedEnd {
                    Text("\(formatTime(start)) - \(formatTime(end))")
                        .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                }
            }

            // Hours vs needed
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", r.sleepHours))
                        .font(.title.weight(.bold).monospacedDigit())
                    Text("hours").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).card()

                VStack(spacing: 2) {
                    Text(String(format: "%.1f", r.sleepNeeded))
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("needed").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()

                let diff = r.sleepHours - r.sleepNeeded
                VStack(spacing: 2) {
                    Text("\(diff >= 0 ? "+" : "")\(String(format: "%.1f", diff))")
                        .font(.title.weight(.bold).monospacedDigit())
                        .foregroundStyle(diff >= 0 ? Theme.deficit : Theme.surplus)
                    Text("balance").font(.caption2).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity).card()
            }

            // Sleep stages
            if let detail = r.sleepDetail, detail.totalHours > 0 {
                VStack(spacing: 6) {
                    stageBar(detail)

                    HStack(spacing: 8) {
                        stagePill("REM", hours: detail.remHours, total: detail.totalHours, color: Theme.accent)
                        stagePill("Deep", hours: detail.deepHours, total: detail.totalHours, color: Theme.sleepIndigo)
                        stagePill("Light", hours: detail.lightHours, total: detail.totalHours, color: Theme.calorieBlue.opacity(0.5))
                        stagePill("Awake", hours: detail.awakeHours, total: detail.totalHours + detail.awakeHours, color: Theme.surplus.opacity(0.5))
                    }
                }
            }
        }
        .card()
    }

    private func stageBar(_ d: HealthKitService.SleepDetail) -> some View {
        let total = d.totalHours + d.awakeHours
        guard total > 0 else { return AnyView(EmptyView()) }

        return AnyView(
            GeometryReader { geo in
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.accent)
                        .frame(width: geo.size.width * d.remHours / total)
                    RoundedRectangle(cornerRadius: 2).fill(Theme.sleepIndigo)
                        .frame(width: geo.size.width * d.deepHours / total)
                    RoundedRectangle(cornerRadius: 2).fill(Theme.calorieBlue.opacity(0.5))
                        .frame(width: geo.size.width * d.lightHours / total)
                    RoundedRectangle(cornerRadius: 2).fill(Theme.surplus.opacity(0.3))
                        .frame(width: geo.size.width * d.awakeHours / total)
                }
            }
            .frame(height: 8)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        )
    }

    private func stagePill(_ name: String, hours: Double, total: Double, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%.1fh", hours)).font(.caption2.weight(.bold).monospacedDigit())
            Text(name).font(.system(size: 8)).foregroundStyle(.secondary)
            if total > 0 {
                Text("\(Int(hours / total * 100))%").font(.system(size: 8).monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Recovery Detail

    private func recoveryDetailCard(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recovery").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(r.recoveryLevel.rawValue)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(r.recoveryLevel == .green ? Theme.deficit : r.recoveryLevel == .yellow ? Theme.fatYellow : Theme.surplus)
            }

            Text(recoveryInsight(r))
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private func recoveryInsight(_ r: RecoveryEstimator.DailyRecovery) -> String {
        if r.recoveryScore >= 67 {
            return "Your body is well recovered. Good time for high-intensity training."
        } else if r.recoveryScore >= 34 {
            return "Moderate recovery. Consider lighter training or active recovery today."
        } else {
            return "Low recovery. Prioritize rest, hydration, and sleep tonight."
        }
    }

    // MARK: - Sleep Trend

    private var sleepTrendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sleep Trend").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                let avg = sleepHistory.map(\.hours).reduce(0, +) / Double(max(1, sleepHistory.count))
                Text("avg \(String(format: "%.1f", avg))h").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
            }

            Chart {
                // Sleep need reference line
                RuleMark(y: .value("", 7.5))
                    .foregroundStyle(Theme.deficit.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .topLeading, spacing: 2) {
                        Text("Need").font(.system(size: 8)).foregroundStyle(Theme.deficit.opacity(0.5))
                    }

                ForEach(sleepHistory.indices, id: \.self) { i in
                    let entry = sleepHistory[i]
                    BarMark(x: .value("", entry.date), y: .value("", entry.hours))
                        .foregroundStyle(entry.hours >= 7 ? Theme.sleepIndigo : Theme.fatYellow)
                        .cornerRadius(3)
                }
            }
            .chartYScale(domain: 0...12)
            .chartYAxis {
                AxisMarks(values: [0, 3, 6, 9, 12]) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)
        }
        .card()
    }

    // MARK: - Vitals

    private func vitalsCard(_ r: RecoveryEstimator.DailyRecovery) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Vitals").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)

            HStack(spacing: 10) {
                vitalPill("HRV", value: r.hrvMs > 0 ? "\(Int(r.hrvMs))ms" : "--", icon: "waveform.path", color: Theme.deficit)
                vitalPill("RHR", value: r.restingHR > 0 ? "\(Int(r.restingHR))bpm" : "--", icon: "heart.fill", color: Theme.heartRed)
                vitalPill("Resp", value: r.respiratoryRate > 0 ? String(format: "%.1f", r.respiratoryRate) : "--", icon: "lungs.fill", color: Theme.calorieBlue)
            }
        }
        .card()
    }

    private func vitalPill(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.caption.weight(.bold).monospacedDigit())
            Text(label).font(.system(size: 8)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 6)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Data Loading

    private func loadData() async {
        let hk = HealthKitService.shared
        let today = Date()

        do {
            let sleepDetail = try await hk.fetchSleepDetail(for: today)
            let hrv = try await hk.fetchHRV(for: today)
            let rhr = try await hk.fetchRestingHeartRate(for: today)
            let resp = try await hk.fetchRespiratoryRate(for: today)
            let calories = try await hk.fetchCaloriesBurned(for: today)
            let steps = try await hk.fetchSteps(for: today)

            let strain = RecoveryEstimator.calculateStrain(activeCalories: calories.active, steps: steps)
            let sleepNeed = RecoveryEstimator.estimatedSleepNeed(strain: strain)
            let (recoveryScore, recoveryLevel) = RecoveryEstimator.calculateRecovery(
                hrvMs: hrv, restingHR: rhr, sleepHours: sleepDetail.totalHours
            )
            let sleepScore = RecoveryEstimator.calculateSleepScore(
                totalHours: sleepDetail.totalHours, remHours: sleepDetail.remHours, deepHours: sleepDetail.deepHours
            )

            recovery = RecoveryEstimator.DailyRecovery(
                date: today, recoveryScore: recoveryScore, recoveryLevel: recoveryLevel,
                sleepScore: sleepScore, strainScore: strain,
                sleepHours: sleepDetail.totalHours, sleepNeeded: sleepNeed,
                hrvMs: hrv, restingHR: rhr, respiratoryRate: resp,
                sleepDetail: sleepDetail
            )

            sleepHistory = try await hk.fetchSleepHistory(days: 30)
        } catch {
            Log.healthKit.error("Sleep/Recovery load failed: \(error.localizedDescription)")
        }

        isLoading = false
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date)
    }
}
