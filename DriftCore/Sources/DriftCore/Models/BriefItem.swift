import Foundation

/// One narrated insight in the proactive "Today's Brief" coaching surface.
///
/// This is the pure render contract the `BriefNarrator` (S2 / #877) populates by
/// synthesizing across the deterministic signals collected by `CoachingBriefService`
/// (S1 / #876): the narrator turns 2-3 raw signals into a single human sentence with a
/// goal-aware stance and a follow-up chat seed. The card (S3 / #878) is a dumb consumer
/// of `[BriefItem]` — it never computes alignment or wording.
///
/// Defined here, from the consumer side, because #877 is unstarted and its DriftCore
/// narrator must produce this exact type; the fields match #877's spec
/// (title/detail/seedQuery/sourceSignalId) plus the `alignment` the goal-aware color needs.
/// Pure value type, no SwiftUI/UIKit import → DriftCore (tenet #6).
public struct BriefItem: Identifiable, Equatable, Codable, Sendable {

    /// Where this insight sits relative to the user's goal direction. Drives the
    /// goal-aware row color (never a generic good/bad palette): `aligned` reads green,
    /// `against` reads red, `neutral` is informational ink. The narrator decides the
    /// stance from the underlying signal's direction; the card only maps it to a color.
    public enum GoalAlignment: String, Equatable, Codable, Sendable {
        case aligned
        case against
        case neutral
    }

    /// Stable identity for `ForEach` / dismissal — the id of the underlying signal so a
    /// dismissed insight stays dismissed across regenerations of the same day's brief.
    public var id: String { sourceSignalId }

    /// One-line headline, e.g. "Protein dipped 3 days while sleep slid".
    public let title: String
    /// The supporting sentence — the synthesized "why it matters", goal-framed.
    public let detail: String
    /// Pre-filled prompt that opens Drift Coach on tap, e.g.
    /// "Why has my protein been low and how do I fix it this week?".
    public let seedQuery: String
    /// Identifier of the originating deterministic signal (BehaviorInsight key,
    /// CrossDomainPattern id, etc.) — used as the dismissal key and id.
    public let sourceSignalId: String
    /// Goal-relative stance, drives the goal-aware color.
    public let alignment: GoalAlignment

    public init(
        title: String,
        detail: String,
        seedQuery: String,
        sourceSignalId: String,
        alignment: GoalAlignment
    ) {
        self.title = title
        self.detail = detail
        self.seedQuery = seedQuery
        self.sourceSignalId = sourceSignalId
        self.alignment = alignment
    }
}
