import Foundation

/// Reading and publishing boards.
/// A global board as the UI needs it: an aspirational few at the top, then the
/// caller's own neighbourhood. Profiles arrive separately — a global board is
/// full of strangers, so names are fetched only for the rows actually rendered.
public struct GlobalBoard: Sendable {
    public let board: LeaderboardBoard
    public let podium: [LeaderboardEntryDTO]
    public let bracket: [LeaderboardEntryDTO]
    public let myValue: Double?
    public let me: String

    /// Every stranger id on screen, for one batched profile fetch.
    public var userIDs: [String] { (podium + bracket).map(\.userId) }
}

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
    /// The period keys worth READING: the current one and the one before it.
    ///
    /// A board used to empty at every rollover. The value is a trailing window
    /// now, but the storage KEY still rolls on Monday (and on the 1st), so a
    /// friend who hasn't opened the app since has no row under the new key —
    /// the board drops below two participants and vanishes for everyone.
    /// Reading both keys and keeping the most recent row per person (see
    /// `Leaderboard.sections`) means their last known number carries over, aged
    /// rather than erased. Operator: "why empty every Monday?"
    public nonisolated static func readPeriods(_ period: LeaderboardBoard.Period,
                                              for date: Date = Date(),
                                              calendar: Calendar = .current) -> [String] {
        let component: Calendar.Component = (period == .month) ? .month : .weekOfYear
        let previous = calendar.date(byAdding: component, value: -1, to: date) ?? date
        return [periodStart(period, for: date, calendar: calendar),
                periodStart(period, for: previous, calendar: calendar)]
    }

    public nonisolated static func periodStart(_ period: LeaderboardBoard.Period,
                                              for date: Date = Date(),
                                              calendar: Calendar = .current) -> String {
        var cal = calendar
        cal.firstWeekday = 2  // Monday
        // `.running` (streaks) stores under the WEEK key: it refreshes on the
        // same cadence as everything else, it just doesn't mean "this week".
        let component: Calendar.Component = (period == .month) ? .month : .weekOfYear
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

        let periods = readPeriods(.week, for: now) + readPeriods(.month, for: now)
        let entries = (try? await svc.leaderboardEntries(userIDs: Array(profiles.keys),
                                                        periods: periods)) ?? []
        return Leaderboard.sections(from: entries, profiles: profiles, me: me)
    }

    /// Your own boards, when no friend has joined them yet. See
    /// `Leaderboard.soloSections` for why showing these matters.
    public static func soloSections(connections: [Connection],
                                   now: Date = Date()) async -> [Leaderboard.Section] {
        let svc = SharingService.shared
        guard svc.isSignedIn, Preferences.shareStatsWithFriends,
              let me = svc.currentSession?.userID else { return [] }
        var profiles = Dictionary(uniqueKeysWithValues:
            connections.filter { $0.kind == .friend }.map { ($0.profile.id, $0.profile) })
        if let mine = svc.currentUsername {
            profiles[me] = SharedProfile(id: me, username: mine)
        }
        let periods = readPeriods(.week, for: now) + readPeriods(.month, for: now)
        let entries = (try? await svc.leaderboardEntries(userIDs: Array(profiles.keys),
                                                        periods: periods)) ?? []
        return Leaderboard.soloSections(from: entries, profiles: profiles, me: me)
    }

    /// A global board: the podium, then the caller's own bracket.
    ///
    /// Two halves because they answer different questions. The podium is
    /// aspirational and — since steps are trivially fakeable — not to be trusted
    /// as a ranking; the bracket is where someone finds people at their own
    /// level, and nobody games their way into the middle. The operator asked for
    /// both: "have a way to show top 3 or something too, else how they inspire."
    ///
    /// De-duplicated: if you're in the top 3 you appear once, on the podium.
    /// Returns nil when the caller doesn't publish this board globally — you
    /// cannot browse a global board you haven't joined, which is what keeps it
    /// symmetric rather than a place to watch strangers from.
    public static func globalBoard(_ key: String,
                                  now: Date = Date()) async -> GlobalBoard? {
        let svc = SharingService.shared
        guard svc.isSignedIn, Preferences.shareStatsWithFriends,
              Preferences.boardIsGlobal(key),
              let me = svc.currentSession?.userID else { return nil }

        let board = LeaderboardBoard.from(key: key)
        // BOTH period keys, exactly as the friends path reads them (#1170).
        // `current` is what a row means TODAY; the older key only carries people
        // who haven't published since the last rollover.
        let periods = readPeriods(board.period, for: now)
        let current = periodStart(board.period, for: now)
        let candidates = (try? await svc.globalPodium(boardKey: key, periods: periods)) ?? []
        let podium = Array(Leaderboard.currentPerUser(candidates, preferring: current)
            .sorted { $0.value > $1.value }
            .prefix(3))
        guard !podium.isEmpty else { return nil }

        // My own value anchors the bracket. Absent it there is nothing to be
        // "near", so the podium alone is the honest answer.
        var myValue = podium.first { $0.userId == me }?.value
        if myValue == nil {
            let mine = (try? await svc.leaderboardEntries(userIDs: [me], periods: periods)) ?? []
            myValue = Leaderboard.currentPerUser(mine.filter { $0.boardKey == key },
                                                 preferring: current).first?.value
        }

        var bracket: [LeaderboardEntryDTO] = []
        if let myValue {
            let rows = (try? await svc.globalBracket(boardKey: key, periods: periods,
                                                     around: myValue)) ?? []
            let podiumIDs = Set(podium.map(\.userId))
            bracket = Leaderboard.bracket(
                Leaderboard.currentPerUser(rows, preferring: current)
                    .filter { !podiumIDs.contains($0.userId) },
                around: myValue, span: 10)
        }

        return GlobalBoard(board: board, podium: podium, bracket: bracket,
                          myValue: myValue, me: me)
    }

    /// Turning sharing off REMOVES what was published — a switch that only stops
    /// future writes leaves last month's deadlift on your friends' boards, which
    /// is not what anyone means by turning it off.
    ///
    /// THROWS, deliberately. This used to be `try?`, and the UI cleared the board
    /// unconditionally: withdrawing on a dead connection showed the off state
    /// while the rows stayed live on strangers' boards, and because
    /// `shareStatsWithFriends` was already false nothing ever retried. A consent
    /// control that reports success it didn't achieve is worse than one that
    /// fails loudly.
    public static func withdraw() async throws {
        try await SharingService.shared.deleteMyLeaderboardEntries()
    }

    /// Take ONE board private, across every period.
    ///
    /// Server-side (`unpublish_board`, 0016) because the client only knows the
    /// current period key: restamping just this week left July's row globally
    /// readable forever, and its existence kept the profile-discovery gate open.
    public static func unpublish(board key: String) async throws {
        _ = try await SharingService.shared.unpublishBoard(key)
    }
}
