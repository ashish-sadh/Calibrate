import Foundation

/// Sends a finished workout to the people who should see it, without making the
/// user tap through a recipient list every session.
///
/// Replaces per-person picking as the DEFAULT (operator 2026-07-29). Two
/// switches, both ON by default, shown on the completion sheet so a test
/// session can be kept private: "sometimes I might be testing and only want to
/// share with friends but not trainer."
///
/// Friends receive it silently — a friend's training is not an interruption.
/// Coaches receive it and, for a workout LOGGED in Drift, get an alert; an
/// imported one shares without interrupting (`NotifiableEvent`, #1162).
///
/// The manual picker stays available for "send this one to just X".
public enum WorkoutBroadcast {

    /// Who a broadcast reached, so the UI can say where the workout went rather
    /// than leaving the user guessing.
    public struct Result: Sendable, Equatable {
        public var friends: Int
        public var coaches: Int
        public var failed: Int

        public var sentAnything: Bool { friends > 0 || coaches > 0 }

        /// "Shared with 3 friends and your coach" — stated plainly, because
        /// automatic sharing that doesn't say where it went is the kind of
        /// thing people discover later and resent.
        public var summary: String {
            var parts: [String] = []
            if friends > 0 { parts.append("\(friends) friend\(friends == 1 ? "" : "s")") }
            if coaches > 0 { parts.append(coaches == 1 ? "your coach" : "\(coaches) coaches") }
            guard !parts.isEmpty else { return "Not shared" }
            return "Shared with " + parts.joined(separator: " and ")
        }
    }

    /// Which connections a broadcast would reach given the two switches. Pure,
    /// so the routing rule is Tier-0 testable without a network.
    public static func recipients(from connections: [Connection],
                                 toFriends: Bool,
                                 toCoaches: Bool) -> [Connection] {
        connections.filter { connection in
            switch connection.kind {
            case .friend: return toFriends
            case .coach: return toCoaches
            // A client never receives their coach's workouts — the coach
            // relationship is one-directional by design.
            case .client: return false
            }
        }
    }

    /// Share to everyone the switches allow. Never throws: a workout is saved
    /// locally first, and a failed share must not look like a failed save.
    @MainActor
    public static func send(workoutName: String,
                           sets: [SharingService.SharedSet],
                           toFriends: Bool = Preferences.shareWorkoutsWithFriends,
                           toCoaches: Bool = Preferences.shareWorkoutsWithCoaches) async -> Result {
        var result = Result(friends: 0, coaches: 0, failed: 0)
        let svc = SharingService.shared
        guard svc.isSignedIn, toFriends || toCoaches else { return result }
        guard let connections = try? await svc.connections() else { return result }

        for connection in recipients(from: connections, toFriends: toFriends, toCoaches: toCoaches) {
            do {
                try await svc.shareCompletedWorkout(
                    to: connection.profile.id, workoutName: workoutName, sets: sets)
                if connection.kind == .coach { result.coaches += 1 } else { result.friends += 1 }
            } catch {
                // One unreachable recipient must not stop the rest.
                result.failed += 1
            }
        }
        return result
    }
}
