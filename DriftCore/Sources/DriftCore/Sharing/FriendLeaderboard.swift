import Foundation

/// A week of ambient activity, as one friend sees another's.
///
/// Deliberately ambient metrics — steps, calories burned, workout count. None
/// of them require logging discipline, so the board measures activity rather
/// than "who is most diligent about using the app", which is what a
/// food-logging or weigh-in board would really rank.
public struct FriendStats: Sendable, Equatable, Codable {
    public let profile: SharedProfile
    /// Sunday-anchored ISO date of the week these numbers cover.
    public let weekStart: String
    public let steps: Int
    public let caloriesBurned: Int
    /// Workouts the person logged themselves.
    public let workoutsLogged: Int
    /// Workouts that arrived from Apple Health / Health Connect. Counted
    /// separately and shown separately: a run your watch noticed is not the
    /// same claim as a session you sat down and recorded, and rolling them
    /// into one number quietly rewards owning a watch.
    public let workoutsImported: Int

    public init(profile: SharedProfile, weekStart: String, steps: Int,
                caloriesBurned: Int, workoutsLogged: Int, workoutsImported: Int) {
        self.profile = profile
        self.weekStart = weekStart
        self.steps = steps
        self.caloriesBurned = caloriesBurned
        self.workoutsLogged = workoutsLogged
        self.workoutsImported = workoutsImported
    }

    public var workoutsTotal: Int { workoutsLogged + workoutsImported }
}

public enum FriendLeaderboard {

    /// What a board is sorted by. Steps first: it's the metric everyone has,
    /// with no watch, no logging and no gym.
    public enum Metric: String, Sendable, CaseIterable {
        case steps, caloriesBurned, workouts

        public var label: String {
            switch self {
            case .steps: return "Steps"
            case .caloriesBurned: return "Calories burned"
            case .workouts: return "Workouts"
            }
        }

        func value(of stats: FriendStats) -> Int {
            switch self {
            case .steps: return stats.steps
            case .caloriesBurned: return stats.caloriesBurned
            case .workouts: return stats.workoutsTotal
            }
        }
    }

    /// A row on the board, with its position resolved.
    public struct Row: Sendable, Equatable {
        public let rank: Int
        public let stats: FriendStats
        public let value: Int
        /// True for the signed-in user's own row, so the UI can anchor on it
        /// rather than making someone hunt for themselves.
        public let isMe: Bool
    }

    /// Rank `entries` by `metric`, highest first.
    ///
    /// Equal values share a rank (two people on 40,000 steps are both 2nd, and
    /// the next row is 4th) — a board that breaks a genuine tie arbitrarily
    /// tells one of them they lost when they didn't. Ordering within a tie is
    /// by username so the list doesn't reshuffle between refreshes.
    ///
    /// People with nothing to show are dropped rather than parked at the
    /// bottom on zero. A leaderboard's failure mode is making someone feel
    /// watched while they're having a bad week, and a visible 0 next to your
    /// name does that better than anything else on the screen.
    public static func rank(_ entries: [FriendStats],
                           by metric: Metric,
                           me: String?) -> [Row] {
        let scored = entries
            .map { (stats: $0, value: metric.value(of: $0)) }
            .filter { $0.value > 0 }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                let a: String = lhs.stats.profile.username.lowercased()
                let b: String = rhs.stats.profile.username.lowercased()
                return a < b
            }

        var rows: [Row] = []
        var lastValue: Int?
        var lastRank = 0
        for (index, entry) in scored.enumerated() {
            let rank = entry.value == lastValue ? lastRank : index + 1
            rows.append(Row(rank: rank, stats: entry.stats, value: entry.value,
                            isMe: entry.stats.profile.id == me))
            lastValue = entry.value
            lastRank = rank
        }
        return rows
    }

    /// Where the user sits, phrased without naming anyone else — the line that
    /// goes on Today, where a full ranking would be too much.
    ///
    /// Returns nil when the user isn't on the board at all; "you are nowhere"
    /// is not a message worth putting on someone's home screen.
    public static func standing(_ rows: [Row], metric: Metric) -> String? {
        guard let mine = rows.first(where: { $0.isMe }) else { return nil }
        guard rows.count > 1 else {
            return "You're the only one sharing \(metric.label.lowercased()) so far"
        }
        if mine.rank == 1 { return "You're leading on \(metric.label.lowercased()) this week" }
        return "#\(mine.rank) of \(rows.count) on \(metric.label.lowercased()) this week"
    }
}
