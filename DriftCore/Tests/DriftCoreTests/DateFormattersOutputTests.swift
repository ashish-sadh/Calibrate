import Foundation
@testable import DriftCore
import Testing

@Suite struct DateFormattersOutputTests {
    @Test func dateDisplayFormattersMatchDocumentedOutput() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 28
        components.hour = 20
        components.minute = 30
        let date = try #require(Calendar.autoupdatingCurrent.date(from: components))

        #expect(DateFormatters.shortDisplay.string(from: date) == "Mar 28")
        #expect(DateFormatters.dayDisplay.string(from: date) == "Sat, Mar 28")
        #expect(DateFormatters.longDayDisplay.string(from: date) == "Saturday, Mar 28, 2026")
        #expect(DateFormatters.monthYear.string(from: date) == "March 2026")
    }

    @Test func shortTimeMatchesDocumentedTwelveHourOutput() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 28
        components.hour = 20
        components.minute = 30
        let date = try #require(Calendar.autoupdatingCurrent.date(from: components))

        #expect(DateFormatters.shortTime.string(from: date) == "8:30 PM")
    }

    @Test func sqliteDatetimeSerializesKnownInstantInUTC() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let date = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 28,
            hour: 20,
            minute: 30,
            second: 45
        )))

        #expect(DateFormatters.sqliteDatetime.string(from: date) == "2026-03-28 20:30:45")
    }

    @Test func iso8601RoundTripsKnownInstant() throws {
        let timestamp = "2026-03-28T20:30:45Z"
        let date = try #require(DateFormatters.iso8601.date(from: timestamp))

        #expect(DateFormatters.iso8601.string(from: date) == timestamp)
    }
}
