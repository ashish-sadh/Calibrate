import Foundation

/// Collects what you'd appear on a board with, and publishes it.
///
/// Two families today:
///   * **week** — steps, active calories, workout count. Ambient: everyone has
///     them, no logging discipline required.
///   * **month** — your heaviest single set per lift, over the last 30 days.
///     This is what makes the boards self-selecting: you publish the lifts you
///     actually train, and a board appears only where a friend trains it too.
///
/// Separate from `LeaderboardService` because this half is the only part that
/// touches the health seam and the local workout store; the service is pure
/// transport, which is what lets it be tested without a HealthKit stub.
@MainActor
public enum LeaderboardPublisher {

    /// **How many lift boards one person may publish per period.**
    ///
    /// Bounded because unbounded is the whole scaling risk here: someone with 300
    /// distinct exercises in their history would write 300 rows a month, and the
    /// friend fan-in would be 150 × 300 rather than 150 × ~11. Capped at the lifts
    /// they train MOST, which are also the ones most likely to overlap with a
    /// friend's — a board needs two people, so publishing your rarest lift is
    /// almost certainly publishing a board of one.
    public static let maxLiftBoards = 8

    /// Days of history a monthly lift board looks at. "Highest deadlift in the
    /// last month", per the operator.
    public static let liftWindowDays = 30

    private static let lastPublishKey = "drift_leaderboard_last_publish_day"

    /// Publish at most once a day unless forced.
    ///
    /// Collecting a week of steps and calories costs up to 14 health queries —
    /// they're per-DAY calls on both platforms with no range API to batch them
    /// (the per-day-loop pattern behind several past P1s). Fine once a day,
    /// wasteful on every screen. `force` covers the moment someone flips the
    /// switch on, where waiting until tomorrow to appear reads as breakage.
    public static func publishIfDue(force: Bool = false) async {
        guard Preferences.shareStatsWithFriends, SharingService.shared.isSignedIn else { return }
        let today = DateFormatters.dateOnly.string(from: Date())
        if !force, DriftPlatform.keyValueStore.string(forKey: lastPublishKey) == today { return }
        await publishNow()
        DriftPlatform.keyValueStore.set(today, forKey: lastPublishKey)
    }

    public static func publishNow() async {
        guard Preferences.shareStatsWithFriends,
              let uid = SharingService.shared.currentSession?.userID else { return }
        let entries = await collect(userID: uid)
        guard !entries.isEmpty else { return }
        // Best-effort: a leaderboard that can't publish must never surface as an
        // error over someone's workout.
        try? await SharingService.shared.upsertLeaderboardEntries(entries)
    }

    /// Everything this user would appear with, right now.
    static func collect(userID: String, now: Date = Date()) async -> [LeaderboardEntryDTO] {
        var out: [LeaderboardEntryDTO] = []
        let week = LeaderboardService.periodStart(.week, for: now)
        let month = LeaderboardService.periodStart(.month, for: now)

        // --- Ambient, week-to-date ---
        // Week-TO-DATE rather than a trailing 7 days: the board compares people
        // over the same calendar window, and a trailing window would rank
        // whoever happened to open the app latest in the day.
        if let health = DriftPlatform.health, health.isAvailable {
            var cal = Calendar.current
            cal.firstWeekday = 2  // Monday, matching LeaderboardService
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            var steps = 0.0
            var calories = 0.0
            var day = start
            while day <= now {
                // ACTIVE energy only. Basal is what a body burns lying still —
                // including it would rank people by size rather than by effort.
                if let burned = try? await health.fetchCaloriesBurned(for: day) {
                    calories += burned.active
                }
                if let walked = try? await health.fetchSteps(for: day) { steps += walked }
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            if steps > 0 {
                out.append(.init(userId: userID, boardKey: "steps", periodStart: week,
                                value: steps.rounded(), unit: ""))
            }
            if calories > 0 {
                out.append(.init(userId: userID, boardKey: "calories", periodStart: week,
                                value: calories.rounded(), unit: "kcal"))
            }
        }

        // Workouts recorded in Drift plus ones a watch noticed. Summed for the
        // count board — unlike the coach briefing, a board only needs "did you
        // train", and splitting it here would make two boards that rank the same
        // people by which hardware they own.
        var workouts = Double((try? WorkoutService.weeklyWorkoutCounts(weeks: 1))?.last?.count ?? 0)
        if let health = DriftPlatform.health, health.isAvailable,
           let recent = try? await health.fetchRecentWorkouts(days: 7) {
            var cal = Calendar.current
            cal.firstWeekday = 2
            let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            workouts += Double(recent.filter { $0.date >= start }.count)
        }
        if workouts > 0 {
            out.append(.init(userId: userID, boardKey: "workouts", periodStart: week,
                            value: workouts, unit: ""))
        }

        // --- Lifts, last 30 days ---
        out += liftEntries(userID: userID, periodStart: month, now: now)
        return out
    }

    /// Heaviest single set per lift in the window, capped to the most-trained.
    ///
    /// Heaviest SET, not estimated 1RM: a 1RM is a formula, and ranking friends
    /// by a projection invites arguing with the projection. What someone actually
    /// picked up is a fact.
    static func liftEntries(userID: String, periodStart: String,
                           now: Date = Date()) -> [LeaderboardEntryDTO] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -liftWindowDays, to: now),
              let workouts = try? WorkoutService.fetchWorkouts(limit: 500) else { return [] }

        let cutoffDay = DateFormatters.dateOnly.string(from: cutoff)
        let recentIDs = Set(workouts.filter { $0.date >= cutoffDay }.compactMap(\.id))
        guard !recentIDs.isEmpty else { return [] }

        var heaviest: [String: Double] = [:]
        var sessions: [String: Set<Int64>] = [:]
        for id in recentIDs {
            guard let sets = try? WorkoutService.fetchSets(forWorkout: id) else { continue }
            for set in sets {
                // Warmups are not what anyone means by their heaviest set.
                guard !set.isWarmup, let weight = set.weightLbs, weight > 0,
                      let key = LeaderboardBoard.liftKey(for: set.exerciseName) else { continue }
                heaviest[key] = max(heaviest[key] ?? 0, weight)
                sessions[key, default: []].insert(id)
            }
        }

        // Most-trained first, so the cap keeps the lifts most likely to be shared
        // with a friend. Ties by key, so the selection is stable rather than
        // shuffling which boards you appear on between publishes.
        let ranked = heaviest.keys.sorted { a, b in
            let sa = sessions[a]?.count ?? 0
            let sb = sessions[b]?.count ?? 0
            if sa != sb { return sa > sb }
            return a < b
        }

        return ranked.prefix(maxLiftBoards).compactMap { key in
            guard let weight = heaviest[key] else { return nil }
            return LeaderboardEntryDTO(userId: userID, boardKey: key,
                                      periodStart: periodStart,
                                      value: weight.rounded(), unit: "lbs")
        }
    }
}
