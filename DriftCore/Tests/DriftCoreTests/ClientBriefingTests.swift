import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for what a coach is allowed to see. The transport is Tier-3; what's
/// locked here is the part that decides whether data the user withheld can
/// still reach a coach — the bug that would matter.
struct ClientBriefingTests {

    // MARK: - Consent

    /// The default. Connecting to a coach is consent to share workouts, not a
    /// standing grant over sleep, food and injuries.
    @Test func nothingIsSharedUntilItIsChosen() {
        let level = BriefingSharingLevel.stored(for: "coach-never-configured")
        #expect(level == .none)
        #expect(level.descriptions.isEmpty)
    }

    /// The load-bearing test: a withheld category must be absent from the wire
    /// payload, not merely hidden in the UI. Filtering happens before the
    /// network, so opting out of nutrition means the number never leaves.
    @Test func withheldCategoriesNeverReachThePayload() {
        let metrics = BriefingAggregator.metrics(
            level: [.sleep],                       // sleep only — no nutrition, no weight
            sleepHours: [(Date(), 6.0), (Date(), 7.0)],
            nutrition: [.init(date: Date(), calories: 2200, proteinG: 140)],
            weights: [(Date(), 180), (Date(), 176)])

        #expect(metrics.avgSleepHours == 6.5)
        #expect(metrics.avgProteinG == nil, "nutrition wasn't shared")
        #expect(metrics.weightChangeLbs == nil, "weight wasn't shared")

        let payload = metrics.payload
        #expect(payload["avg_sleep_hours"] != nil)
        #expect(payload["avg_protein_g"] == nil)
        #expect(payload["avg_calories"] == nil)
        #expect(payload["weight_change_lbs"] == nil)
    }

    @Test func optingIntoEverythingSendsEverything() {
        let metrics = BriefingAggregator.metrics(
            level: [.history, .sleep, .nutrition, .weight],
            sleepHours: [(Date(), 8.0)],
            nutrition: [.init(date: Date(), calories: 2000, proteinG: 100),
                        .init(date: Date(), calories: 2400, proteinG: 140)],
            weights: [(Date(timeIntervalSince1970: 0), 180),
                      (Date(timeIntervalSince1970: 86_400), 177.5)],
            proteinTargetG: 150,
            workoutsCompleted: 3)

        #expect(metrics.avgCalories == 2200)
        #expect(metrics.avgProteinG == 120)
        #expect(metrics.proteinTargetG == 150)
        #expect(metrics.weightChangeLbs == -2.5)
        #expect(metrics.workoutsCompleted == 3)
    }

    // MARK: - Honest absence

    /// "No data" and "zero" mean opposite things to a coach: 0g protein reads
    /// as a client who ate nothing, while absent reads as nothing to report.
    @Test func noDataIsAbsentRatherThanZero() {
        let metrics = BriefingAggregator.metrics(level: [.sleep, .nutrition, .weight])
        #expect(metrics.avgSleepHours == nil)
        #expect(metrics.avgCalories == nil)
        #expect(metrics.lines.isEmpty)
    }

    /// One weigh-in is not a trend. Reporting 0.0 would claim the client held
    /// steady across the window, which we haven't earned from a single point.
    @Test func aSingleWeighInIsNotATrend() {
        #expect(BriefingAggregator.change([(Date(), 180)]) == nil)
        #expect(BriefingAggregator.change([]) == nil)
    }

    // MARK: - Round trip

    @Test func metricsSurviveEncodeAndDecode() {
        var original = BriefingMetrics()
        original.windowDays = 14
        original.avgSleepHours = 6.4
        original.avgProteinG = 118
        original.workoutsCompleted = 5

        let decoded = BriefingMetrics.decode(original.payload)
        #expect(decoded.windowDays == 14)
        #expect(decoded.avgSleepHours == 6.4)
        #expect(decoded.avgProteinG == 118)
        #expect(decoded.workoutsCompleted == 5)
        #expect(decoded.avgCalories == nil)
    }

    /// Postgres hands back jsonb numbers as Int or Double depending on the
    /// value; a strict read would drop a whole-number average.
    @Test func decodeToleratesWhateverNumberTypePostgresReturns() {
        let decoded = BriefingMetrics.decode(["avg_sleep_hours": 7, "avg_protein_g": "118.5"])
        #expect(decoded.avgSleepHours == 7)
        #expect(decoded.avgProteinG == 118.5)
    }

    @Test func briefingRowParsesNotesAndMetrics() {
        let row: [String: Any] = [
            "summary": "2 days/week, 45 min, full gym",
            "notes": [["id": "n1", "date": "2026-07-20", "text": "Back sore", "kind": "moment"]],
            "metrics": ["avg_sleep_hours": 6.2, "window_days": 7],
        ]
        let briefing = SharingService.parseBriefing(row, clientID: "client-1")
        #expect(briefing.notes.count == 1)
        #expect(briefing.notes.first?.kind == .moment)
        #expect(briefing.metrics.avgSleepHours == 6.2)
        #expect(!briefing.isEmpty)
    }

    @Test func anEmptyBriefingKnowsItIsEmpty() {
        let briefing = SharingService.parseBriefing([:], clientID: "c")
        #expect(briefing.isEmpty, "so the coach sees 'nothing shared yet', not a blank card")
    }

    // MARK: - Body composition (.bodyComp opt-in)

    /// The consent guarantee extends to the new category: scans stay off the
    /// wire unless the bodyComp bit is set, and the bit only sends summary
    /// numbers — never the scan itself.
    @Test func bodyCompStaysOffTheWireUntilChosen() {
        let scans = [DEXAScan(scanDate: "2026-07-01", leanMassKg: 63.0, bodyFatPct: 25.0),
                     DEXAScan(scanDate: "2026-07-25", leanMassKg: 63.5, bodyFatPct: 24.1)]

        let withheld = BriefingAggregator.metrics(level: [.weight], scans: scans)
        #expect(withheld.bodyFatPct == nil)
        #expect(withheld.payload["body_fat_pct"] == nil)

        let shared = BriefingAggregator.metrics(level: [.bodyComp], scans: scans)
        #expect(shared.bodyFatPct == 24.1)
        #expect(shared.scanDate == "2026-07-25")
        #expect(shared.payload["body_fat_pct"] != nil)
    }

    /// Diffs are latest-vs-previous by scan DATE (not array order), and lean
    /// mass converts kg→lb to match the app's display convention.
    @Test func bodyCompDiffsAreLatestVsPreviousByDate() {
        // Deliberately unordered.
        let scans = [DEXAScan(scanDate: "2026-07-25", leanMassKg: 63.5, bodyFatPct: 24.1),
                     DEXAScan(scanDate: "2026-03-10", leanMassKg: 61.0, bodyFatPct: 27.0),
                     DEXAScan(scanDate: "2026-07-01", leanMassKg: 63.0, bodyFatPct: 25.0)]

        let metrics = BriefingAggregator.metrics(level: [.bodyComp], scans: scans)
        #expect(metrics.bodyFatDeltaPct != nil)
        #expect(abs((metrics.bodyFatDeltaPct ?? 0) - -0.9) < 0.0001, "24.1 vs the 07-01 scan's 25.0")
        #expect(abs((metrics.leanMassLbs ?? 0) - 63.5 * 2.20462) < 0.001)
        #expect(abs((metrics.leanMassDeltaLbs ?? 0) - 0.5 * 2.20462) < 0.001)
    }

    /// One scan = numbers with no delta; a scan missing a value produces no
    /// delta for that value ("progress vs nothing" must not render).
    @Test func bodyCompDeltasNeedBothScans() {
        let single = BriefingAggregator.metrics(
            level: [.bodyComp], scans: [DEXAScan(scanDate: "2026-07-25", bodyFatPct: 24.1)])
        #expect(single.bodyFatPct == 24.1)
        #expect(single.bodyFatDeltaPct == nil)
        #expect(single.leanMassLbs == nil)

        let sparse = BriefingAggregator.metrics(
            level: [.bodyComp],
            scans: [DEXAScan(scanDate: "2026-07-25", leanMassKg: 63.5, bodyFatPct: 24.1),
                    DEXAScan(scanDate: "2026-07-01", leanMassKg: nil, bodyFatPct: nil)])
        #expect(sparse.bodyFatDeltaPct == nil)
        #expect(sparse.leanMassDeltaLbs == nil)

        let none = BriefingAggregator.metrics(level: [.bodyComp], scans: [])
        #expect(none.bodyFatPct == nil)
        #expect(none.scanDate == nil)
    }

    @Test func bodyCompSurvivesEncodeAndDecode() {
        var original = BriefingMetrics()
        original.bodyFatPct = 24.1
        original.bodyFatDeltaPct = -0.9
        original.leanMassLbs = 140.0
        original.scanDate = "2026-07-25"

        let decoded = BriefingMetrics.decode(original.payload)
        #expect(decoded.bodyFatPct == 24.1)
        #expect(decoded.bodyFatDeltaPct == -0.9)
        #expect(decoded.leanMassLbs == 140.0)
        #expect(decoded.scanDate == "2026-07-25")
        #expect(decoded.leanMassDeltaLbs == nil)
    }

    // MARK: - Weekly trends, adherence, records

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_750_000_000 + Double(offset) * 86_400)
    }

    /// Trends are WEEKLY AVERAGES — the consent boundary, not a display
    /// choice. Two weeks of daily weights collapse to two points, each the
    /// week's mean.
    @Test func trendsBucketDailyValuesIntoWeeklyAverages() {
        // Two clean weeks: 7 days at 180, then 7 days at 178.
        var samples: [(date: Date, value: Double)] = []
        for i in 0..<7 { samples.append((day(i), 180)) }
        for i in 7..<14 { samples.append((day(i), 178)) }

        let points = BriefingAggregator.weeklyAverages(samples)
        #expect(points?.count == 2)
        #expect(points?.first?.value == 180)
        #expect(points?.last?.value == 178)
        // Oldest first, so a chart reads left-to-right in time.
        #expect((points?.first?.weekStart ?? "") < (points?.last?.weekStart ?? ""))
    }

    /// A single week is a number, not a direction — `trends` drops it.
    @Test func oneWeekIsNotATrend() {
        var metrics = BriefingMetrics()
        metrics.weightSeries = [WeeklyPoint(weekStart: "2026-07-20", value: 180)]
        #expect(metrics.trends.isEmpty)

        metrics.weightSeries?.append(WeeklyPoint(weekStart: "2026-07-27", value: 177.6))
        let trend = metrics.trends.first
        #expect(trend?.label == "Weight")
        #expect(trend?.weeks == 2)
        #expect(trend?.changeText == "-2.4 lb")
    }

    /// Series ride their category's existing bit, and stay off the wire when
    /// that category is withheld.
    @Test func seriesFollowTheirCategoryConsent() {
        let sleep = [(date: day(0), hours: 7.0), (date: day(8), hours: 6.0)]
        let weights = [(date: day(0), lbs: 180.0), (date: day(8), lbs: 178.0)]

        let sleepOnly = BriefingAggregator.metrics(
            level: [.sleep], trendSleep: sleep, trendWeights: weights)
        #expect(sleepOnly.sleepSeries?.count == 2)
        #expect(sleepOnly.weightSeries == nil, "weight wasn't shared")
        #expect(sleepOnly.payload["weight_series"] == nil)

        let both = BriefingAggregator.metrics(
            level: [.sleep, .weight], trendSleep: sleep, trendWeights: weights)
        #expect(both.weightSeries?.count == 2)
        #expect(both.payload["weight_series"] != nil)
    }

    /// "Didn't log" must be distinguishable from "ate nothing" — the averages
    /// alone can't say which happened.
    @Test func daysLoggedRidesWithNutritionAndShowsAdherence() {
        let metrics = BriefingAggregator.metrics(
            level: [.nutrition], windowDays: 7,
            nutrition: [.init(date: day(0), calories: 2000, proteinG: 120)],
            daysLogged: 5)
        #expect(metrics.daysLogged == 5)
        #expect(metrics.lines.contains { $0.label == "Days logged" && $0.value == "5/7" })

        let withheld = BriefingAggregator.metrics(level: [.weight], daysLogged: 5)
        #expect(withheld.daysLogged == nil)
        #expect(withheld.payload["days_logged"] == nil)
    }

    /// PRs come from the full history and need the .strength bit — they are a
    /// widening beyond the sessions a client explicitly shared.
    @Test func recordsNeedTheStrengthBit() {
        let prs = [PersonalRecord(exercise: "Bench Press", weightLbs: 185, reps: 5,
                                  estimated1RM: 208.1, date: "2026-07-20")]

        let withheld = BriefingAggregator.metrics(level: [.weight], records: prs)
        #expect(withheld.records == nil)
        #expect(withheld.payload["records"] == nil)

        let shared = BriefingAggregator.metrics(level: [.strength], records: prs)
        #expect(shared.records?.count == 1)
        #expect(shared.records?.first?.setDescription == "185 lb × 5")
        #expect(shared.payload["records"] != nil)
    }

    /// The whole trend/record payload must survive the jsonb round trip, or a
    /// coach reads a briefing that silently lost its charts.
    @Test func trendsAndRecordsSurviveEncodeAndDecode() {
        var original = BriefingMetrics()
        original.weightSeries = [WeeklyPoint(weekStart: "2026-07-13", value: 180.2),
                                 WeeklyPoint(weekStart: "2026-07-20", value: 178.4)]
        original.daysLogged = 6
        original.records = [PersonalRecord(exercise: "Squat", weightLbs: 245, reps: 3,
                                           estimated1RM: 269.6, date: "2026-07-18")]

        let decoded = BriefingMetrics.decode(original.payload)
        #expect(decoded.weightSeries?.count == 2)
        #expect(decoded.weightSeries?.last?.value == 178.4)
        #expect(decoded.weightSeries?.first?.weekStart == "2026-07-13")
        #expect(decoded.daysLogged == 6)
        #expect(decoded.records?.first?.exercise == "Squat")
        #expect(decoded.records?.first?.reps == 3)
        #expect(decoded.sleepSeries == nil)
    }

    /// A briefing carrying only trends/records is NOT empty — otherwise the
    /// coach card would hide a client who shares exactly those.
    @Test func aBriefingWithOnlyTrendsIsNotEmpty() {
        var metrics = BriefingMetrics()
        metrics.weightSeries = [WeeklyPoint(weekStart: "2026-07-13", value: 180),
                                WeeklyPoint(weekStart: "2026-07-20", value: 178)]
        let briefing = ClientBriefing(clientID: "c", summary: "", notes: [], metrics: metrics)
        #expect(!briefing.isEmpty)
    }

    // MARK: - Recovery map

    /// The client grades its own recovery with its LEARNED thresholds, so the
    /// coach sees the same colour the client sees. Default 72h reproduces the
    /// original day thresholds: 0-1d recovering, 2d moderate, 3d+ recovered.
    @Test func recoveryUsesTheClientsLearnedThresholds() {
        let today = Date()
        func daysAgo(_ n: Int) -> Date { today.addingTimeInterval(-Double(n) * 86_400) }

        let points = MuscleRecoveryMap.points(
            lastTrained: ["Legs": daysAgo(1), "Chest": daysAgo(2),
                          "Back": daysAgo(4), "Arms": daysAgo(30)],
            soreness: MuscleSoreness.State(),
            today: today)

        func status(_ group: String) -> MuscleRecoveryPoint.Status? {
            points.first { $0.group == group }?.status
        }
        #expect(status("Legs") == .recovering)
        #expect(status("Chest") == .moderate)
        #expect(status("Back") == .recovered)
        #expect(status("Arms") == .untrained, "30 days off is not 'ready'")
        #expect(status("Core") == .untrained, "never trained")
        #expect(points.count == MuscleRecoveryMap.groups.count, "every group is reported")

        // A learned SHORTER recovery for legs promotes the same 1-day-ago
        // session from recovering to recovered — proving the estimate drives it.
        let fastLegs = MuscleSoreness.State(learnedHours: ["Legs": 24])
        let relearned = MuscleRecoveryMap.points(
            lastTrained: ["Legs": daysAgo(1)], soreness: fastLegs, today: today)
        #expect(relearned.first { $0.group == "Legs" }?.status == .recovered)
    }

    @Test func recoveryNeedsTheTrainingDetailBitAndRoundTrips() {
        let points = [MuscleRecoveryPoint(group: "Legs", status: .recovering, daysSince: 1),
                      MuscleRecoveryPoint(group: "Core", status: .untrained)]

        let withheld = BriefingAggregator.metrics(level: [.weight], recovery: points)
        #expect(withheld.recovery == nil)
        #expect(withheld.payload["recovery"] == nil)

        let shared = BriefingAggregator.metrics(level: [.strength], recovery: points)
        #expect(shared.recovery?.count == 2)

        let decoded = BriefingMetrics.decode(shared.payload)
        #expect(decoded.recovery?.first?.group == "Legs")
        #expect(decoded.recovery?.first?.status == .recovering)
        #expect(decoded.recovery?.first?.daysSince == 1)
        #expect(decoded.recovery?.last?.status == .untrained)
        #expect(decoded.recovery?.last?.daysSince == nil, "never-trained carries no age")
        #expect(decoded.recovery?.first?.shortAge == "1d")
    }

    // MARK: - The coach's unread mark

    private func session(_ id: String, client: String, started: Date,
                         status: SessionStatus = .completed) -> LiveWorkoutDTO {
        LiveWorkoutDTO(id: id, clientId: client, trainerId: "coach",
                       templateName: "Push", status: status,
                       startedAt: DateFormatters.iso8601.string(from: started),
                       endedAt: nil)
    }

    /// Never looked ⇒ everything shared counts as new; after opening, nothing
    /// does. Only COMPLETED sessions badge: an abandoned one isn't an
    /// achievement and a live one is already shown with a live dot.
    @Test func unseenCountsCompletedSessionsSinceTheCoachLastLooked() {
        let clientID = "client-unread-\(UUID().uuidString)"
        let now = Date()
        let sessions = [
            session("s1", client: clientID, started: now.addingTimeInterval(-3600)),
            session("s2", client: clientID, started: now.addingTimeInterval(-7200)),
            session("s3", client: clientID, started: now, status: .abandoned),
            session("s4", client: "someone-else", started: now),
        ]

        #expect(CoachSeenStore.unseenCount(for: clientID, sessions: sessions) == 2,
                "never looked: both completed sessions are new")

        CoachSeenStore.markSeen(client: clientID, at: now)
        #expect(CoachSeenStore.unseenCount(for: clientID, sessions: sessions) == 0)

        // A session finished after the visit badges again.
        let later = sessions + [session("s5", client: clientID,
                                        started: now.addingTimeInterval(60))]
        #expect(CoachSeenStore.unseenCount(for: clientID, sessions: later) == 1)
    }

    // MARK: - Plateau alerts

    private func pr(_ exercise: String, sessionsSince: Int) -> PersonalRecord {
        PersonalRecord(exercise: exercise, weightLbs: 185, reps: 5,
                       estimated1RM: 208.1, date: "2026-06-01",
                       sessionsSincePR: sessionsSince)
    }

    /// Four sessions of trying without a new best is a stall; one or two is
    /// noise. Longest stall first — that's the lift to change.
    @Test func strengthPlateauNeedsFourStaleSessionsAndRanksByLength() {
        let alerts = BriefingAggregator.strengthPlateaus([
            pr("Bench Press", sessionsSince: 4),
            pr("Overhead Press", sessionsSince: 9),
            pr("Squat", sessionsSince: 3),          // noise, not a stall
            pr("Row", sessionsSince: 0),            // just set it
        ])
        #expect(alerts.count == 2)
        #expect(alerts.first?.subject == "Overhead Press")
        #expect(alerts.first?.span == 9)
        #expect(alerts.first?.text == "Overhead Press: 9 sessions without a new best")
        #expect(!alerts.contains { $0.subject == "Squat" })
    }

    /// Flat weight is only a stall when the client is TRYING to move it.
    /// Maintaining (or no goal) means flat is the plan working.
    @Test func weightPlateauDependsOnTheGoalDirection() {
        let flat = [WeeklyPoint(weekStart: "2026-07-06", value: 180.0),
                    WeeklyPoint(weekStart: "2026-07-13", value: 180.4),
                    WeeklyPoint(weekStart: "2026-07-20", value: 180.2)]

        #expect(BriefingAggregator.weightPlateau(flat, direction: .losing)?.span == 3)
        #expect(BriefingAggregator.weightPlateau(flat, direction: .gaining) != nil)
        #expect(BriefingAggregator.weightPlateau(flat, direction: .none) == nil,
                "holding steady on purpose is not a plateau")
    }

    /// Real movement isn't a stall, and two weeks isn't enough to call one.
    @Test func weightPlateauIgnoresMovementAndShortHistory() {
        let falling = [WeeklyPoint(weekStart: "2026-07-06", value: 182.0),
                       WeeklyPoint(weekStart: "2026-07-13", value: 180.5),
                       WeeklyPoint(weekStart: "2026-07-20", value: 179.0)]
        #expect(BriefingAggregator.weightPlateau(falling, direction: .losing) == nil)

        let tooShort = Array(falling.prefix(2))
        #expect(BriefingAggregator.weightPlateau(tooShort, direction: .losing) == nil)
    }

    /// The consent rule for alerts: each is gated by the category it came
    /// from, so a plateau can never reveal a withheld category.
    @Test func plateausFollowTheirCategoryConsent() {
        let flat = [(date: day(0), lbs: 180.0), (date: day(7), lbs: 180.2),
                    (date: day(14), lbs: 180.1)]
        let records = [pr("Bench Press", sessionsSince: 6)]

        // Strength shared, weight withheld: only the lift stall crosses.
        let strengthOnly = BriefingAggregator.metrics(
            level: [.strength], trendWeights: flat, records: records,
            weightGoalDirection: .losing)
        #expect(strengthOnly.plateaus?.count == 1)
        #expect(strengthOnly.plateaus?.first?.kind == .strength)

        // Weight shared, strength withheld: only the weight stall crosses.
        let weightOnly = BriefingAggregator.metrics(
            level: [.weight], trendWeights: flat, records: records,
            weightGoalDirection: .losing)
        #expect(weightOnly.plateaus?.count == 1)
        #expect(weightOnly.plateaus?.first?.kind == .weight)

        // Neither shared: no alerts at all, and nothing on the wire.
        let neither = BriefingAggregator.metrics(
            level: [.sleep], trendWeights: flat, records: records,
            weightGoalDirection: .losing)
        #expect(neither.plateaus == nil)
        #expect(neither.payload["plateaus"] == nil)
    }

    @Test func plateausSurviveEncodeAndDecode() {
        var original = BriefingMetrics()
        original.plateaus = [PlateauAlert(kind: .strength, subject: "Squat", span: 7),
                             PlateauAlert(kind: .weight, subject: "", span: 3)]
        original.records = [pr("Squat", sessionsSince: 7)]

        let decoded = BriefingMetrics.decode(original.payload)
        #expect(decoded.plateaus?.count == 2)
        #expect(decoded.plateaus?.first?.kind == .strength)
        #expect(decoded.plateaus?.first?.subject == "Squat")
        #expect(decoded.plateaus?.first?.span == 7)
        #expect(decoded.plateaus?.last?.kind == .weight)
        // sessionsSincePR must round trip too, or the coach's client page
        // can't recompute why the alert fired.
        #expect(decoded.records?.first?.sessionsSincePR == 7)
    }

    /// A briefing whose only content is an alert must still render.
    @Test func aBriefingWithOnlyAPlateauIsNotEmpty() {
        var metrics = BriefingMetrics()
        metrics.plateaus = [PlateauAlert(kind: .weight, subject: "", span: 3)]
        let briefing = ClientBriefing(clientID: "c", summary: "", notes: [], metrics: metrics)
        #expect(!briefing.isEmpty)
    }

    // MARK: - PR ranking

    /// The best set per exercise, ranked by how central the lift is to this
    /// person's training — not by which movement happens to move the most
    /// weight. A deadlift they tried once shouldn't outrank the bench they
    /// train every week.
    @Test func recordsKeepTheBestSetAndRankByTrainingVolume() {
        func set(_ workout: Int64, _ exercise: String, _ weight: Double?, _ reps: Int?,
                 warmup: Bool = false) -> WorkoutSet {
            WorkoutSet(workoutId: workout, exerciseName: exercise, setOrder: 1,
                       weightLbs: weight, reps: reps, isWarmup: warmup)
        }
        let sets = [
            // Bench: trained 3× — the heaviest set is 185×5.
            set(1, "Bench Press", 155, 8),
            set(1, "Bench Press", 185, 5),
            set(2, "Bench Press", 175, 5),
            // Deadlift: heavier absolute load, but logged once.
            set(2, "Deadlift", 315, 3),
            // Junk that must never become a record.
            set(1, "Bench Press", nil, 5),
            set(2, "Plank", nil, nil),
        ]
        let dates: [Int64: String] = [1: "2026-07-10", 2: "2026-07-17"]

        let records = WorkoutService.personalRecords(from: sets, dateByWorkout: dates, limit: 5)
        #expect(records.count == 2, "Plank has no weight/reps, so it has no record")
        #expect(records.first?.exercise == "Bench Press", "3 sets beats 1, whatever the load")
        #expect(records.first?.weightLbs == 185)
        #expect(records.first?.reps == 5)
        #expect(records.first?.date == "2026-07-10", "the date of the PR set's workout")
        #expect(records.last?.exercise == "Deadlift")
    }

    @Test func recordsRespectTheLimitAndSkipWarmups() {
        let sets = (1...8).map { i in
            WorkoutSet(workoutId: 1, exerciseName: "Lift \(i)", setOrder: 1,
                       weightLbs: 100, reps: 5)
        } + [WorkoutSet(workoutId: 1, exerciseName: "Warmup Only", setOrder: 1,
                        weightLbs: 45, reps: 10, isWarmup: true)]

        // The DB query filters warmups; the ranking is handed only working
        // sets, so a warmup-only exercise simply never appears.
        let working = sets.filter { !$0.isWarmup }
        let records = WorkoutService.personalRecords(from: working, dateByWorkout: [:], limit: 3)
        #expect(records.count == 3)
        #expect(!records.contains { $0.exercise == "Warmup Only" })
    }

    // MARK: - Coach memory

    /// The returning-user path: the coach should ask how the last program went,
    /// not offer to build the same thing again.
    @Test func theCoachRemembersWhatItRecommended() {
        var notes = CoachNotes()
        #expect(notes.returningGreeting == nil, "no history, so no callback")

        notes.recordProgram(["Upper Body A", "Lower Body A"])
        let greeting = notes.returningGreeting
        #expect(greeting?.contains("Upper Body A") == true)
        #expect(greeting?.contains("Lower Body A") == true)
        #expect(notes.lastProgramNames.count == 2)
        #expect(notes.notes.contains { $0.kind == .observation },
                "and it lands in the shareable note log too")
    }
}
