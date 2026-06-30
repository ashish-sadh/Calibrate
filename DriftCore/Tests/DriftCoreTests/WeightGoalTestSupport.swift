import Foundation
@testable import DriftCore

/// A `WeightGoal.startDate` anchored to the current date, so the full
/// `monthsToAchieve` window stays in the future and `weeksRemaining > 0`.
///
/// WeightGoal's rate / deficit / on-track math is measured from the real clock:
/// `daysRemaining` counts from `Date()` to the goal's target date. Hardcoded
/// fixture start dates rot silently — once the real date passes a goal's target
/// date the goal is "expired", so `requiredWeeklyRate` and `requiredDailyDeficit`
/// collapse to 0 and `isOnTrack` returns `.onTrack` for every input, turning
/// every direction / rate assertion red. (That is exactly how #916 turned tier-0
/// red: fixtures dated "2026-01-01" + 6 months landed on 2026-07-01, which the
/// real clock reached on 2026-06-30.) Anchoring the start to "today" makes these
/// fixtures time-invariant — they cannot rot again.
///
/// Use ONLY for fixtures whose assertions exercise date-sensitive math
/// (requiredWeeklyRate / requiredDailyDeficit / isOnTrack). Date-independent
/// fixtures (isLosing / remainingKg / progress / totalChangeKg) must keep their
/// literal start dates so the diff stays minimal and intent stays explicit.
func currentGoalStartDate() -> String {
    DateFormatters.todayString
}
