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
