import Foundation
import DriftCore

/// Re-push the briefing to every coach the client already shares with. The
/// briefing upserts "the current picture" — but until 2026-07-29 it was only
/// pushed when the client touched the sharing toggle, so notes recorded AFTER
/// that (every Coach Me session, every chat note) sat on the device until the
/// client happened to revisit the card. The human coach read a stale client.
///
/// Consent unchanged: each coach gets exactly their stored level, `.none`
/// coaches are never contacted, and a failure is silent — the next change
/// retries.
enum BriefingRepush {
    @MainActor
    static func afterNotesChanged() async {
        let svc = SharingService.shared
        guard svc.isSignedIn else { return }
        guard let connections = try? await svc.connections() else { return }
        let notes = CoachNotes.load()
        for coach in connections where coach.kind == .coach {
            let level = BriefingSharingLevel.stored(for: coach.id)
            guard level != .none else { continue }
            let metrics = await BriefingSnapshot.metrics(level: level)
            try? await svc.shareBriefing(with: coach.id, level: level, notes: notes, metrics: metrics)
        }
    }
}

/// Distills a Drift Coach chat session into a `CoachNotes` moment so the human
/// coach's briefing knows what the client has been telling the AI (operator
/// 2026-07-29: "the summary note shown to the human coach as well, whatever
/// client talks to AI coach"). The note is stored on-device; it reaches a
/// coach only through the briefing's existing History consent.
enum CoachChatNoteTaker {
    /// `history` is "user: …" / "coach: …" lines, oldest first.
    @MainActor
    static func capture(history: [String]) async {
        guard let note = await NebiusCoach.chatNote(history: history) else { return }
        var notes = CoachNotes.load()
        notes.record(note, kind: .moment)
        notes.save()
        await BriefingRepush.afterNotesChanged()
    }
}

/// Gathers the local data a briefing needs and hands it to
/// `BriefingAggregator`. Lives in SharedUI rather than DriftCore because sleep
/// comes through the HealthKit seam, which is a platform adapter — the maths
/// itself stays pure and Tier-0 tested in `BriefingAggregator`.
///
/// Only reads what the client opted into. A category left off is never even
/// queried, so there is no window where the number exists in memory next to a
/// network call that might send it.
enum BriefingSnapshot {

    static let windowDays = 7
    /// Trend horizon. The headline numbers stay a 7-day picture (that's what
    /// "average sleep" means to a coach); the trends need enough weeks to show
    /// a direction.
    static let trendWeeks = 8
    static var trendDays: Int { trendWeeks * 7 }

    @MainActor
    static func metrics(level: BriefingSharingLevel, days: Int = windowDays) async -> BriefingMetrics {
        let calendar = Calendar.current
        let today = Date()
        let dates = (0..<days).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }

        var sleep: [(date: Date, hours: Double)] = []
        var trendSleep: [(date: Date, hours: Double)] = []
        if level.contains(.sleep), let health = DriftPlatform.health {
            // Android has no health adapter yet, so this stays empty there and
            // the field is simply absent rather than reported as zero.
            // One fetch over the trend horizon, then the 7-day slice is taken
            // from it — asking HealthKit twice for overlapping ranges is a
            // per-day-loop tax we don't need (see the #1008 perf work).
            let nights = (try? await health.fetchRecentSleepData(days: trendDays)) ?? []
            trendSleep = nights.map { (date: $0.date, hours: $0.hours) }
            let cutoff = calendar.date(byAdding: .day, value: -days, to: today) ?? today
            sleep = trendSleep.filter { $0.date >= cutoff }
        }

        var nutrition: [BriefingAggregator.NutritionDay] = []
        var trendNutrition: [BriefingAggregator.NutritionDay] = []
        var proteinTarget: Double?
        var daysLogged: Int?
        if level.contains(.nutrition) {
            let trendDates = (0..<trendDays).compactMap {
                calendar.date(byAdding: .day, value: -$0, to: today)
            }
            let cutoff = calendar.date(byAdding: .day, value: -days, to: today) ?? today
            var loggedInWindow = 0
            for date in trendDates {
                let key = DateFormatters.dateOnly.string(from: date)
                let totals = FoodService.getDailyTotals(date: key)
                // A day with nothing logged is skipped, not averaged as zero —
                // otherwise a coach reads "ate nothing Tuesday" when the truth
                // is "didn't log Tuesday". `daysLogged` carries that
                // distinction explicitly instead of hiding it.
                guard totals.eaten > 0 else { continue }
                let day = BriefingAggregator.NutritionDay(
                    date: date,
                    calories: Double(totals.eaten),
                    proteinG: Double(totals.proteinG))
                trendNutrition.append(day)
                if date >= cutoff {
                    nutrition.append(day)
                    loggedInWindow += 1
                }
            }
            daysLogged = loggedInWindow
            proteinTarget = WeightGoal.load()?.proteinTargetG
        }

        var weights: [(date: Date, lbs: Double)] = []
        var trendWeights: [(date: Date, lbs: Double)] = []
        if level.contains(.weight) {
            trendWeights = WeightServiceAPI.getHistory(days: trendDays).compactMap {
                entry -> (date: Date, lbs: Double)? in
                guard let date = DateFormatters.dateOnly.date(from: entry.date) else { return nil }
                return (date: date, lbs: entry.weightLbs)
            }
            let cutoff = calendar.date(byAdding: .day, value: -days, to: today) ?? today
            weights = trendWeights.filter { $0.date >= cutoff }
        }

        // Strength records read the FULL history — a PR is by definition
        // all-time, not something that happened this week.
        let records = level.contains(.strength)
            ? ((try? WorkoutService.personalRecords(limit: 5)) ?? [])
            : []

        // Recovery is graded on the CLIENT, with the client's own learned
        // thresholds, so the coach sees the same colours the client does.
        let recovery = level.contains(.strength)
            ? MuscleRecoveryMap.points(lastTrained: MuscleRecoveryMap.lastTrainedByGroup(),
                                       soreness: MuscleSoreness.loadState())
            : []

        // Only the DIRECTION crosses, never the goal: a coach needs to know
        // whether flat weight is a stall or the plan working, and that is the
        // whole of it — target weight and deadline stay on the device.
        var direction = BriefingAggregator.WeightGoalDirection.none
        if level.contains(.weight), let goal = WeightGoal.load() {
            let delta = goal.targetWeightKg - goal.startWeightKg
            if delta < -0.5 { direction = .losing }
            else if delta > 0.5 { direction = .gaining }
        }

        // Body comp reads the whole scan history (scans are sparse, not
        // windowed) — the aggregator keeps only the latest + the diff.
        let scans = level.contains(.bodyComp) ? DEXAService.fetchScans() : []

        return BriefingAggregator.metrics(
            level: level, windowDays: days,
            sleepHours: sleep, nutrition: nutrition, weights: weights,
            proteinTargetG: proteinTarget,
            workoutsCompleted: completedWorkouts(since: days),
            scans: scans,
            daysLogged: daysLogged,
            trendSleep: trendSleep,
            trendNutrition: trendNutrition,
            trendWeights: trendWeights,
            records: records,
            weightGoalDirection: direction,
            recovery: recovery)
    }

    /// Adherence — the number a coach checks first. Derived from sessions the
    /// coach can already see, so it rides along with any sharing at all.
    static func completedWorkouts(since days: Int) -> Int {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return 0 }
        let cutoffKey = DateFormatters.dateOnly.string(from: cutoff)
        let workouts = (try? WorkoutService.fetchWorkouts()) ?? []
        // String comparison is safe here: yyyy-MM-dd sorts lexicographically.
        return workouts.filter { $0.date >= cutoffKey }.count
    }
}
