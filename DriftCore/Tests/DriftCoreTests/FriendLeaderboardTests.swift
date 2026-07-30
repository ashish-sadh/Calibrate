import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for the friends board's ranking rules.
///
/// A leaderboard is the one social surface that can make someone feel worse
/// for using the app, so the edges — ties, zeroes, being alone on the board —
/// are the tests that matter, not the happy path.
struct FriendLeaderboardTests {

    private func stats(_ name: String, steps: Int = 0, calories: Int = 0,
                       logged: Int = 0, imported: Int = 0) -> FriendStats {
        FriendStats(
            profile: SharedProfile(id: name, username: name, displayName: nil, avatarUrl: nil),
            weekStart: "2026-07-26", steps: steps, caloriesBurned: calories,
            workoutsLogged: logged, workoutsImported: imported)
    }

    @Test func ranksHighestFirst() {
        let rows = FriendLeaderboard.rank(
            [stats("ana", steps: 30_000), stats("bo", steps: 52_000), stats("cy", steps: 41_000)],
            by: .steps, me: nil)
        #expect(rows.map(\.stats.profile.username) == ["bo", "cy", "ana"])
        #expect(rows.map(\.rank) == [1, 2, 3])
    }

    /// Two people on the same number are both in the same place. Breaking a
    /// genuine tie tells one of them they lost when they didn't.
    @Test func tiesShareARankAndSkipTheNext() {
        let rows = FriendLeaderboard.rank(
            [stats("ana", steps: 40_000), stats("bo", steps: 40_000), stats("cy", steps: 10_000)],
            by: .steps, me: nil)
        #expect(rows.map(\.rank) == [1, 1, 3])
        // Stable inside the tie, so the list doesn't reshuffle on refresh.
        #expect(rows.map(\.stats.profile.username) == ["ana", "bo", "cy"])
    }

    /// The failure mode this guards: a visible 0 next to your name during a bad
    /// week is the most discouraging thing the screen could show.
    @Test func peopleWithNothingToShowAreOmittedNotZeroed() {
        let rows = FriendLeaderboard.rank(
            [stats("ana", steps: 12_000), stats("resting", steps: 0)], by: .steps, me: nil)
        #expect(rows.map(\.stats.profile.username) == ["ana"])
    }

    @Test func workoutsCountLoggedAndImportedTogether() {
        let rows = FriendLeaderboard.rank(
            [stats("ana", logged: 1, imported: 4), stats("bo", logged: 3, imported: 0)],
            by: .workouts, me: nil)
        #expect(rows.map(\.value) == [5, 3])
        // But the split survives on the row, so the UI can still say which is
        // which — a watch-detected run isn't the same claim as a logged one.
        #expect(rows[0].stats.workoutsLogged == 1)
        #expect(rows[0].stats.workoutsImported == 4)
    }

    @Test func myRowIsMarked() {
        let rows = FriendLeaderboard.rank(
            [stats("ana", calories: 3_000), stats("me", calories: 5_000)],
            by: .caloriesBurned, me: "me")
        #expect(rows.first(where: \.isMe)?.stats.profile.username == "me")
        #expect(rows.filter(\.isMe).count == 1)
    }

    // MARK: - The Today line

    @Test func standingNamesNobodyElse() {
        let rows = FriendLeaderboard.rank(
            [stats("ana", steps: 60_000), stats("me", steps: 30_000), stats("cy", steps: 40_000)],
            by: .steps, me: "me")
        let line = FriendLeaderboard.standing(rows, metric: .steps)
        #expect(line == "#3 of 3 on steps this week")
        #expect(line?.contains("ana") == false)
    }

    @Test func standingCelebratesTheLead() {
        let rows = FriendLeaderboard.rank(
            [stats("ana", steps: 10_000), stats("me", steps: 90_000)], by: .steps, me: "me")
        #expect(FriendLeaderboard.standing(rows, metric: .steps) == "You're leading on steps this week")
    }

    /// Being ranked #1 of 1 is not an achievement, and shouldn't read like one.
    @Test func aloneOnTheBoardSaysSo() {
        let rows = FriendLeaderboard.rank([stats("me", steps: 20_000)], by: .steps, me: "me")
        #expect(FriendLeaderboard.standing(rows, metric: .steps)
                == "You're the only one sharing steps so far")
    }

    /// "You are nowhere" is not a message for someone's home screen.
    @Test func noStandingWhenImNotOnTheBoard() {
        let rows = FriendLeaderboard.rank(
            [stats("ana", steps: 10_000), stats("me", steps: 0)], by: .steps, me: "me")
        #expect(FriendLeaderboard.standing(rows, metric: .steps) == nil)
        #expect(FriendLeaderboard.standing([], metric: .steps) == nil)
    }
}
