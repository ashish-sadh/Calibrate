import Foundation

/// Collects what you'd appear on a board with, and publishes it.
///
/// A FIXED set of ambient boards (operator 2026-07-31): steps, active calories,
/// workout count — all trailing 7 days — plus the food-logging streak. Everyone
/// has these without any logging discipline, and the set is the same for every
/// user, so a board is a shared thing rather than one person's private lift.
///
/// Per-exercise lift boards were removed here on the operator's call ("have a
/// fixed set for now — no need for individual exercises to be part of or
/// aggregated for the leaderboard"). They were self-selecting and clever but
/// fragmented the board into hundreds of one-person lifts and made the whole
/// surface hard to read. `Leaderboard.boardKeys` is the fixed set both this
/// publisher and the read path honor.
///
/// Separate from `LeaderboardService` because this half is the only part that
/// touches the health seam and the local workout store; the service is pure
/// transport, which is what lets it be tested without a HealthKit stub.
@MainActor
public enum LeaderboardPublisher {

    private static let lastPublishKey = "drift_leaderboard_last_publish_day"
    private static let lastPublishAtKey = "drift_leaderboard_last_publish_at"

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
        stampPublished(at: Date())
    }

    /// Refresh the viewer's OWN numbers when they open the leaderboard, so
    /// everyone reading their row sees a current value rather than yesterday's
    /// (operator 2026-07-31: "make sure numbers are refreshed and reported
    /// correctly from everyone"). The once-a-day gate is right for the silent
    /// background publish, but wrong the moment someone is actually LOOKING at
    /// the board — their steps since this morning simply weren't on it.
    ///
    /// Rate-limited by a real timestamp (default 10 min) so opening the tab
    /// repeatedly, or a recomposition, doesn't re-run the 14 health queries.
    /// Returns whether it actually published, so the caller re-reads only when
    /// the numbers could have changed.
    @discardableResult
    public static func publishForView(now: Date = Date(),
                                      minInterval: TimeInterval = 600) async -> Bool {
        guard Preferences.shareStatsWithFriends, SharingService.shared.isSignedIn else { return false }
        let last = DriftPlatform.keyValueStore.double(forKey: lastPublishAtKey)
        if last > 0, now.timeIntervalSince1970 - last < minInterval { return false }
        await publishNow()
        stampPublished(at: now)
        return true
    }

    private static func stampPublished(at date: Date) {
        DriftPlatform.keyValueStore.set(DateFormatters.dateOnly.string(from: date), forKey: lastPublishKey)
        DriftPlatform.keyValueStore.set(date.timeIntervalSince1970, forKey: lastPublishAtKey)
    }

    public static func publishNow() async {
        guard Preferences.shareStatsWithFriends,
              let uid = SharingService.shared.currentSession?.userID else { return }
        // A private board publishes NOTHING. Filtered before the upsert rather
        // than stamped with a visibility, because "private" isn't an audience —
        // there is no row to show anyone.
        var entries = await collect(userID: uid)
            .filter { !Preferences.boardIsPrivate($0.boardKey) }
        guard !entries.isEmpty else { return }
        // Stamp each row with the audience the user chose for THAT board. Done
        // here, at the last moment, so flipping a board to friends-only takes
        // effect on the next publish without a separate migration of rows.
        for i in entries.indices {
            entries[i].visibility =
                Preferences.boardIsGlobal(entries[i].boardKey) ? "global" : "friends"
        }
        // Best-effort: a leaderboard that can't publish must never surface as an
        // error over someone's workout.
        try? await SharingService.shared.upsertLeaderboardEntries(entries)
    }

    /// Everything this user would appear with, right now.
    static func collect(userID: String, now: Date = Date()) async -> [LeaderboardEntryDTO] {
        var out: [LeaderboardEntryDTO] = []
        let week = LeaderboardService.periodStart(.week, for: now)

        // --- Ambient, TRAILING 7 DAYS ---
        //
        // Rolling, not week-to-date. Calendar-to-date had a cliff: at 00:01 on
        // Monday everyone's total was ~0 and climbed back over seven days, so
        // the board was near-meaningless for the first half of every week and a
        // friend who hadn't opened the app since Sunday vanished from it
        // entirely. Operator: "it should be a sliding window, right? Why empty
        // every Monday?"
        //
        // The old argument for calendar windows was fairness — everyone measured
        // over the same days. But that's precisely what a Monday breaks: my
        // seven days against your one. Two trailing 7-day totals computed a day
        // apart are FAR closer to equal than that, and they never reset.
        if let health = DriftPlatform.health, health.isAvailable {
            let cal = Calendar.current
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
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
        // Trailing 7 days here too, for the same reason.
        let cal = Calendar.current
        let since = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now)) ?? now
        let sinceDay = DateFormatters.dateOnly.string(from: since)
        var workouts = Double(((try? WorkoutService.fetchWorkouts(limit: 200)) ?? [])
            .filter { $0.date >= sinceDay }.count)
        if let health = DriftPlatform.health, health.isAvailable,
           let recent = try? await health.fetchRecentWorkouts(days: 7) {
            workouts += Double(recent.filter { $0.date >= since }.count)
        }
        if workouts > 0 {
            out.append(.init(userId: userID, boardKey: "workouts", periodStart: week,
                            value: workouts, unit: ""))
        }

        // Food-logging streak. The board that actually populates: steps need a
        // phone in your pocket and a lift board needs a friend training the same
        // lift, but anyone who has used Drift twice has a streak.
        // Published even at ZERO, unlike the health boards above.
        //
        // A broken streak used to be OMITTED, and an omitted row doesn't
        // overwrite anything — so the last good value sat on everyone's board
        // forever. Live rows on 2026-08-02 showed exactly that: a user whose
        // steps/calories/workouts all updated that afternoon still showed a
        // 5-day streak last written on 08-01, because their streak had since
        // broken and the row was skipped. Operator: "it's not getting refreshed
        // and food logging streak should be refreshed daily? Is it happening?"
        // It wasn't — the number was a fossil.
        //
        // Zero is safe to publish HERE because the streak comes from the local
        // food log, where zero unambiguously means "no logs". The health boards
        // above stay guarded: HealthKit returns 0 both for a genuinely still day
        // and for revoked permission, and publishing that would wipe a real
        // number over a permissions prompt. `rank` drops zeroes from display, so
        // this leaves the board rather than showing a demoralising 0.
        let streak = FoodLoggingStreak.mine(today: now)
        out.append(.init(userId: userID, boardKey: "food_streak", periodStart: week,
                        value: Double(streak), unit: "days"))

        return out
    }
}
