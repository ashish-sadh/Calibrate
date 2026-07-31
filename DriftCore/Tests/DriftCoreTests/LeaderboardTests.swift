import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for board DISCOVERY and ranking.
///
/// A leaderboard is the one social surface that can make someone feel worse for
/// using the app, so the edges — ties, zeroes, a board of one, being absent —
/// are the tests that matter, not the happy path. Discovery is pure so "which
/// boards exist" is an assertion here rather than something to squint at on a
/// device.
struct LeaderboardTests {

    private func profile(_ name: String) -> SharedProfile {
        SharedProfile(id: name, username: name, displayName: nil, avatarUrl: nil)
    }

    private func people(_ names: String...) -> [String: SharedProfile] {
        Dictionary(uniqueKeysWithValues: names.map { ($0, profile($0)) })
    }

    private func entry(_ user: String, _ board: String, _ value: Double,
                       period: String = "2026-07-27", unit: String = "") -> LeaderboardEntryDTO {
        LeaderboardEntryDTO(userId: user, boardKey: board, periodStart: period,
                            value: value, unit: unit)
    }

    // MARK: - Discovery

    /// The headline behaviour: a board exists because two people share it, not
    /// because someone shipped it.
    @Test func aBoardAppearsWhenTwoPeopleShareIt() {
        let sections = Leaderboard.sections(
            from: [entry("me", "steps", 50_000), entry("ana", "steps", 61_000)],
            profiles: people("me", "ana"), me: "me")
        #expect(sections.map(\.board.key) == ["steps"])
        #expect(sections[0].board.title == "Steps")
        #expect(sections[0].board.period == .week)
    }

    /// A board of one is a joke at that person's expense.
    @Test func aBoardOfOneIsNotABoard() {
        let sections = Leaderboard.sections(
            from: [entry("me", "steps", 50_000)],
            profiles: people("me", "ana"), me: "me")
        #expect(sections.isEmpty)
    }

    /// FIXED SET (operator 2026-07-31): per-exercise lift rows are ignored, so a
    /// stale `lift:*` row from an older client can never fragment the board list
    /// back into per-exercise noise — even when two people share the same lift.
    @Test func liftRowsAreIgnoredEvenWhenShared() {
        let sections = Leaderboard.sections(
            from: [entry("me", "lift:deadlift", 405, unit: "lbs"),
                   entry("ana", "lift:deadlift", 365, unit: "lbs")],
            profiles: people("me", "ana"), me: "me")
        #expect(sections.isEmpty, "lift boards are no longer part of the leaderboard")
    }

    /// The four core boards render, in a fixed order, and nothing else does —
    /// even when a shared lift row is present in the same fetch.
    @Test func onlyTheFourCoreBoardsRenderInAFixedOrder() {
        let entries = [
            entry("me", "lift:squat", 300), entry("ana", "lift:squat", 280),
            entry("me", "workouts", 4), entry("ana", "workouts", 3),
            entry("me", "steps", 50_000), entry("ana", "steps", 61_000),
            entry("me", "calories", 3_000), entry("ana", "calories", 2_500),
            entry("me", "food_streak", 12), entry("ana", "food_streak", 9),
        ]
        let keys = Leaderboard.sections(from: entries, profiles: people("me", "ana"),
                                       me: "me").map(\.board.key)
        #expect(keys == ["food_streak", "steps", "calories", "workouts"])
    }

    /// Entries from someone who isn't a friend any more must not resurrect them
    /// onto a board.
    @Test func entriesFromUnknownPeopleAreDropped() {
        let sections = Leaderboard.sections(
            from: [entry("me", "steps", 40_000), entry("stranger", "steps", 90_000)],
            profiles: people("me"), me: "me")
        #expect(sections.isEmpty, "one known participant is not a board")
    }

    // MARK: - Ranking

    @Test func ranksHighestFirst() {
        let sections = Leaderboard.sections(
            from: [entry("ana", "steps", 30_000), entry("bo", "steps", 52_000),
                   entry("cy", "steps", 41_000)],
            profiles: people("ana", "bo", "cy"), me: nil)
        #expect(sections[0].rows.map(\.profile.username) == ["bo", "cy", "ana"])
        #expect(sections[0].rows.map(\.rank) == [1, 2, 3])
    }

    /// Two people on the same number are in the same place. Breaking a genuine
    /// tie tells one of them they lost when they didn't.
    @Test func tiesShareARankAndSkipTheNext() {
        let sections = Leaderboard.sections(
            from: [entry("ana", "steps", 40_000), entry("bo", "steps", 40_000),
                   entry("cy", "steps", 10_000)],
            profiles: people("ana", "bo", "cy"), me: nil)
        #expect(sections[0].rows.map(\.rank) == [1, 1, 3])
        // Stable inside the tie, so the list doesn't reshuffle on refresh.
        #expect(sections[0].rows.map(\.profile.username) == ["ana", "bo", "cy"])
    }

    /// A visible 0 next to your name during a bad week is the most discouraging
    /// thing this screen could show.
    @Test func zeroDropsYouOffTheBoardRatherThanToTheBottom() {
        let sections = Leaderboard.sections(
            from: [entry("ana", "steps", 12_000), entry("bo", "steps", 8_000),
                   entry("resting", "steps", 0)],
            profiles: people("ana", "bo", "resting"), me: "resting")
        #expect(sections[0].rows.map(\.profile.username) == ["ana", "bo"])
        #expect(sections[0].rows.allSatisfy { !$0.isMe })
    }

    @Test func myRowIsMarkedExactlyOnce() {
        let sections = Leaderboard.sections(
            from: [entry("ana", "steps", 3_000), entry("me", "steps", 5_000)],
            profiles: people("ana", "me"), me: "me")
        #expect(sections[0].rows.filter(\.isMe).count == 1)
        #expect(sections[0].rows.first(where: \.isMe)?.profile.username == "me")
    }

    // MARK: - The standing line

    @Test func standingNamesNobodyElse() {
        let sections = Leaderboard.sections(
            from: [entry("ana", "steps", 60_000), entry("me", "steps", 30_000),
                   entry("cy", "steps", 40_000)],
            profiles: people("ana", "me", "cy"), me: "me")
        let line = Leaderboard.standing(sections[0])
        #expect(line == "#3 of 3 on steps last 7 days")
        #expect(line?.contains("ana") == false)
    }

    @Test func standingUsesTheBoardsOwnPeriod() {
        // food_streak's period is `.running` ("right now"), not a week — so this
        // pins that the standing line reads the board's OWN period label.
        let sections = Leaderboard.sections(
            from: [entry("ana", "food_streak", 3), entry("me", "food_streak", 12)],
            profiles: people("ana", "me"), me: "me")
        #expect(Leaderboard.standing(sections[0]) == "You're leading on food logging streak right now")
    }

    /// "You are nowhere" is not a message worth putting on a home screen.
    @Test func noStandingWhenImNotOnTheBoard() {
        let sections = Leaderboard.sections(
            from: [entry("ana", "steps", 10_000), entry("bo", "steps", 20_000)],
            profiles: people("ana", "bo", "me"), me: "me")
        #expect(Leaderboard.standing(sections[0]) == nil)
    }

    // MARK: - Keys and titles

    /// `from(key:)` still renders a legacy `lift:*` row sanely (defensive — the
    /// read path filters these out of the board list, but a raw key must never
    /// surface unprettified if one is ever passed straight in).
    @Test func legacyLiftKeysStillRenderSanely() {
        let board = LeaderboardBoard.from(key: "lift:zercher_squat", unit: "lbs")
        #expect(board.title == "Zercher Squat")
        #expect(board.unit == "lbs")
        #expect(!board.isCore)
    }

    @Test func formattingCarriesTheUnitOnlyWhereItHelps() {
        let steps = LeaderboardBoard.from(key: "steps")
        let lift = LeaderboardBoard.from(key: "lift:deadlift", unit: "lbs")
        #expect(Leaderboard.formatted(50_000, board: steps) == 50_000.formatted(.number))
        #expect(Leaderboard.formatted(405, board: lift) == "405 lbs")
    }

    // MARK: - Which boards fetch the worldwide view (#1170)

    private func section(_ key: String) -> Leaderboard.Section {
        Leaderboard.Section(board: LeaderboardBoard.from(key: key), rows: [])
    }

    /// THE BUG. A board where you're the only publisher (in `solo`, not
    /// `sections`) must still fetch the worldwide podium when you've opened it to
    /// Everyone. Deriving the fetch set from `sections` alone required ≥2 of your
    /// own friends on that board first, so "I turned on global, show me the
    /// world" showed nothing.
    @Test func soloBoardYouOpenedGlobalStillFetchesTheWorld() {
        let keys = Leaderboard.globalCandidateKeys(
            sections: [section("steps")],          // 2+ friends here
            solo: [section("calories")],           // only you here
            isGlobal: { $0 == "calories" || $0 == "steps" })
        #expect(keys.contains("calories"), "a solo board opened global must load")
        #expect(keys.contains("steps"))
    }

    @Test func friendsOnlyBoardsAreNeverFetchedGlobally() {
        let keys = Leaderboard.globalCandidateKeys(
            sections: [section("steps")],
            solo: [section("calories")],
            isGlobal: { _ in false })              // nothing opened to Everyone
        #expect(keys.isEmpty)
    }

    @Test func aBoardInBothSectionsAndSoloIsNotDoubleCounted() {
        let keys = Leaderboard.globalCandidateKeys(
            sections: [section("steps")],
            solo: [section("steps")],
            isGlobal: { _ in true })
        #expect(keys == ["steps"])
    }
}

/// Tier-0 for the period keys, which are PRIMARY KEY components on the server.
/// Getting one wrong doesn't produce a wrong number — it produces a second row
/// for the same period, splitting one person's totals.
@MainActor
struct LeaderboardPeriodTests {

    private func day(_ s: String) -> Date { DateFormatters.dateOnly.date(from: s)! }

    @Test func weeksStartOnMonday() {
        // 2026-07-30 is a Thursday.
        #expect(LeaderboardService.periodStart(.week, for: day("2026-07-30")) == "2026-07-27")
        #expect(LeaderboardService.periodStart(.week, for: day("2026-07-27")) == "2026-07-27")
    }

    /// The edge a Sunday-first locale gets wrong, and the reason firstWeekday is
    /// pinned rather than inherited: a user in the US and one in Germany must
    /// agree on which week it is, or the same board shows two windows.
    @Test func sundayClosesTheWeekItEnds() {
        #expect(LeaderboardService.periodStart(.week, for: day("2026-08-02")) == "2026-07-27")
        #expect(LeaderboardService.periodStart(.week, for: day("2026-08-03")) == "2026-08-03")
    }

    @Test func weekKeyIsIdenticalAcrossLocalesWithDifferentFirstDays() {
        var us = Calendar(identifier: .gregorian); us.firstWeekday = 1  // Sunday
        var de = Calendar(identifier: .gregorian); de.firstWeekday = 2  // Monday
        let thursday = day("2026-07-30")
        #expect(LeaderboardService.periodStart(.week, for: thursday, calendar: us)
                == LeaderboardService.periodStart(.week, for: thursday, calendar: de))
    }

    @Test func monthsStartOnTheFirst() {
        #expect(LeaderboardService.periodStart(.month, for: day("2026-07-30")) == "2026-07-01")
        #expect(LeaderboardService.periodStart(.month, for: day("2026-07-01")) == "2026-07-01")
    }

    /// The fixed set is exactly the four ambient boards — rows-per-user is
    /// bounded by construction now (no per-exercise fan-out to cap).
    @Test func theBoardSetIsFixedToFourAmbientBoards() {
        #expect(Leaderboard.boardKeys == ["steps", "calories", "workouts", "food_streak"])
    }
}

/// Tier-0 for the two audience decisions that can leak data if wrong.
struct AudienceTests {

    /// The switch combination that per-recipient sharing could express and a
    /// purely derived audience could not — the reason 0014 stores it.
    @Test func coachOnlyIsRepresentable() {
        #expect(WorkoutAudience.from(friends: false, coaches: true) == .coaches)
    }

    /// Each of the four switch combinations maps to its OWN audience.
    ///
    /// This test previously asserted `from(friends: true, coaches: false) == .all`
    /// — i.e. it locked in the bug: the coach switch did nothing while the
    /// completion sheet claimed the session was friends-only. A test that
    /// encodes the defect is worse than no test, because it defends it.
    @Test func everySwitchCombinationHasItsOwnAudience() {
        #expect(WorkoutAudience.from(friends: true, coaches: true) == .all)
        #expect(WorkoutAudience.from(friends: true, coaches: false) == .friends)
        #expect(WorkoutAudience.from(friends: false, coaches: true) == .coaches)
        #expect(WorkoutAudience.from(friends: false, coaches: false) == .private)
        // Four distinct outcomes — nothing collapses.
        let all = Set([WorkoutAudience.from(friends: true, coaches: true),
                       .from(friends: true, coaches: false),
                       .from(friends: false, coaches: true),
                       .from(friends: false, coaches: false)])
        #expect(all.count == 4)
    }

    /// Both switches off must publish NOTHING — this is the "I'm just testing"
    /// case, and a row written here is a real privacy failure.
    @Test func bothOffIsPrivate() {
        #expect(WorkoutAudience.from(friends: false, coaches: false) == .private)
    }

    /// A row that predates the visibility column, or comes from a client that
    /// doesn't set it, must decode as FRIENDS. Defaulting to global would widen
    /// exposure through silence.
    @Test func entriesWithoutVisibilityDecodeAsFriends() throws {
        let json = """
        {"user_id":"u1","board_key":"steps","period_start":"2026-07-27","value":40000}
        """
        let entry = try JSONDecoder().decode(LeaderboardEntryDTO.self, from: Data(json.utf8))
        #expect(entry.visibility == "friends")
        #expect(entry.unit == "")
    }

    @Test func explicitGlobalSurvivesDecoding() throws {
        let json = """
        {"user_id":"u1","board_key":"steps","period_start":"2026-07-27","value":40000,
         "unit":"","visibility":"global"}
        """
        let entry = try JSONDecoder().decode(LeaderboardEntryDTO.self, from: Data(json.utf8))
        #expect(entry.visibility == "global")
    }
}

/// Tier-0 for what a HUMAN coach may read as prose.
///
/// The load-bearing assertion is a negative one: AI-chat notes must never appear.
/// They're things someone told a machine in passing — injuries, pain levels —
/// and nobody experiences that as telling their trainer (operator 2026-07-30).
@MainActor
struct CoachFacingSummaryTests {

    private func notesWithChatter() -> CoachNotes {
        var notes = CoachNotes()
        notes.notes = [
            .init(date: "2026-07-01", text: "left shoulder impingement, sharp at 7/10", kind: .moment),
            .init(date: "2026-07-02", text: "drinking most nights this month", kind: .moment),
            .init(date: "2026-07-03", text: "probably overreaching", kind: .observation),
        ]
        return notes
    }

    @Test func aiChatNotesNeverReachTheCoach() {
        let summary = SharingService.coachFacingSummary(notesWithChatter())
        #expect(!summary.contains("impingement"))
        #expect(!summary.contains("drinking"))
        #expect(!summary.contains("overreaching"))
    }

    @Test func theSharedGoalDoesReachTheCoach() {
        Preferences.sharedGoalStatement = "Add 20 lbs to my deadlift by December"
        Preferences.sharedGoalDate = "2026-07-30"
        defer { Preferences.sharedGoalStatement = nil; Preferences.sharedGoalDate = nil }
        let summary = SharingService.coachFacingSummary(notesWithChatter())
        #expect(summary.contains("Add 20 lbs to my deadlift"))
        // Dated, so a coach can tell a stale goal from a current one.
        #expect(summary.contains("2026-07-30"))
        // And STILL no chatter.
        #expect(!summary.contains("impingement"))
    }

    @Test func noGoalMeansNothingIsInvented() {
        Preferences.sharedGoalStatement = nil
        #expect(!SharingService.coachFacingSummary(CoachNotes()).contains("Goal"))
    }
}

/// Tier-0 for the COLD START — a board nobody else has joined yet.
///
/// The operator hit this on day one: "my leaderboard looks empty even though I
/// have 12 friends." Publishing was working (11 entries); he was simply the only
/// publisher, and the ≥2 rule hid every board including his own.
struct SoloBoardTests {

    private func profile(_ n: String) -> SharedProfile {
        SharedProfile(id: n, username: n, displayName: nil, avatarUrl: nil)
    }
    private func entry(_ u: String, _ b: String, _ v: Double) -> LeaderboardEntryDTO {
        LeaderboardEntryDTO(userId: u, boardKey: b, periodStart: "2026-07-27", value: v, unit: "")
    }

    /// Alone on a board: it is NOT a real board, but my value is still surfaced.
    @Test func myOwnNumbersSurfaceWhenNobodyElseHasJoined() {
        let people = ["me": profile("me"), "ana": profile("ana")]
        let entries = [entry("me", "steps", 47_000)]
        #expect(Leaderboard.sections(from: entries, profiles: people, me: "me").isEmpty,
                "one participant is still not a ranking")
        let solo = Leaderboard.soloSections(from: entries, profiles: people, me: "me")
        #expect(solo.map(\.board.key) == ["steps"])
        #expect(solo[0].rows.first?.value == 47_000)
    }

    /// Once a friend joins, it becomes a REAL board and must stop being listed
    /// as waiting — otherwise it renders twice.
    @Test func aBoardStopsBeingSoloOnceAFriendJoins() {
        let people = ["me": profile("me"), "ana": profile("ana")]
        let entries = [entry("me", "steps", 47_000), entry("ana", "steps", 51_000)]
        #expect(Leaderboard.sections(from: entries, profiles: people, me: "me").count == 1)
        #expect(Leaderboard.soloSections(from: entries, profiles: people, me: "me").isEmpty)
    }

    /// A friend publishing alone is NOT my waiting board — I'd be showing
    /// someone else's number under "your numbers".
    @Test func aFriendsSoloBoardIsNotMine() {
        let people = ["me": profile("me"), "ana": profile("ana")]
        let entries = [entry("ana", "lift:squat", 300)]
        #expect(Leaderboard.soloSections(from: entries, profiles: people, me: "me").isEmpty)
    }

    /// Mixed: one real board, one waiting. Each appears exactly once, and they
    /// never overlap.
    ///
    /// Uses a CORE board for the waiting case: a solo lift is deliberately not a
    /// waiting board any more (it was twelve cards of noise), so asserting one
    /// here would be asserting the behaviour we removed. See `BoardNoiseTests`.
    @Test func realAndWaitingBoardsDoNotOverlap() {
        let people = ["me": profile("me"), "ana": profile("ana")]
        let entries = [entry("me", "steps", 47_000), entry("ana", "steps", 51_000),
                       entry("me", "food_streak", 12)]
        let real = Leaderboard.sections(from: entries, profiles: people, me: "me").map(\.board.key)
        let solo = Leaderboard.soloSections(from: entries, profiles: people, me: "me").map(\.board.key)
        #expect(real == ["steps"])
        #expect(solo == ["food_streak"])
        #expect(Set(real).intersection(Set(solo)).isEmpty)
    }
}

/// Tier-0 for the food-logging streak — the board most people will actually
/// appear on, so its edges get read by everyone.
struct FoodLoggingStreakTests {

    private func days(_ offsets: [Int], from today: Date) -> Set<String> {
        let cal = Calendar.current
        return Set(offsets.compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
                          .map { DateFormatters.dateOnly.string(from: $0) })
    }

    private let today = DateFormatters.dateOnly.date(from: "2026-07-30")!

    @Test func countsConsecutiveDaysEndingToday() {
        #expect(FoodLoggingStreak.current(loggedDays: days([0, 1, 2, 3], from: today),
                                          today: today) == 4)
    }

    /// A streak that resets at midnight punishes people for sleeping — someone
    /// who logs dinner nightly must not read zero every morning.
    @Test func yesterdayKeepsTheStreakAlive() {
        #expect(FoodLoggingStreak.current(loggedDays: days([1, 2, 3], from: today),
                                          today: today) == 3)
    }

    /// Broken is broken. Inflating it would make the number meaningless to
    /// compare against a friend's.
    @Test func aGapEndsIt() {
        #expect(FoodLoggingStreak.current(loggedDays: days([2, 3, 4], from: today),
                                          today: today) == 0,
                "last log was two days ago — the streak is over")
        // A gap in the MIDDLE stops the count there rather than counting across.
        #expect(FoodLoggingStreak.current(loggedDays: days([0, 1, 3, 4], from: today),
                                          today: today) == 2)
    }

    @Test func noLogsIsZeroNotACrash() {
        #expect(FoodLoggingStreak.current(loggedDays: [], today: today) == 0)
    }

    /// The long streaks the operator expects to see ("for some it will be 90-100
    /// days") must count correctly, not cap early.
    @Test func longStreaksCountFully() {
        #expect(FoodLoggingStreak.current(loggedDays: days(Array(0..<97), from: today),
                                          today: today) == 97)
    }

    /// A streak is not a per-period total, so it must not read "this week".
    @Test func theStreakBoardLabelsItselfHonestly() {
        let board = LeaderboardBoard.from(key: "food_streak")
        #expect(board.title == "Food logging streak")
        #expect(board.unit == "days")
        #expect(board.period.label == "right now")
    }
}

/// Tier-0 for the rollover that used to empty every board.
///
/// Operator: "it should be a sliding window right? Why empty every Monday?"
/// Two fixes, both asserted here: the VALUE is a trailing window (so it never
/// resets to near-zero), and the READ spans the current and previous period key
/// (so a friend who hasn't opened the app since the roll doesn't vanish).
@MainActor
struct PeriodRolloverTests {

    private func profile(_ n: String) -> SharedProfile {
        SharedProfile(id: n, username: n, displayName: nil, avatarUrl: nil)
    }
    private func entry(_ u: String, _ period: String, _ v: Double,
                       updated: String) -> LeaderboardEntryDTO {
        LeaderboardEntryDTO(userId: u, boardKey: "steps", periodStart: period,
                            value: v, unit: "", visibility: "friends", updatedAt: updated)
    }

    private let monday = DateFormatters.dateOnly.date(from: "2026-07-27")!

    @Test func readSpansTheCurrentAndPreviousPeriod() {
        #expect(LeaderboardService.readPeriods(.week, for: monday) == ["2026-07-27", "2026-07-20"])
        #expect(LeaderboardService.readPeriods(.month, for: monday) == ["2026-07-01", "2026-06-01"])
    }

    /// THE BUG: I publish on the new Monday, my friend last published Sunday.
    /// Under one-period reads the board had a single participant and vanished.
    @Test func aFriendWhoHasNotOpenedTheAppSinceTheRollStillCounts() {
        let people = ["me": profile("me"), "ana": profile("ana")]
        let entries = [
            entry("me", "2026-07-27", 12_000, updated: "2026-07-27T09:00:00Z"),
            entry("ana", "2026-07-20", 61_000, updated: "2026-07-26T20:00:00Z"),
        ]
        let sections = Leaderboard.sections(from: entries, profiles: people, me: "me")
        #expect(sections.count == 1, "the board must survive the rollover")
        #expect(sections[0].rows.count == 2)
    }

    /// Two rows for one person across periods: the NEWER wins, not the bigger.
    /// Max-value would pin someone to their best week forever.
    @Test func recencyBeatsMagnitudeAcrossPeriods() {
        let people = ["me": profile("me"), "ana": profile("ana")]
        let entries = [
            entry("ana", "2026-07-20", 90_000, updated: "2026-07-24T10:00:00Z"),
            entry("ana", "2026-07-27", 15_000, updated: "2026-07-28T10:00:00Z"),
            entry("me", "2026-07-27", 20_000, updated: "2026-07-28T10:00:00Z"),
        ]
        let rows = Leaderboard.sections(from: entries, profiles: people, me: "me")[0].rows
        #expect(rows.count == 2, "one row per person, not one per period")
        #expect(rows.first { !$0.isMe }?.value == 15_000, "their CURRENT number, not their best")
    }

    @Test func weeklyBoardsSayLastSevenDays() {
        #expect(LeaderboardBoard.from(key: "steps").period.label == "last 7 days")
    }
}

/// Tier-0 for noise control — the operator's "very cluttered... not every
/// exercise... think of creative ways of reducing noise in exercises".
struct BoardNoiseTests {

    private func profile(_ n: String) -> SharedProfile {
        SharedProfile(id: n, username: n, displayName: nil, avatarUrl: nil)
    }
    private func entry(_ u: String, _ b: String, _ v: Double) -> LeaderboardEntryDTO {
        LeaderboardEntryDTO(userId: u, boardKey: b, periodStart: "2026-07-27", value: v, unit: "")
    }

    /// The screenshot: twelve solo boards, "Wrist Extension" among them. While
    /// nobody else has joined, only the four everyone-has boards may take a card.
    @Test func waitingBoardsAreCoreOnly() {
        let people = ["me": profile("me"), "ana": profile("ana")]
        let mine = [entry("me", "steps", 59_000), entry("me", "food_streak", 3),
                    entry("me", "calories", 693), entry("me", "workouts", 5),
                    entry("me", "lift:wrist_extension", 30),
                    entry("me", "lift:calf_raises", 115),
                    entry("me", "lift:leg_extension", 70)]
        let solo = Leaderboard.soloSections(from: mine, profiles: people, me: "me")
        let keys = Set(solo.map(\.board.key))
        let expected: Set<String> = ["food_streak", "steps", "calories", "workouts"]
        #expect(keys == expected)
        #expect(solo.allSatisfy { $0.board.isCore })
    }

    /// A big group full of shared lifts still yields ONLY the four core boards —
    /// the fixed set can't be flooded back into per-exercise boards, however many
    /// people share a lift.
    @Test func onlyCoreBoardsRenderEvenInABigGroupOfSharedLifts() {
        var entries: [LeaderboardEntryDTO] = []
        var people: [String: SharedProfile] = [:]
        for name in ["me", "ana", "bo"] { people[name] = profile(name) }
        for core in ["steps", "calories", "workouts", "food_streak"] {
            entries += [entry("me", core, 10), entry("ana", core, 20)]
        }
        for lift in ["squat", "bench", "row", "curl", "dip", "ohp"] {
            let key = "lift:" + lift
            entries += [entry("me", key, 100), entry("ana", key, 90)]
        }
        let keys = Set(Leaderboard.sections(from: entries, profiles: people, me: "me").map(\.board.key))
        #expect(keys == ["steps", "calories", "workouts", "food_streak"])
    }
}

/// Tier-0 for the visibility default, inverted BACK to opt-in 2026-07-31 (#1171).
///
/// Boards are FRIENDS-ONLY by default. This flag has flipped twice; these
/// assertions are the record of which way it points, so a future change has to
/// argue with a failing test rather than a comment.
@MainActor
struct BoardVisibilityDefaultTests {

    @Test func boardsAreFriendsOnlyUntilOpenedUp() {
        Preferences.globalBoardKeys = []
        #expect(!Preferences.boardIsGlobal("steps"))
        #expect(!Preferences.boardIsGlobal("lift:deadlift"))
        // A board this build has never heard of is friends-only too — the
        // default must not depend on knowing the key.
        #expect(!Preferences.boardIsGlobal("lift:zercher_squat"))
    }

    @Test func openingOneUpDoesNotAffectOthers() {
        Preferences.globalBoardKeys = ["lift:deadlift"]
        defer { Preferences.globalBoardKeys = [] }
        #expect(Preferences.boardIsGlobal("lift:deadlift"))
        #expect(!Preferences.boardIsGlobal("steps"), "per board, not all-or-nothing")
    }

    /// An existing install that never touched the control reads as friends-only
    /// even though it has the OLD opt-out key on disk. That key is left in place
    /// deliberately (never destroy what a user set) — it must simply go unread.
    @Test func staleOptOutKeyDoesNotLeakBoardsGlobal() {
        Preferences.globalBoardKeys = []
        DriftPlatform.keyValueStore.set(["lift:deadlift"],
                                        forKey: "drift_friends_only_board_keys")
        defer { DriftPlatform.keyValueStore.removeObject(forKey: "drift_friends_only_board_keys") }
        #expect(!Preferences.boardIsGlobal("steps"),
                "a board absent from the old opt-out set must not inherit global")
        #expect(!Preferences.boardIsGlobal("lift:deadlift"))
    }

    /// THE SAFEGUARD. Nothing is published at all until the master switch is on.
    /// With the per-board default now also friends-only, this is the second of
    /// two gates rather than the only one — but it still has to hold.
    @Test func nothingPublishesUntilTheMasterSwitchIsOn() {
        DriftPlatform.keyValueStore.removeObject(forKey: "drift_share_stats_friends")
        #expect(!Preferences.shareStatsWithFriends,
                "leaderboards must stay opt-in")
    }
}

/// Regression for the streak that stopped at 27 days.
///
/// A real user had logged since April; the board showed 27. `mine()` parsed
/// `loggedAt` through two formatters and `compactMap`ped away anything that
/// matched neither — so history older than the current timestamp format silently
/// disappeared, and the streak ended exactly where parsing did.
struct StreakHistoryDepthTests {

    private let today = DateFormatters.dateOnly.date(from: "2026-07-30")!

    private func days(back: Int) -> Set<String> {
        let cal = Calendar.current
        return Set((0..<back).compactMap { cal.date(byAdding: .day, value: -$0, to: today) }
                             .map { DateFormatters.dateOnly.string(from: $0) })
    }

    /// April → July is ~120 days. The count must not stop early.
    @Test func aStreakSinceAprilCountsEveryDay() {
        #expect(FoodLoggingStreak.current(loggedDays: days(back: 120), today: today) == 120)
    }

    /// And well past it — the only cap is the 10-year runaway guard.
    @Test func aVeryLongStreakIsNotTruncated() {
        #expect(FoodLoggingStreak.current(loggedDays: days(back: 400), today: today) == 400)
    }
}
