import Foundation

/// Aggregates Drift's existing on-device intelligence into a single ranked, deduped `BriefInput`
/// for the proactive "Today's Brief" coaching surface (epic #875).
///
/// The Today screen historically rendered only
/// `BehaviorInsightService.computeProactiveAlerts().first` (DashboardView.swift:199), discarding
/// every other signal. This service is the seam that lets the brief synthesize across 2-3 signals:
/// it composes `computeProactiveAlerts()`, `CrossDomainPatternService.detect()`, and a selected
/// analytical-tool summary, then ranks, dedups, and caps them. No new analytics — pure composition
/// of what already exists.
///
/// Structured as a pure core (`buildBriefInput` and the mappers below — `nonisolated`, fully Tier-0
/// tested) behind a thin `@MainActor` collector (`aggregate`) that touches the DB-backed sources.
/// Pure logic, no UIKit/HealthKit import → DriftCore (tenet #6).
public enum CoachingBriefService {

    /// Max signals the brief surfaces — never a wall of cards (visual_criterion v1).
    public static let signalCap = 3
    /// Below this many days of logged data the brief is thin-data: an onboarding nudge, not an insight.
    public static let minDataDays = 3
    /// Window for the data-sufficiency count.
    static let lookbackDays = 30

    // MARK: - Pure core (nonisolated, Tier-0 tested)

    /// Build the brief from already-collected signals. Pure — the `@MainActor` `aggregate` feeds it
    /// live data, tests feed it fixtures. `< minDataDays` of data short-circuits to an explicit
    /// thin-data input (no signals) so the surface shows an onboarding nudge, never an empty shell.
    public static func buildBriefInput(
        alerts: [BehaviorInsight],
        patterns: [CrossDomainPattern],
        toolSignals: [BriefSignal],
        dataDayCount: Int
    ) -> BriefInput {
        guard dataDayCount >= minDataDays else {
            return BriefInput(signals: [], isThinData: true, dataDayCount: dataDayCount)
        }
        let combined = alerts.map { signal(from: $0) }
            + patterns.map { signal(from: $0) }
            + toolSignals
        return BriefInput(
            signals: rankDedupCap(combined),
            isThinData: false,
            dataDayCount: dataDayCount
        )
    }

    /// Deterministic order, dedup, cap. Sorts by source priority then original position (an explicit
    /// tiebreak — never relies on `sort` stability), dedups by `id` first-wins (so the highest-priority
    /// signal survives an id collision, since the sort already put it first), and caps at `signalCap`.
    static func rankDedupCap(_ signals: [BriefSignal], cap: Int = signalCap) -> [BriefSignal] {
        let ordered = signals.enumerated().sorted { lhs, rhs in
            if lhs.element.source.priority != rhs.element.source.priority {
                return lhs.element.source.priority < rhs.element.source.priority
            }
            return lhs.offset < rhs.offset
        }
        var seen = Set<String>()
        let deduped = ordered.map(\.element).filter { seen.insert($0.id).inserted }
        return Array(deduped.prefix(cap))
    }

    /// Map an actionable alert. `isPositive` is the alert's own good/bad read, which is exactly its
    /// goal-relative direction here (a "positive" alert is aligned with the goal). The stable id is
    /// the alert's `dismissKey` when it has one (so brief dismissal can reuse the 24h dismissal key),
    /// else a slug of the title.
    static func signal(from alert: BehaviorInsight) -> BriefSignal {
        BriefSignal(
            id: alert.dismissKey ?? "alert-\(slug(alert.title))",
            source: .alert,
            title: alert.title,
            detail: alert.detail,
            goalDirection: alert.isPositive ? .aligned : .against
        )
    }

    /// Map a detected correlation. A correlation has no inherent goal direction → `.neutral`; the
    /// narrator frames it. The id is built from `UnorderedMetricPair` so it's stable regardless of
    /// which metric the service reported as A vs B (the dedup invariant). Title is the pretty metric
    /// pair; detail is the service's own natural-language sentence.
    static func signal(from pattern: CrossDomainPattern) -> BriefSignal {
        let pair = UnorderedMetricPair(pattern.metricA, pattern.metricB)
        return BriefSignal(
            id: "pattern-\(pair.a)-\(pair.b)",
            source: .pattern,
            title: "\(CrossDomainInsightTool.prettyName(pair.a)) ↔ \(CrossDomainInsightTool.prettyName(pair.b))",
            detail: pattern.summary,
            goalDirection: .neutral
        )
    }

    /// Wrap a `WeightTrendPredictionTool.run()` summary as a tool signal — or `nil` when the tool
    /// returned one of its not-ready guard sentinels (no goal set, <7 days of data, degenerate
    /// trend). Those are "go log more" nudges, not insights; surfacing one would be noise. Pure, so
    /// the filtering is Tier-0 tested. Direction is `.neutral` — the summary carries the trend; the
    /// narrator decides the stance rather than us parsing free text.
    static func weightTrendSignal(summary: String) -> BriefSignal? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !weightTrendNotReadyPrefixes.contains(where: { trimmed.hasPrefix($0) }) else { return nil }
        return BriefSignal(
            id: "weight-trend",
            source: .tool,
            title: "Weight trend",
            detail: trimmed,
            goalDirection: .neutral
        )
    }

    /// Lead phrases of `WeightTrendPredictionTool.run()`'s guard-clause early returns — the
    /// "not enough signal yet" states the brief never surfaces as an insight.
    static let weightTrendNotReadyPrefixes = [
        "Set a goal weight first",
        "Need at least",
        "Couldn't compute a trend",
    ]

    /// Lowercased, hyphenated, alphanumeric slug for a stable id derived from a title.
    static func slug(_ s: String) -> String {
        let cleaned = s.lowercased().map { ($0.isLetter || $0.isNumber) ? $0 : "-" }
        return String(cleaned).split(separator: "-").joined(separator: "-")
    }

    // MARK: - Impure collector (@MainActor)

    /// Collect live signals from the DB-backed sources and build the brief. The only impure seam —
    /// kept thin; all the ranking / dedup / cap / thin-data logic lives in the pure core above.
    @MainActor
    public static func aggregate(now: Date = Date(), recentAppleWorkouts: [Date] = []) -> BriefInput {
        buildBriefInput(
            alerts: BehaviorInsightService.computeProactiveAlerts(recentAppleWorkouts: recentAppleWorkouts),
            patterns: CrossDomainPatternService.detect(now: now),
            toolSignals: selectedToolSignals(),
            dataDayCount: loggedDayCount(now: now)
        )
    }

    /// The selected analytical tool — a weight-trend projection, relevant to every user with a goal.
    @MainActor
    static func selectedToolSignals() -> [BriefSignal] {
        [weightTrendSignal(summary: WeightTrendPredictionTool.run())].compactMap { $0 }
    }

    /// Distinct days in the last `lookbackDays` with logged food (calories > 100) — the brief's
    /// data-sufficiency measure, matching `BehaviorInsightService`'s logging-day threshold.
    @MainActor
    static func loggedDayCount(now: Date) -> Int {
        let db = AppDatabase.shared
        let calendar = Calendar.current
        var count = 0
        for dayOffset in 0..<lookbackDays {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { break }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            if let nutrition = try? db.fetchDailyNutrition(for: dateStr), nutrition.calories > 100 {
                count += 1
            }
        }
        return count
    }
}
