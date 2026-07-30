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

    /// Which sections are folded away. Everything a coach ACTS on is open by
    /// default (alerts, stats, trends); the reference material — recovery
    /// figures, body composition, best sets, history — collapses so the page
    /// is scannable rather than a wall (operator 2026-07-29: "make it readable
    /// and collapsible for easy reads"). Not private: Fuse can't bridge
    /// private @State.
    @State var collapsed: Set<String> = ["recovery", "bodycomp", "records", "history"]

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
        section("bodycomp", "BODY COMPOSITION", subtitle: bodyCompSummary) {
            VStack(spacing: 10) {
                // Regional fat on the same body model as recovery — one visual
                // language for "where on the body", so a coach doesn't learn
                // two diagrams.
                if !regionalFat.isEmpty {
                    HStack(spacing: 10) {
                        MuscleBodyView(side: .front,
                                       slugColors: regionalFatSlugColors,
                                       colorSignature: regionalSignature)
                            .frame(height: 190)
                        MuscleBodyView(side: .back,
                                       slugColors: regionalFatSlugColors,
                                       colorSignature: regionalSignature)
                            .frame(height: 190)
                    }
                    VStack(spacing: 4) {
                        ForEach(regionalFat, id: \.label) { region in
                            HStack {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(fatColor(region.value)).frame(width: 10, height: 3)
                                Text(region.label)
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(String(format: "%.1f%% fat", region.value))
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                    legend([(Theme.deficit, "leaner"), (Theme.stepsOrange, "mid"),
                            (Theme.surplus, "higher")])
                    Divider().overlay(Theme.separatorFaint)
                }

                VStack(spacing: 6) {
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
            }
        }
    }

    var bodyCompSummary: String {
        guard let fat = metrics.bodyFatPct else { return "" }
        return String(format: "%.1f%% body fat", fat)
    }

    /// Regions the scan actually measured — a missing region is omitted, never
    /// drawn as zero.
    var regionalFat: [(label: String, value: Double, slugs: [String])] {
        var out: [(String, Double, [String])] = []
        if let trunk = metrics.trunkFatPct {
            out.append(("Trunk", trunk, ["chest", "abs", "obliques", "upper-back", "lower-back"]))
        }
        if let arms = metrics.armsFatPct {
            out.append(("Arms", arms, ["biceps", "triceps", "forearm", "deltoids"]))
        }
        if let legs = metrics.legsFatPct {
            out.append(("Legs", legs, ["quadriceps", "hamstring", "gluteal", "calves", "adductors"]))
        }
        return out
    }

    var regionalFatSlugColors: [String: Color] {
        var colors: [String: Color] = [:]
        for region in regionalFat {
            for slug in region.slugs { colors[slug] = fatColor(region.value).opacity(0.6) }
        }
        return colors
    }

    var regionalSignature: String {
        regionalFat.map { String(format: "%@:%.1f", $0.label, $0.value) }.joined(separator: ",")
    }

    /// A readiness-style scale for fat percentage, NOT a good/bad judgement:
    /// the bands are population-typical reference points so a coach can see
    /// distribution at a glance. Deliberately coarse — a precise colour ramp
    /// would imply a precision DEXA regional figures don't carry.
    func fatColor(_ pct: Double) -> Color {
        if pct < 20 { return Theme.deficit }
        if pct < 30 { return Theme.stepsOrange }
        return Theme.surplus
    }

    // MARK: - Collapsible section chrome

    /// A titled, foldable card. The header is one tap target the whole width
    /// of the card, and the chevron states which way it goes.
    @ViewBuilder
    func section<Content: View>(_ key: String, _ title: String,
                               subtitle: String? = nil,
                               @ViewBuilder content: () -> Content) -> some View {
        let isCollapsed = collapsed.contains(key)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isCollapsed { collapsed.remove(key) } else { collapsed.insert(key) }
            } label: {
                HStack(spacing: 6) {
                    Text(title).sectionHeading()
                    if let subtitle, isCollapsed {
                        Text(subtitle)
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Image(systemName: sym(isCollapsed ? "chevron.down" : "chevron.up"))
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed { content() }
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
        section("recovery", "RECOVERY", subtitle: recoverySummary(recovery)) {
            VStack(spacing: 10) {
                // The SAME anatomical figure the client sees on their own
                // Muscle Recovery card — `MuscleBodyView` already takes
                // injected per-slug colours, so the coach gets the real body
                // model rather than a second-class abstraction of it.
                HStack(spacing: 10) {
                    MuscleBodyView(side: .front,
                                   slugColors: recoverySlugColors(recovery),
                                   colorSignature: recoverySignature(recovery))
                        .frame(height: 190)
                    MuscleBodyView(side: .back,
                                   slugColors: recoverySlugColors(recovery),
                                   colorSignature: recoverySignature(recovery))
                        .frame(height: 190)
                }
                // The figure shows WHERE; the chips give the exact ages, which
                // a figure can't carry.
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
                legend([(Theme.surplus, "still recovering"),
                        (Theme.stepsOrange, "part-way"),
                        (Theme.deficit, "ready")])
            }
        }
    }

    /// Collapsed-state summary, so the header still says something useful
    /// without unfolding: "2 ready · 1 recovering".
    func recoverySummary(_ recovery: [MuscleRecoveryPoint]) -> String {
        let ready = recovery.filter { $0.status == .recovered }.count
        let cooked = recovery.filter { $0.status == .recovering }.count
        return "\(ready) ready · \(cooked) recovering"
    }

    /// Group statuses → per-slug colours for the body model. Untrained groups
    /// are left unpainted so the figure reads calm, exactly as the client's
    /// own map does.
    func recoverySlugColors(_ recovery: [MuscleRecoveryPoint]) -> [String: Color] {
        var colors: [String: Color] = [:]
        for point in recovery where point.status != .untrained {
            for slug in BodyMapView.groupSlugs[point.group] ?? [] {
                colors[slug] = recoveryColor(point.status).opacity(0.65)
            }
        }
        return colors
    }

    /// `MuscleBodyView` caches built figures per signature on Android (#1074),
    /// and `Color` has no cross-platform introspection — so any caller passing
    /// explicit colours must hand it a string that changes when they do.
    func recoverySignature(_ recovery: [MuscleRecoveryPoint]) -> String {
        recovery.map { "\($0.group):\($0.status.rawValue)" }.joined(separator: ",")
    }

    func legend(_ items: [(color: Color, label: String)]) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(item.color).frame(width: 10, height: 3)
                    Text(item.label)
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer()
        }
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
        section("records", "BEST SETS", subtitle: "\(records.count) lifts") {
            VStack(alignment: .leading, spacing: 7) {
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
        }
    }

    /// The written picture: the intake summary, then the dated note log —
    /// newest first, because a six-month-old sore shoulder is history while
    /// last week's is a training constraint.
    var insightsCard: some View {
        section("history", "FROM DRIFT'S AI COACH",
                subtitle: "\(briefing.notes.count) notes") {
            VStack(alignment: .leading, spacing: 8) {
                // PROVENANCE, stated once and loudly (operator 2026-07-29:
                // "AI notes are confusing, looks like trainer added it").
                // Everything in this card was written by the app from the
                // client's own words — never by a human coach.
                Text("Written by Drift's AI coach from what the client told it — not by you.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)

                if !briefing.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AI SUMMARY OF THEIR SETUP").sectionHeading()
                        Text(briefing.summary)
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                        Text("From the client's answers in Coach Me.")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }

                if !briefing.notes.isEmpty {
                    Divider().overlay(Theme.separatorFaint)
                    ForEach(briefing.notes.suffix(6).reversed(), id: \.id) { note in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(note.date)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                                // Per-note source: an intake answer and a line
                                // the AI picked out of a chat are different
                                // kinds of evidence.
                                Text(noteSource(note.kind))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Theme.chartTrend.opacity(0.12), in: Capsule())
                                    .foregroundStyle(Theme.chartTrend)
                                Spacer()
                            }
                            Text(note.text)
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
            }
        }
    }

    /// Where one note actually came from — all AI-authored, but from different
    /// moments, which changes how much weight a coach gives it.
    func noteSource(_ kind: CoachNotes.Note.Kind) -> String {
        switch kind {
        case .intake: return "AI · intake"
        case .moment: return "AI · from chat"
        case .observation: return "AI · program"
        }
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
