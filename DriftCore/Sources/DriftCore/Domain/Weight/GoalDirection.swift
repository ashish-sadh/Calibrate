import Foundation

/// User's intended weight direction, plus whether an observed weekly rate moves
/// them toward it.
///
/// Lifted out of `Drift/Views/BodySummaryCardsRow.swift` (#1202/#1203): the
/// dashboard WEIGHT card's goal-aware colour is the same rule on both
/// platforms, and Android had no copy of it — so its WEIGHT value rendered a
/// flat accent tint regardless of whether the user was moving toward the goal
/// or away from it. One rule, one place; the views only map `Alignment` to a
/// `Color` (they can't — `Theme` is UI, and this package is UI-free).
public enum GoalDirection: Equatable, Sendable {
    case lose
    case gain
    case maintain
    case none

    /// Transcribed from `DashboardView.goalDirection`. `currentWeightKg` is the
    /// caller's displayed weight (latest, else trend); nil falls back to the
    /// goal's start weight, so a goal with no weigh-ins still reads as a
    /// direction instead of `.none`.
    public static func derive(goal: WeightGoal?, currentWeightKg: Double?) -> GoalDirection {
        guard let goal else { return .none }
        let currentKg = currentWeightKg ?? goal.startWeightKg
        if abs(currentKg - goal.targetWeightKg) < 0.1 { return .maintain }
        return goal.isLosing(currentWeightKg: currentKg) ? .lose : .gain
    }

    /// Whether a weekly rate helps or hurts. Deliberately colour-free — the
    /// green/red mapping is a view concern (`Theme.deficit` / `Theme.surplus`).
    public enum Alignment: Equatable, Sendable {
        case aligned
        case against
        case neutral
    }

    /// Colour-free core of `BodySummaryCardsRow.goalAlignedColor`. A missing,
    /// non-finite, or effectively-zero rate is `.neutral` — as is `.maintain`
    /// (drifting either way off a maintenance target is not "good" or "bad")
    /// and `.none` (no goal to be aligned with).
    public func alignment(ofWeeklyRateKg rate: Double?) -> Alignment {
        guard let rate, rate.isFinite, abs(rate) > 0.001 else { return .neutral }
        switch self {
        case .lose: return rate < 0 ? .aligned : .against
        case .gain: return rate > 0 ? .aligned : .against
        case .maintain, .none: return .neutral
        }
    }
}
