import Foundation

/// One person's value on one board, as the server stores it (migration 0011).
public struct LeaderboardEntryDTO: Codable, Sendable, Hashable {
    public let userId: String
    public let boardKey: String
    public let periodStart: String
    public let value: Double
    public let unit: String
    /// "friends" or "global" (migration 0012). Decodes as "friends" when a row
    /// predates the column, matching the server default — an unknown row must
    /// never be treated as public.
    public var visibility: String
    /// When this value was last published. Decoded so the UI can say how old a
    /// number is instead of implying every row is current: nothing publishes
    /// while someone's app isn't running, so a board legitimately mixes a
    /// Monday value with a Thursday one.
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case boardKey = "board_key"
        case periodStart = "period_start"
        case updatedAt = "updated_at"
        case value, unit, visibility
    }

    public init(userId: String, boardKey: String, periodStart: String,
                value: Double, unit: String, visibility: String = "friends",
                updatedAt: String? = nil) {
        self.userId = userId
        self.boardKey = boardKey
        self.periodStart = periodStart
        self.value = value
        self.unit = unit
        self.visibility = visibility
        self.updatedAt = updatedAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        boardKey = try c.decode(String.self, forKey: .boardKey)
        periodStart = try c.decode(String.self, forKey: .periodStart)
        value = try c.decode(Double.self, forKey: .value)
        unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
        visibility = (try? c.decode(String.self, forKey: .visibility)) ?? "friends"
        updatedAt = try? c.decode(String.self, forKey: .updatedAt)
    }

    /// How stale this value is, in whole days, or nil when unknown.
    public func ageInDays(now: Date = Date()) -> Int? {
        guard let updatedAt, let when = SeenMarks.parse(updatedAt) else { return nil }
        return Calendar.current.dateComponents([.day], from: when, to: now).day
    }
}

/// A board is DATA, not a case in an enum.
///
/// The operator's direction (2026-07-30): "sometimes auto render based on what
/// you are… doing. Figure out how it can be multiple of this. Like steps,
/// deadlift highest weight etc." So boards are discovered from the entries that
/// exist rather than declared in code — `lift:deadlift` appears because you and
/// a friend both deadlift, and disappears when you stop.
///
/// The key is namespaced (`lift:deadlift`) so a new FAMILY of boards can be
/// added without colliding with an old one, and so this type can present a key
/// it has never seen.
public struct LeaderboardBoard: Sendable, Hashable, Identifiable {
    public enum Period: String, Sendable {
        case week, month
        /// A running total that isn't bounded by the period at all — a streak.
        /// Stored under the WEEK key so it refreshes and upserts on the same
        /// cadence as everything else, but it does not MEAN "this week".
        case running

        /// What a board covers, in words, for the line under its title.
        public var label: String {
            switch self {
            case .week: return "last 7 days"
            case .month: return "last 30 days"
            case .running: return "right now"
            }
        }
    }

    public let key: String
    public let title: String
    public let unit: String
    public let period: Period
    /// Fixed boards (steps, calories, workouts) sort above discovered lifts, so
    /// the screen doesn't reorder itself as friends' training changes.
    public let isCore: Bool

    public var id: String { key }

    /// Present any key, including one this build has never heard of — a newer
    /// client can publish `lift:zercher_squat` and older ones must render it
    /// rather than dropping the row on the floor.
    public static func from(key: String, unit: String = "") -> LeaderboardBoard {
        switch key {
        case "steps":
            return .init(key: key, title: "Steps", unit: "", period: .week, isCore: true)
        case "calories":
            return .init(key: key, title: "Calories burned", unit: "kcal",
                        period: .week, isCore: true)
        case "workouts":
            return .init(key: key, title: "Workouts", unit: "", period: .week, isCore: true)
        case "food_streak":
            return .init(key: key, title: "Food logging streak", unit: "days",
                        period: .running, isCore: true)
        default:
            if key.hasPrefix("lift:") {
                let slug = String(key.dropFirst("lift:".count))
                return .init(key: key, title: prettify(slug), unit: unit.isEmpty ? "lbs" : unit,
                            period: .month, isCore: false)
            }
            return .init(key: key, title: prettify(key), unit: unit,
                        period: .week, isCore: false)
        }
    }

    /// `bench_press` → `Bench Press`. Deliberately not a lookup against the
    /// exercise catalog: the slug came from another person's device, which may
    /// know exercises this one doesn't.
    static func prettify(_ slug: String) -> String {
        slug.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// Exercise name → board key. Lossy on purpose (case, punctuation and
    /// spacing all collapse) so "Bench Press", "bench press" and "Bench-Press"
    /// are ONE board rather than three near-empty ones.
    public static func liftKey(for exercise: String) -> String? {
        let slug = exercise.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "_")
        guard slug.count >= 2, slug.count <= 40 else { return nil }
        return "lift:\(slug)"
    }
}

/// Ranking, and deciding which boards are worth showing at all.
public enum Leaderboard {

    /// A row on a board.
    public struct Row: Sendable, Equatable, Identifiable {
        public let rank: Int
        public let profile: SharedProfile
        public let value: Double
        /// True for the signed-in user, so the UI can anchor on it rather than
        /// making someone hunt for themselves.
        public let isMe: Bool

        public var id: String { profile.id }
    }

    /// A board plus its ranked rows.
    public struct Section: Sendable, Identifiable {
        public let board: LeaderboardBoard
        public let rows: [Row]
        public var id: String { board.key }
        public var participants: Int { rows.count }
    }

    /// **The minimum that makes a board a board.**
    ///
    /// Two people. One person "ranked #1 of 1" is a joke at their own expense,
    /// and it's also how a screen fills with dozens of solo boards for every
    /// exercise someone has ever logged.
    public static let minimumParticipants = 2

    /// Turn raw entries into the boards actually worth rendering.
    ///
    /// Auto-discovery lives here, in one pure function, so "which boards exist"
    /// is a Tier-0 assertion rather than something to squint at on a device. No
    /// extra requests: the boards come from rows already fetched.
    public static func sections(from entries: [LeaderboardEntryDTO],
                              profiles: [String: SharedProfile],
                              me: String?,
                              minimum: Int = minimumParticipants) -> [Section] {
        var byBoard: [String: [LeaderboardEntryDTO]] = [:]
        for entry in entries where profiles[entry.userId] != nil {
            byBoard[entry.boardKey, default: []].append(entry)
        }

        var sections: [Section] = []
        for (key, group) in byBoard {
            // One row per person per board, keeping the MOST RECENT — not the
            // biggest. Now that two period keys are fetched (see
            // LeaderboardService.sections), max-value would pin someone to a
            // good week forever; recency is what "their current number" means.
            var best: [String: LeaderboardEntryDTO] = [:]
            for entry in group {
                guard let existing = best[entry.userId] else { best[entry.userId] = entry; continue }
                let newer = (entry.updatedAt ?? entry.periodStart)
                    > (existing.updatedAt ?? existing.periodStart)
                if newer { best[entry.userId] = entry }
            }
            guard best.count >= minimum else { continue }

            let board = LeaderboardBoard.from(key: key, unit: group.first?.unit ?? "")
            let rows = rank(best.values.map { ($0.userId, $0.value) },
                           profiles: profiles, me: me)
            guard !rows.isEmpty else { continue }
            sections.append(Section(board: board, rows: rows))
        }

        // Core boards first in a fixed order, then discovered lifts by
        // participation (the ones your group actually shares), then title so the
        // order is stable between refreshes.
        let coreOrder = ["food_streak", "steps", "calories", "workouts"]
        return sections.sorted { a, b in
            let ai = coreOrder.firstIndex(of: a.board.key)
            let bi = coreOrder.firstIndex(of: b.board.key)
            switch (ai, bi) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default:
                if a.participants != b.participants { return a.participants > b.participants }
                return a.board.title < b.board.title
            }
        }
    }

    /// Rank `values` highest-first.
    ///
    /// Equal values SHARE a rank (two people on 40,000 steps are both 2nd, and
    /// the next row is 4th) — breaking a genuine tie tells one of them they lost
    /// when they didn't. Ties order by username so the list doesn't reshuffle
    /// between refreshes. Zero drops you off the board rather than parking you at
    /// the bottom: a visible 0 next to your name during a bad week is the most
    /// discouraging thing the screen could show.
    public static func rank(_ values: [(userID: String, value: Double)],
                           profiles: [String: SharedProfile],
                           me: String?) -> [Row] {
        let scored = values
            .compactMap { pair -> (profile: SharedProfile, value: Double)? in
                guard pair.value > 0, let profile = profiles[pair.userID] else { return nil }
                return (profile, pair.value)
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                let a: String = lhs.profile.username.lowercased()
                let b: String = rhs.profile.username.lowercased()
                return a < b
            }

        var rows: [Row] = []
        var lastValue: Double?
        var lastRank = 0
        for (index, entry) in scored.enumerated() {
            let rank = entry.value == lastValue ? lastRank : index + 1
            rows.append(Row(rank: rank, profile: entry.profile, value: entry.value,
                            isMe: entry.profile.id == me))
            lastValue = entry.value
            lastRank = rank
        }
        return rows
    }

    /// Boards where the user is publishing but NOBODY ELSE is yet.
    ///
    /// The cold-start problem I built and the operator hit within a day: an
    /// opt-in board that needs two participants can never bootstrap. You turn it
    /// on, you are the only publisher, the ≥2 rule hides every board — including
    /// your own numbers — so the screen says "nothing shared yet" to someone who
    /// just shared something, and there is no reason to leave it on.
    ///
    /// So these render, clearly labelled as waiting rather than as a ranking.
    /// "#1 of 1" is still never shown; your value is, because seeing it is what
    /// tells you the thing works and is worth nudging a friend about.
    public static func soloSections(from entries: [LeaderboardEntryDTO],
                                   profiles: [String: SharedProfile],
                                   me: String?) -> [Section] {
        let all = sections(from: entries, profiles: profiles, me: me, minimum: 1)
        // Only the ones that DIDN'T qualify as real boards, and only mine.
        let real = Set(sections(from: entries, profiles: profiles, me: me).map(\.board.key))
        return all.filter { !real.contains($0.board.key) && $0.rows.contains(where: \.isMe) }
    }

    /// Where the user sits on one board, phrased without naming anyone else —
    /// the line that can go on Today, where a full ranking is too much.
    ///
    /// Returns nil when the user isn't on the board; "you are nowhere" is not a
    /// message worth putting on someone's home screen.
    public static func standing(_ section: Section) -> String? {
        guard let mine = section.rows.first(where: \.isMe) else { return nil }
        let what = section.board.title.lowercased()
        guard section.rows.count > 1 else {
            return "You're the only one sharing \(what) so far"
        }
        if mine.rank == 1 { return "You're leading on \(what) \(section.board.period.label)" }
        return "#\(mine.rank) of \(section.rows.count) on \(what) \(section.board.period.label)"
    }

    /// Format a value for display — thousands separators for counts, one decimal
    /// dropped for weights, and the unit only where it isn't obvious.
    public static func formatted(_ value: Double, board: LeaderboardBoard) -> String {
        let rounded = Int(value.rounded())
        guard !board.unit.isEmpty else { return rounded.formatted(.number) }
        return "\(rounded.formatted(.number)) \(board.unit)"
    }
}
