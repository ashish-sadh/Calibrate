import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for WHERE a finished workout goes.
///
/// Finishing a workout now shares it automatically, so the routing rule is the
/// thing standing between the operator and an unwanted share: "sometimes I
/// might be testing and only want to share with friends but not trainer."
struct WorkoutBroadcastTests {

    private func profile(_ id: String) -> SharedProfile {
        SharedProfile(id: id, username: id, displayName: nil, avatarUrl: nil)
    }

    private var everyone: [Connection] {
        [Connection(profile: profile("friend-a"), kind: .friend),
         Connection(profile: profile("friend-b"), kind: .friend),
         Connection(profile: profile("coach"), kind: .coach),
         Connection(profile: profile("client"), kind: .client)]
    }

    @Test func bothSwitchesOnReachesFriendsAndCoachesButNeverClients() {
        let ids = WorkoutBroadcast.recipients(from: everyone, toFriends: true, toCoaches: true)
            .map(\.profile.id)
        #expect(ids == ["friend-a", "friend-b", "coach"])
    }

    /// The exact case the switches exist for.
    @Test func friendsOnlyExcludesTheCoach() {
        let ids = WorkoutBroadcast.recipients(from: everyone, toFriends: true, toCoaches: false)
            .map(\.profile.id)
        #expect(ids == ["friend-a", "friend-b"])
    }

    @Test func coachOnlyExcludesFriends() {
        let ids = WorkoutBroadcast.recipients(from: everyone, toFriends: false, toCoaches: true)
            .map(\.profile.id)
        #expect(ids == ["coach"])
    }

    @Test func bothOffSharesWithNobody() {
        #expect(WorkoutBroadcast.recipients(from: everyone, toFriends: false, toCoaches: false).isEmpty)
    }

    /// A coach's own workout is not pushed at the people they coach — the
    /// relationship only points one way.
    @Test func clientsNeverReceiveTheirCoachesWorkouts() {
        let clientsOnly = [Connection(profile: profile("client"), kind: .client)]
        #expect(WorkoutBroadcast.recipients(from: clientsOnly, toFriends: true, toCoaches: true).isEmpty)
    }

    // MARK: - What the sheet tells the user

    @Test func summaryNamesTheRecipients() {
        #expect(WorkoutBroadcast.Result(friends: 3, coaches: 1, failed: 0).summary
                == "Shared with 3 friends and your coach")
        #expect(WorkoutBroadcast.Result(friends: 1, coaches: 0, failed: 0).summary
                == "Shared with 1 friend")
        #expect(WorkoutBroadcast.Result(friends: 0, coaches: 2, failed: 0).summary
                == "Shared with 2 coaches")
        #expect(WorkoutBroadcast.Result(friends: 0, coaches: 0, failed: 2).summary == "Not shared")
    }

    @Test func failuresAloneDoNotClaimASend() {
        #expect(!WorkoutBroadcast.Result(friends: 0, coaches: 0, failed: 3).sentAnything)
        #expect(WorkoutBroadcast.Result(friends: 0, coaches: 1, failed: 3).sentAnything)
    }

    // MARK: - Defaults

    /// Both default ON — sharing is the point of the feature, opting out is the
    /// exception — and both survive being flipped.
    ///
    /// Default and round-trip are ONE test on purpose: they touch the same two
    /// global keys, and splitting them gives the parallel test runner a way to
    /// interleave the unset and the flip (the #1160 shared-static-state flake).
    @Test func switchesDefaultOnAndPersist() {
        let kv = DriftPlatform.keyValueStore
        kv.removeObject(forKey: "drift_share_workouts_friends")
        kv.removeObject(forKey: "drift_share_workouts_coaches")
        #expect(Preferences.shareWorkoutsWithFriends)
        #expect(Preferences.shareWorkoutsWithCoaches)

        Preferences.shareWorkoutsWithCoaches = false
        #expect(!Preferences.shareWorkoutsWithCoaches)
        #expect(Preferences.shareWorkoutsWithFriends, "the switches are independent")
        Preferences.shareWorkoutsWithCoaches = true
        #expect(Preferences.shareWorkoutsWithCoaches)
    }
}
