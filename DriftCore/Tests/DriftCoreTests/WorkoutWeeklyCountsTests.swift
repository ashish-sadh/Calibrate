import Foundation
@testable import DriftCore
import Testing
import GRDB

// Tier-0: DB-backed but deterministic — no LLM, no network.
//
// `weeklyWorkoutCounts` shipped with ZERO coverage, which is how the ordering
// contract broke unnoticed: the builder walks `(0..<weeks)` as offsets BACK from
// the current week and then `.reversed()` the result, so the array is
// **oldest → newest** and the CURRENT week is `.last`, not `.first`.
// `WorkoutView.consistencyChart` read `.first` and therefore rendered the week
// from 11 weeks ago as "this week" — a workout logged today showed "0 this week"
// (#1076, live on Android build 21 and equally wrong on iOS).
//
// `streak(fromWeeklyCounts:)` already documents the same oldest→newest ordering,
// so these tests pin the contract both consumers depend on.
//
// `WorkoutService.db` is `AppDatabase.shared`, a real file shared by parallel
// tests, so fixtures use a UUID-suffixed name and are deleted afterwards, and
// the count assertions are `>=` on the buckets they own rather than exact totals.

@discardableResult
private func seedWorkoutDated(_ date: String, exercise: String) throws -> Int64 {
    try AppDatabase.shared.writer.write { dbConn in
        let workout = Workout(name: "WeeklyCountsFixture", date: date,
                              durationSeconds: 60, createdAt: "\(date)T10:00:00Z")
        try workout.insert(dbConn)
        let workoutId = dbConn.lastInsertedRowID
        let set = WorkoutSet(workoutId: workoutId, exerciseName: exercise, setOrder: 1,
                             weightLbs: 135, reps: 10, isWarmup: false)
        try set.insert(dbConn)
        return workoutId
    }
}

private func deleteWorkoutById(_ id: Int64) {
    try? AppDatabase.shared.writer.write { dbConn in
        try WorkoutSet.filter(Column("workout_id") == id).deleteAll(dbConn)
        try Workout.filter(Column("id") == id).deleteAll(dbConn)
    }
}

/// The array runs oldest → newest, so the CURRENT week is the last element.
@Test func weeklyCountsAreOrderedOldestToNewest() throws {
    let counts = try WorkoutService.weeklyWorkoutCounts(weeks: 12)
    #expect(counts.count == 12)

    let cal = Calendar.current
    guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start else {
        Issue.record("no current week interval")
        return
    }
    #expect(counts.last?.weekStart == currentWeekStart,
            "the CURRENT week must be the last element (oldest→newest ordering)")
    #expect(counts.first?.weekStart == cal.date(byAdding: .weekOfYear, value: -11, to: currentWeekStart),
            "the FIRST element is 11 weeks ago, not this week")

    // Strictly increasing — no duplicate or out-of-order buckets.
    for (earlier, later) in zip(counts, counts.dropFirst()) {
        #expect(earlier.weekStart < later.weekStart)
    }
}

/// A workout logged TODAY lands in the last bucket. This is the exact defect the
/// "0 this week" card showed: `.first` is a bucket from 11 weeks ago.
@Test func workoutLoggedTodayCountsInTheCurrentWeekBucket() throws {
    let exercise = "WeeklyCounts Bench \(UUID().uuidString.prefix(6))"
    let id = try seedWorkoutDated(DateFormatters.todayString, exercise: exercise)
    defer { deleteWorkoutById(id) }

    let counts = try WorkoutService.weeklyWorkoutCounts(weeks: 12)
    #expect((counts.last?.count ?? 0) >= 1,
            "today's workout must be counted in the current (last) week bucket")

    // And the single-week call — TodayTab asks for weeks: 1 — must describe the
    // SAME bucket. Only the weekStart is compared: `AppDatabase.shared` is a real
    // file and Swift Testing runs in parallel, so other suites' workout fixtures
    // move the count between these two reads (seen live as 29 vs 31).
    let oneWeek = try WorkoutService.weeklyWorkoutCounts(weeks: 1)
    #expect(oneWeek.count == 1)
    #expect(oneWeek.last?.weekStart == counts.last?.weekStart,
            "weeks:1 must report the same current-week bucket as weeks:12")
    #expect((oneWeek.last?.count ?? 0) >= 1,
            "weeks:1 must also see today's workout — this is the TodayTab path")
}

// MARK: - startOfWeek
//
// THE Android failure mode (#1076): a workout's date parses to midnight while
// `now` carries a time of day, and Android's
// `Calendar.dateInterval(of: .weekOfYear, for:)` returned a different bucket for
// the two — so a workout logged today was counted in an older week and every
// "this week" counter read 0 while the 12-week total stayed correct. These pin
// the property that broke, so it cannot regress on either platform.

/// Same calendar day ⇒ same week start, whatever the time of day.
@Test func startOfWeekIgnoresTimeOfDay() {
    let cal = Calendar.current
    let midnight = cal.startOfDay(for: Date())
    let times = [0, 1, 6 * 3600, 13 * 3600 + 27 * 60, 23 * 3600 + 59 * 60]

    let expected = WorkoutService.startOfWeek(for: midnight, calendar: cal)
    for seconds in times {
        let sameDay = midnight.addingTimeInterval(TimeInterval(seconds))
        #expect(WorkoutService.startOfWeek(for: sameDay, calendar: cal) == expected,
                "time of day (+\(seconds)s) must not change the week bucket")
    }
}

/// The week start is midnight, on or before the date, within the last 7 days,
/// and lands on the calendar's configured first weekday.
@Test func startOfWeekIsNormalizedAndAligned() {
    let cal = Calendar.current
    for dayOffset in 0..<14 {
        guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
        let start = WorkoutService.startOfWeek(for: date, calendar: cal)

        #expect(start == cal.startOfDay(for: start), "week start must be midnight")
        #expect(start <= cal.startOfDay(for: date), "week start cannot be after its date")
        #expect(cal.component(.weekday, from: start) == cal.firstWeekday,
                "week start must land on the calendar's first weekday")

        let days = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: date)).day
        #expect((days ?? -1) >= 0 && (days ?? 7) < 7, "week start must be within 7 days")
    }
}

/// Consecutive weeks bucket into consecutive slots — a workout dated 7 days
/// before the current week's start belongs one slot earlier, not the same one.
@Test func workoutFromLastWeekLandsInThePreviousBucket() throws {
    let cal = Calendar.current
    let currentWeekStart = WorkoutService.startOfWeek(for: Date(), calendar: cal)
    guard let lastWeek = cal.date(byAdding: .day, value: -7, to: currentWeekStart) else {
        Issue.record("could not build last week's date")
        return
    }

    let exercise = "WeeklyCounts LastWeek \(UUID().uuidString.prefix(6))"
    let id = try seedWorkoutDated(DateFormatters.dateOnly.string(from: lastWeek), exercise: exercise)
    defer { deleteWorkoutById(id) }

    let counts = try WorkoutService.weeklyWorkoutCounts(weeks: 12)
    #expect(counts.count == 12)
    #expect(counts[counts.count - 2].weekStart == lastWeek)
    #expect(counts[counts.count - 2].count >= 1,
            "a workout dated last week belongs in the second-to-last bucket")
}
