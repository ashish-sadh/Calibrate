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

    @MainActor
    static func metrics(level: BriefingSharingLevel, days: Int = windowDays) async -> BriefingMetrics {
        let calendar = Calendar.current
        let today = Date()
        let dates = (0..<days).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }

        var sleep: [(date: Date, hours: Double)] = []
        if level.contains(.sleep), let health = DriftPlatform.health {
            // Android has no health adapter yet, so this stays empty there and
            // the field is simply absent rather than reported as zero.
            let nights = (try? await health.fetchRecentSleepData(days: days)) ?? []
            sleep = nights.map { (date: $0.date, hours: $0.hours) }
        }

        var nutrition: [BriefingAggregator.NutritionDay] = []
        var proteinTarget: Double?
        if level.contains(.nutrition) {
            for date in dates {
                let key = DateFormatters.dateOnly.string(from: date)
                let totals = FoodService.getDailyTotals(date: key)
                // A day with nothing logged is skipped, not averaged as zero —
                // otherwise a coach reads "ate nothing Tuesday" when the truth
                // is "didn't log Tuesday".
                guard totals.eaten > 0 else { continue }
                nutrition.append(.init(date: date,
                                       calories: Double(totals.eaten),
                                       proteinG: Double(totals.proteinG)))
            }
            proteinTarget = WeightGoal.load()?.proteinTargetG
        }

        var weights: [(date: Date, lbs: Double)] = []
        if level.contains(.weight) {
            weights = WeightServiceAPI.getHistory(days: days).compactMap {
                entry -> (date: Date, lbs: Double)? in
                guard let date = DateFormatters.dateOnly.date(from: entry.date) else { return nil }
                return (date: date, lbs: entry.weightLbs)
            }
        }

        return BriefingAggregator.metrics(
            level: level, windowDays: days,
            sleepHours: sleep, nutrition: nutrition, weights: weights,
            proteinTargetG: proteinTarget,
            workoutsCompleted: completedWorkouts(since: days))
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
