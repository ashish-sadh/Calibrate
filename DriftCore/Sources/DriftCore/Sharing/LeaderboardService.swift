import Foundation

/// Reading and publishing boards.
@MainActor
public enum LeaderboardService {

    /// The date key for a period containing `date`.
    ///
    /// Weekly boards anchor on MONDAY, explicitly — not on the locale's first
    /// weekday. A user in the US (Sunday-first) and one in Germany (Monday-first)
    /// must agree on which week it is, or the same board shows two windows and
    /// the same person can hold two rows for one week.
    ///
    /// `nonisolated` because it's pure date math and is used as a default
    /// argument, which Swift evaluates outside the actor.
    public nonisolated static func periodStart(_ period: LeaderboardBoard.Period,
                                              for date: Date = Date(),
                                              calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.firstWeekday = 2  // Monday
        let component: Calendar.Component = period == .week ? .weekOfYear : .month
        let start = cal.dateInterval(of: component, for: date)?.start ?? date
        return DateFormatters.dateOnly.string(from: start)
    }

    /// Every board worth showing, for you and your friends, right now.
    ///
    /// ONE round trip per 50 friends. Both period keys go in a single
    /// `period_start=in.(...)` filter so the weekly and monthly families arrive
    /// together — asking per board would be a request per exercise, which is the
    /// shape that makes a feature like this quietly expensive.
    ///
    /// Coaches and clients are excluded: a board is a peer thing, and ranking
    /// yourself against the person you pay changes that relationship into
    /// something neither of you asked for.
    public static func sections(connections: [Connection],
                               now: Date = Date()) async -> [Leaderboard.Section] {
        let svc = SharingService.shared
        guard svc.isSignedIn, Preferences.shareStatsWithFriends,
              let me = svc.currentSession?.userID else { return [] }

        var profiles = Dictionary(uniqueKeysWithValues:
            connections.filter { $0.kind == .friend }.map { ($0.profile.id, $0.profile) })
        // You appear from your own PUBLISHED row, on the same terms as everyone
        // else, rather than from a local shortcut that could disagree with what
        // friends see.
        if let mine = svc.currentUsername {
            profiles[me] = SharedProfile(id: me, username: mine)
        }
        guard profiles.count >= Leaderboard.minimumParticipants else { return [] }

        let periods = [periodStart(.week, for: now), periodStart(.month, for: now)]
        let entries = (try? await svc.leaderboardEntries(userIDs: Array(profiles.keys),
                                                        periods: periods)) ?? []
        return Leaderboard.sections(from: entries, profiles: profiles, me: me)
    }

    /// Turning sharing off REMOVES what was published — a switch that only stops
    /// future writes leaves last month's deadlift on your friends' boards, which
    /// is not what anyone means by turning it off.
    public static func withdraw() async {
        try? await SharingService.shared.deleteMyLeaderboardEntries()
    }
}
