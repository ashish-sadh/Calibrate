import Foundation

/// The deterministic input the proactive "Today's Brief" narrator (S2 / #877) synthesizes over.
///
/// `CoachingBriefService` (S1 / #876) aggregates the existing on-device intelligence —
/// `BehaviorInsightService.computeProactiveAlerts()`, `CrossDomainPatternService.detect()`, and a
/// selected analytical-tool summary — into this ranked, deduped, capped list. Every `BriefSignal`
/// is a fact the deterministic layer actually computed; the narrator may phrase and combine them
/// but must never claim a number that isn't here (the over-claim bug class the epic's Tier-3
/// grounding eval guards against). The companion render contract is `BriefItem` (S3 / #878).
///
/// Pure value type, no SwiftUI/UIKit/HealthKit import → DriftCore (tenet #6).
public struct BriefInput: Equatable, Sendable, Codable {

    /// Ranked (alert → pattern → tool), deduped, and capped (≤ `CoachingBriefService.signalCap`)
    /// signals the narrator may synthesize across. Empty when `isThinData`.
    public let signals: [BriefSignal]

    /// True when there isn't yet enough logged data to coach on
    /// (`dataDayCount < CoachingBriefService.minDataDays`). The surface shows a thin-data
    /// onboarding nudge ("log a few days and I'll start spotting patterns") instead of an empty
    /// shell or a fabricated insight (visual_criterion v1).
    public let isThinData: Bool

    /// Distinct days in the last 30 with logged food — the input to the thin-data gate, surfaced
    /// so the onboarding nudge can say how close the user is to unlocking the brief.
    public let dataDayCount: Int

    public init(signals: [BriefSignal], isThinData: Bool, dataDayCount: Int) {
        self.signals = signals
        self.isThinData = isThinData
        self.dataDayCount = dataDayCount
    }
}

/// One deterministic signal feeding the brief — an actionable alert, a detected cross-domain
/// correlation, or a selected analytical-tool projection. The narrator turns 1-3 of these into
/// `BriefItem`s; `id` is the stable dismissal key that survives same-day regeneration.
public struct BriefSignal: Identifiable, Equatable, Sendable, Codable {

    /// Which engine produced the signal. Drives the brief's ranking — actionable alerts beat
    /// correlations beat tool projections.
    public enum Source: String, Equatable, Sendable, Codable {
        case alert
        case pattern
        case tool

        /// Lower sorts first (higher priority) in the brief.
        var priority: Int {
            switch self {
            case .alert: return 0
            case .pattern: return 1
            case .tool: return 2
            }
        }
    }

    /// The deterministic layer's read of where this signal sits relative to the user's goal. The
    /// narrator maps this 1:1 to `BriefItem.GoalAlignment` for the goal-aware color — a raw
    /// correlation has no goal direction, so patterns are `.neutral` and the narrator never invents
    /// a stance the data didn't have.
    public enum GoalDirection: String, Equatable, Sendable, Codable {
        case aligned
        case against
        case neutral
    }

    /// Stable identity — the underlying alert's `dismissKey`, the metric-pair key for a pattern, or
    /// the tool key. Becomes `BriefItem.sourceSignalId` so a dismissed insight stays dismissed
    /// across regenerations of the same day's brief.
    public let id: String
    public let source: Source
    /// Short headline, e.g. "Protein below target" or "Protein ↔ Weight".
    public let title: String
    /// The one-line fact the narrator may state — the alert/pattern/tool's own summary sentence.
    public let detail: String
    public let goalDirection: GoalDirection

    public init(id: String, source: Source, title: String, detail: String, goalDirection: GoalDirection) {
        self.id = id
        self.source = source
        self.title = title
        self.detail = detail
        self.goalDirection = goalDirection
    }
}
