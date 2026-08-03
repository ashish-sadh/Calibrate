import Foundation

/// "Swap the squats for something else" — picking a real substitute.
///
/// Mid-workout, a swap is asked for because something is wrong: the rack is
/// taken, the knee is complaining, the weight isn't there. So the substitute has
/// to train the SAME thing — swapping a squat for a curl is not a swap, it's a
/// different workout — and it has to be one the person can actually do right
/// now with the equipment they have.
///
/// Deterministic and local. This runs between sets, where a network round trip
/// is the difference between a useful answer and a dead pause.
public enum ExerciseAlternatives {

    /// Substitutes for `name`, best first.
    ///
    /// Ranked by how much of the original's work they reproduce:
    /// 1. every primary muscle matches — a true like-for-like swap;
    /// 2. some primary overlap, preferring more;
    /// 3. same body part, as the floor.
    ///
    /// `excluding` is what's already in the session: offering someone the lift
    /// they're already doing three sets of is the one answer guaranteed to be
    /// useless. `equipment` empty means "no filter" — an unknown gym is not a
    /// reason to refuse to answer.
    public static func suggestions(for name: String,
                                  excluding: Set<String> = [],
                                  equipment: Set<String> = [],
                                  limit: Int = 5) -> [ExerciseDatabase.ExerciseInfo] {
        guard let original = ExerciseDatabase.info(for: name)
                ?? ExerciseDatabase.match(name: name) else { return [] }

        let blocked = Set(excluding.map { $0.lowercased() })
            .union([original.name.lowercased()])
        let wantedPrimary = Set(original.primaryMuscles.map { $0.lowercased() })

        let pool = ExerciseDatabase.all.filter { candidate in
            guard !blocked.contains(candidate.name.lowercased()) else { return false }
            guard equipment.isEmpty || ExerciseDatabase.isDoable(candidate, with: equipment)
            else { return false }
            let primary = Set(candidate.primaryMuscles.map { $0.lowercased() })
            // Same body part is the floor — anything less isn't a substitute.
            return !primary.isDisjoint(with: wantedPrimary)
                || candidate.bodyPart.lowercased() == original.bodyPart.lowercased()
        }

        return pool
            .map { (info: $0, score: score($0, against: original, wantedPrimary: wantedPrimary)) }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                // Stable, and it keeps the list from reshuffling between asks.
                return $0.info.name < $1.info.name
            }
            .prefix(limit)
            .map(\.info)
    }

    /// The single best substitute, or nil when the catalog has nothing close.
    public static func best(for name: String,
                           excluding: Set<String> = [],
                           equipment: Set<String> = []) -> ExerciseDatabase.ExerciseInfo? {
        suggestions(for: name, excluding: excluding, equipment: equipment, limit: 1).first
    }

    /// How good a substitute this is. Higher is better.
    static func score(_ candidate: ExerciseDatabase.ExerciseInfo,
                     against original: ExerciseDatabase.ExerciseInfo,
                     wantedPrimary: Set<String>) -> Int {
        let primary = Set(candidate.primaryMuscles.map { $0.lowercased() })
        let overlap = primary.intersection(wantedPrimary).count

        var score = overlap * 10
        // A full primary match is the real like-for-like swap, and worth more
        // than the sum of its overlaps.
        if !wantedPrimary.isEmpty, primary == wantedPrimary { score += 25 }
        if candidate.bodyPart.lowercased() == original.bodyPart.lowercased() { score += 5 }
        // Same equipment keeps the swap practical — you're already standing at
        // the rack. Never decisive: the usual REASON for a swap is that the
        // equipment isn't available.
        if candidate.equipment.lowercased() == original.equipment.lowercased() { score += 3 }
        // Prefer the same difficulty, so a swap doesn't quietly hand a beginner
        // an advanced lift mid-session.
        if candidate.level.lowercased() == original.level.lowercased() { score += 2 }
        return score
    }
}
