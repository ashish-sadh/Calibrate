import SwiftUI
import DriftCore

/// THE mirror view (#1156): one component renders a `ClientBriefing`
/// everywhere it appears. The coach's client page shows it from the fetched
/// row; the client's sharing card shows it built from LOCAL data — "this is
/// exactly what your coach sees", byte for byte, because it IS the same view.
/// Consent you can see, not a checkbox you trust.
///
/// Reading order is deliberate and matches how a coach actually works:
/// what needs CHANGING (plateaus) → where they ARE (hero stats) → where
/// they're GOING (trends) → the evidence (records, notes).
///
/// Presentation only: no loading, no network, no tap handling — hosts own
/// all of that.
struct CoachBriefingView: View {
    let briefing: ClientBriefing
    /// Shown when the briefing is empty — the two hosts phrase it differently
    /// ("nothing shared yet" vs "turn on a toggle to see a preview").
    var emptyText: String

    private var metrics: BriefingMetrics { briefing.metrics }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if briefing.isEmpty {
                Text(emptyText)
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            } else {
                // FRESHNESS. A briefing only refreshes when the CLIENT's app
                // runs and pushes — the data is local-first, so there is no
                // server-side refresh to fall back on. A coach reading a
                // three-week-old trend as current would change training on
                // stale evidence. Absent on the client's own preview, where
                // the numbers are live local data by construction.
                if let updatedAt = briefing.updatedAt,
                   let date = parseTimestamp(updatedAt) {
                    Text("Updated \(RelativeTime.string(from: date))")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }

                if let plateaus = metrics.plateaus, !plateaus.isEmpty {
                    plateauBand(plateaus)
                }

                if !heroStats.isEmpty { heroRow }

                ForEach(metrics.trends) { trend in
                    trendCard(trend)
                }

                if let recovery = metrics.recovery, !recovery.isEmpty {
                    recoveryCard(recovery)
                }

                if !bodyCompLines.isEmpty { bodyCompCard }

                if let records = metrics.records, !records.isEmpty {
                    recordsCard(records)
                }

                if !briefing.summary.isEmpty || !briefing.notes.isEmpty {
                    insightsCard
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - What needs changing

    /// Plateaus first, in amber: worth attention, not an emergency. A stall
    /// buried under the averages is a stall nobody acts on.
    func plateauBand(_ plateaus: [PlateauAlert]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plateaus) { alert in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: sym("exclamationmark.triangle.fill"))
                        .font(.caption2).foregroundStyle(Theme.fatYellow)
                    Text(alert.text)
                        .font(.caption.weight(.medium)).foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fatYellow.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    // MARK: - Where they are

    /// The three numbers a coach checks first, as big type. Adherence leads:
    /// it's what makes every other number worth reading.
    var heroStats: [(value: String, label: String)] {
        var out: [(String, String)] = []
        if let workouts = metrics.workoutsCompleted {
            out.append(("\(workouts)", "workouts / \(metrics.windowDays)d"))
        }
        if let logged = metrics.daysLogged {
            out.append(("\(logged)/\(metrics.windowDays)", "days logged"))
        }
        if let change = metrics.weightChangeLbs {
            // Neutral, not green/red: the coach view doesn't carry the
            // client's goal direction, and colouring a direction we can't
            // interpret would break the goal-aware-colour tenet.
            out.append((String(format: "%@%.1f", change > 0 ? "+" : "", change),
                        "lb / \(metrics.windowDays)d"))
        }
        return out
    }

    var heroRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(heroStats.enumerated()), id: \.offset) { _, stat in
                VStack(spacing: 2) {
                    Text(stat.value)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text(stat.label)
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.cardBackgroundElevated,
                            in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
            }
        }
    }

    // MARK: - Where they're going

    /// One trend per shared category: the number first (a coach reads
    /// "−2.4 lb over 8w" before any shape), then the line.
    func trendCard(_ trend: BriefingMetrics.Trend) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(trend.label)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(trend.changeText)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.chartTrend)
                Text("over \(trend.weeks)w")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            BriefingTrendChart(values: trend.values)
            HStack {
                Text(trend.format(trend.values.first ?? 0))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(trend.format(trend.values.last ?? 0))
                    .font(.caption2.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(10)
        .background(Theme.cardBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    // MARK: - Body composition

    var bodyCompLines: [(label: String, value: String)] {
        metrics.lines.filter { ["Body fat", "Lean mass", "DEXA scan"].contains($0.label) }
    }

    var bodyCompCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BODY COMPOSITION").sectionHeading()
            ForEach(bodyCompLines, id: \.label) { line in
                HStack {
                    Text(line.label).font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(line.value)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    // MARK: - Recovery

    /// What's fresh and what's cooked, per muscle group — the question a coach
    /// answers before writing today's session.
    ///
    /// A compact status strip rather than the client's full body figure:
    /// `BodyMapView` owns local soreness check-ins, template starts and its
    /// own DB loads, none of which belong on someone else's client page. The
    /// COLOURS are the body map's, so the two read as one system.
    func recoveryCard(_ recovery: [MuscleRecoveryPoint]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECOVERY").sectionHeading()
                Spacer()
                Text("trained / ready")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            // Two rows of three: six groups fit without horizontal scrolling,
            // which keeps it readable at large font scales (cf. #1159).
            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { column in
                            let index = row * 3 + column
                            if index < recovery.count {
                                recoveryChip(recovery[index])
                            } else {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    func recoveryChip(_ point: MuscleRecoveryPoint) -> some View {
        VStack(spacing: 3) {
            Text(point.group)
                .font(.caption2.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(point.shortAge)
                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textSecondary)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(recoveryColor(point.status))
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(recoveryColor(point.status).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    /// Same semantics as `BodyMapView.MuscleStatus.color` — recovery colour is
    /// a readiness scale, not a good/bad judgement, so it is exempt from the
    /// goal-aware rule the way the client's own map is.
    func recoveryColor(_ status: MuscleRecoveryPoint.Status) -> Color {
        switch status {
        case .recovered: return Theme.deficit
        case .moderate: return Theme.stepsOrange
        case .recovering: return Theme.surplus
        case .untrained: return Color.gray.opacity(0.4)
        }
    }

    // MARK: - The evidence

    func recordsCard(_ records: [PersonalRecord]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("BEST SETS").sectionHeading()
            ForEach(records) { record in
                HStack(spacing: 8) {
                    Text(record.exercise)
                        .font(.caption).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(record.setDescription)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    if !record.date.isEmpty {
                        Text(record.date)
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    /// The written picture: the intake summary, then the dated note log —
    /// newest first, because a six-month-old sore shoulder is history while
    /// last week's is a training constraint.
    var insightsCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("HISTORY & NOTES").sectionHeading()
            if !briefing.summary.isEmpty {
                Text(briefing.summary)
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            ForEach(briefing.notes.suffix(6).reversed(), id: \.id) { note in
                HStack(alignment: .top, spacing: 6) {
                    Text(note.date)
                        .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                    Text(note.text)
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackgroundElevated,
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
    }

    /// Postgres hands back `updated_at` with or without fractional seconds
    /// depending on the value, so try both rather than dropping the stamp.
    func parseTimestamp(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
}

/// A weekly trend as one clean connected line with a dot on the latest point
/// — the house chart style (Apple Health / Renpho), not a scatter and not a
/// second "trend" line.
///
/// Path inside a GeometryReader inside a FIXED-height frame: the proven Fuse
/// pattern from `WeightChartAndroid`. The fixed height is what keeps it safe
/// at large system font scales (cf. #1159), and a Path costs one JNI hop per
/// command rather than one per point.
struct BriefingTrendChart: View {
    let values: [Double]
    var height: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let low = values.min() ?? 0
            let high = values.max() ?? 0
            let span = high - low
            let inset: CGFloat = 4
            let usableHeight = max(1, size.height - inset * 2)

            // A flat series has no shape to draw — pin it mid-height, which
            // is honest: no movement rather than a fake slope.
            let points: [CGPoint] = values.enumerated().map { index, value in
                let ratio = span > 0 ? (value - low) / span : 0.5
                let x = values.count <= 1
                    ? size.width / 2
                    : size.width * CGFloat(index) / CGFloat(values.count - 1)
                // Flip: a bigger value sits higher on screen.
                let y = inset + usableHeight * (1 - CGFloat(ratio))
                return CGPoint(x: x, y: y)
            }

            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(Theme.chartTrend, lineWidth: 2)

                // One marker, on the current value — the same emphasis the
                // Health app uses. A dot per point turns a trend into a
                // scatter (chart-style feedback, 2026-07).
                if let last = points.last {
                    Path { path in
                        path.addEllipse(in: CGRect(x: last.x - 3.5, y: last.y - 3.5,
                                                   width: 7, height: 7))
                    }
                    .fill(Theme.chartTrend)
                }
            }
        }
        .frame(height: height)
    }
}
