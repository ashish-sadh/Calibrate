import Foundation

/// Turns "when was each muscle group last trained" into recovery statuses,
/// using the client's LEARNED per-group recovery estimates.
///
/// Extracted so the client's own Muscle Recovery card and the coach briefing
/// grade the same body identically. The colour a coach sees has to be the
/// colour the client sees — a shared calculator is the only way that stays
/// true as the thresholds keep learning (`MuscleSoreness`).
public enum MuscleRecoveryMap {

    /// The six groups the body map draws, in the order it draws them.
    public static let groups = ["Chest", "Back", "Shoulders", "Arms", "Core", "Legs"]

    /// Beyond this, a group reads as untrained rather than "recovered" —
    /// three weeks off is not the same as ready, and a coach should see the
    /// difference.
    public static let untrainedAfterDays = 7

    /// `lastTrained` is group → the most recent date that group was worked.
    /// Groups absent from it come back `.untrained`.
    public static func points(lastTrained: [String: Date],
                             soreness: MuscleSoreness.State,
                             today: Date = Date(),
                             calendar: Calendar = .current) -> [MuscleRecoveryPoint] {
        groups.map { group in
            guard let last = lastTrained[group],
                  let days = calendar.dateComponents([.day], from: last, to: today).day else {
                return MuscleRecoveryPoint(group: group, status: .untrained)
            }
            guard days <= untrainedAfterDays else {
                return MuscleRecoveryPoint(group: group, status: .untrained, daysSince: days)
            }
            // Workout dates are day-granular, hence days × 24.
            let estimate = MuscleSoreness.recoveryHours(for: group, state: soreness)
            let status: MuscleRecoveryPoint.Status
            switch MuscleSoreness.status(hoursSince: Double(days) * 24, recoveryHours: estimate) {
            case .recovering: status = .recovering
            case .moderate:   status = .moderate
            case .recovered:  status = .recovered
            }
            return MuscleRecoveryPoint(group: group, status: status, daysSince: days)
        }
    }

    /// Group → last-trained date, read from recent workout history. Mirrors
    /// the window the body map uses so the two never disagree about what
    /// "recent" means.
    public static func lastTrainedByGroup(historyDays: Int = 14,
                                         today: Date = Date(),
                                         calendar: Calendar = .current) -> [String: Date] {
        guard let workouts = try? WorkoutService.fetchWorkouts(limit: 500) else { return [:] }
        var lastTrained: [String: Date] = [:]
        for workout in workouts {
            guard let date = DateFormatters.dateOnly.date(from: String(workout.date.prefix(10))),
                  let id = workout.id,
                  let days = calendar.dateComponents([.day], from: date, to: today).day,
                  days <= historyDays else { continue }
            for set in (try? WorkoutService.fetchSets(forWorkout: id)) ?? [] {
                let group = ExerciseDatabase.bodyPart(for: set.exerciseName)
                if let existing = lastTrained[group] {
                    if date > existing { lastTrained[group] = date }
                } else {
                    lastTrained[group] = date
                }
            }
        }
        return lastTrained
    }
}
