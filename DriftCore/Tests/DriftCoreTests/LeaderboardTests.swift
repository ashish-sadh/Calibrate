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
            from: [entry("me", "lift:deadlift", 405, unit: "lbs"),
                   entry("ana", "lift:deadlift", 365, unit: "lbs")],
            profiles: people("me", "ana"), me: "me")
        #expect(sections.map(\.board.key) == ["lift:deadlift"])
        #expect(sections[0].board.title == "Deadlift")
        #expect(sections[0].board.period == .month)
    }

    /// A board of one is a joke at that person's expense — and it's also how the
    /// screen fills with a board per exercise anyone ever logged.
    @Test func aBoardOfOneIsNotABoard() {
        let sections = Leaderboard.sections(
            from: [entry("me", "lift:zercher_squat", 185, unit: "lbs")],
            profiles: people("me", "ana"), me: "me")
        #expect(sections.isEmpty)
    }

    /// Different lifts don't merge into one board just because both exist.
    @Test func lifts_nobodyShares_produceNoBoards() {
        let sections = Leaderboard.sections(
            from: [entry("me", "lift:deadlift", 405), entry("ana", "lift:bench_press", 225)],
            profiles: people("me", "ana"), me: "me")
        #expect(sections.isEmpty)
    }

    /// Core boards sort above discovered lifts, in a fixed order, so the screen
    /// doesn't reorder itself as friends' training changes week to week.
    @Test func coreBoardsComeFirstInAFixedOrder() {
        let entries = [
            entry("me", "lift:squat", 300), entry("ana", "lift:squat", 280),
            entry("me", "workouts", 4), entry("ana", "workouts", 3),
            entry("me", "steps", 50_000), entry("ana", "steps", 61_000),
            entry("me", "calories", 3_000), entry("ana", "calories", 2_500),
        ]
        let keys = Leaderboard.sections(from: entries, profiles: people("me", "ana"),
                                       me: "me").map(\.board.key)
        #expect(keys == ["steps", "calories", "workouts", "lift:squat"])
    }

    /// Among discovered lifts, the ones more of the group shares rank higher —
    /// that's what makes the top of the list the group's common ground.
    @Test func moreWidelySharedLiftsSortFirst() {
        let entries = [
            entry("me", "lift:squat", 300), entry("ana", "lift:squat", 280),
            entry("me", "lift:bench_press", 225), entry("ana", "lift:bench_press", 205),
            entry("bo", "lift:bench_press", 245),
        ]
        let keys = Leaderboard.sections(from: entries, profiles: people("me", "ana", "bo"),
                                       me: "me").map(\.board.key)
        #expect(keys == ["lift:bench_press", "lift:squat"])
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
        #expect(line == "#3 of 3 on steps this week")
        #expect(line?.contains("ana") == false)
    }

    @Test func standingUsesTheBoardsOwnPeriod() {
        let sections = Leaderboard.sections(
            from: [entry("ana", "lift:deadlift", 300), entry("me", "lift:deadlift", 405)],
            profiles: people("ana", "me"), me: "me")
        #expect(Leaderboard.standing(sections[0]) == "You're leading on deadlift last 30 days")
    }

    /// "You are nowhere" is not a message worth putting on a home screen.
    @Test func noStandingWhenImNotOnTheBoard() {
        let sections = Leaderboard.sections(
            from: [entry("ana", "steps", 10_000), entry("bo", "steps", 20_000)],
            profiles: people("ana", "bo", "me"), me: "me")
        #expect(Leaderboard.standing(sections[0]) == nil)
    }

    // MARK: - Keys and titles

    /// One board per lift, not three for the same one. This is what stops
    /// "Bench Press", "bench press" and "Bench-Press" fragmenting a group.
    @Test func liftKeysCollapseCaseAndPunctuation() {
        let expected = "lift:bench_press"
        #expect(LeaderboardBoard.liftKey(for: "Bench Press") == expected)
        #expect(LeaderboardBoard.liftKey(for: "bench press") == expected)
        #expect(LeaderboardBoard.liftKey(for: "Bench-Press") == expected)
        #expect(LeaderboardBoard.liftKey(for: "  BENCH   PRESS  ") == expected)
    }

    @Test func liftKeysRejectNonsense() {
        #expect(LeaderboardBoard.liftKey(for: "") == nil)
        #expect(LeaderboardBoard.liftKey(for: "!") == nil)
        #expect(LeaderboardBoard.liftKey(for: String(repeating: "a", count: 60)) == nil)
    }

    /// A newer client can publish a board this build has never heard of. Dropping
    /// the row would make the two versions disagree about what exists.
    @Test func unknownBoardKeysStillRender() {
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

    /// The publish cap is what keeps rows-per-user bounded: without it someone
    /// with 300 exercises writes 300 rows a month and the friend fan-in is
    /// 150 × 300.
    @Test func liftBoardsPerPersonAreCapped() {
        #expect(LeaderboardPublisher.maxLiftBoards <= 10)
        #expect(LeaderboardPublisher.maxLiftBoards >= 3, "too few and no board finds a pair")
    }
}
