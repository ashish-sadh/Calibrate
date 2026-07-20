import Foundation
@testable import DriftCore
import Testing

// Tier-0: pure formatter contract — no DB, no LLM, no network.
//
// `dateOnly` is the format of every date column that means "the local calendar
// day the user did this". It set a locale but no `timeZone`, which is harmless
// on Apple (DateFormatter already defaults to the system zone) and wrong on
// Android, whose Foundation defaults to UTC. That made the round trip
// `Date -> string -> Date` lose a day for any local zone behind UTC: the string
// said "today", but re-parsing it produced UTC midnight, which `Calendar.current`
// read back as *yesterday*.
//
// It surfaced as "0 this week" on a device with three workouts logged (#1076):
// today's workouts bucketed into the previous week. The same shift would have
// filed an evening food entry under tomorrow's date.
//
// These pin the invariant the platforms disagreed on. They pass on macOS/iOS
// either way — their job is to fail loudly if the explicit zone is ever dropped
// and to document why it is there.
@Suite struct DateFormattersRoundTripTests {

    /// The bug, reduced: format now, parse it back, and the calendar must agree
    /// it is still the same day.
    @Test func todayStringParsesBackToToday() {
        let cal = Calendar.current
        let parsed = DateFormatters.dateOnly.date(from: DateFormatters.todayString)
        #expect(parsed != nil)
        guard let parsed else { return }

        let dayDelta = cal.dateComponents([.day],
                                          from: cal.startOfDay(for: parsed),
                                          to: cal.startOfDay(for: Date())).day
        #expect(dayDelta == 0, "round trip drifted by \(dayDelta ?? -999) day(s)")
    }

    /// The round trip has to hold at every hour, not just the ones where local
    /// time and UTC happen to land on the same date. Late-evening instants are
    /// exactly where an unpinned formatter diverges.
    @Test func roundTripHoldsAcrossTheWholeDay() {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: Date())

        for hour in 0..<24 {
            guard let instant = cal.date(byAdding: .hour, value: hour, to: midnight) else { continue }
            let string = DateFormatters.dateOnly.string(from: instant)
            guard let parsed = DateFormatters.dateOnly.date(from: string) else {
                Issue.record("hour \(hour): \(string) failed to parse")
                continue
            }
            #expect(cal.isDate(parsed, inSameDayAs: instant),
                    "hour \(hour): \(string) parsed back to a different day")
        }
    }

    /// `dateOnly` must read a stored date as a LOCAL day. Pinning the zone is the
    /// fix, so assert the property rather than the implementation detail.
    @Test func storedDateStringIsInterpretedAsALocalDay() {
        let cal = Calendar.current
        guard let parsed = DateFormatters.dateOnly.date(from: "2026-07-20") else {
            Issue.record("2026-07-20 failed to parse")
            return
        }
        let parts = cal.dateComponents([.year, .month, .day], from: parsed)
        #expect(parts.year == 2026)
        #expect(parts.month == 7)
        #expect(parts.day == 20)
    }

    /// Timestamps are a different contract: `sqliteDatetime` encodes an absolute
    /// instant and is deliberately UTC. Guard it so a future "fix everything to
    /// local" sweep doesn't rewrite stored timestamps.
    @Test func sqliteDatetimeStaysUTC() {
        #expect(DateFormatters.sqliteDatetime.timeZone == TimeZone(identifier: "UTC"))
    }
}
