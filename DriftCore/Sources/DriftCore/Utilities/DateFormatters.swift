import Foundation

public enum DateFormatters {
    /// Every formatter below represents a **local calendar day or wall time** —
    /// "the day the user logged this", not an absolute instant. Apple's
    /// `DateFormatter` already defaults to the system zone, but Android's
    /// Foundation defaults to **UTC**, so leaving `timeZone` unset made the
    /// `Date -> string -> Date` round trip lose a day there: parsing today's own
    /// `todayString` came back as *yesterday* whenever local time is behind UTC
    /// (all of the Americas), because `Calendar.current` then read that UTC
    /// midnight in local time. That silently bucketed workouts logged today into
    /// last week ("0 this week" with three workouts logged — #1076) and would
    /// have filed any evening food entry under tomorrow's date.
    ///
    /// Pinning the zone explicitly makes both platforms agree. It is a no-op on
    /// iOS (this is already the default) per directive 0-IOS-GUARD, and
    /// `autoupdatingCurrent` keeps these long-lived statics following a
    /// timezone change the way the unset default did.
    ///
    /// `sqliteDatetime` and `iso8601` are deliberately excluded: those encode
    /// absolute instants and are correctly UTC.
    private static let localZone = TimeZone.autoupdatingCurrent

    /// "YYYY-MM-DD" for database date columns.
    public static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = localZone
        return f
    }()

    /// ISO 8601 for timestamps.
    public nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Display format: "Mar 28"
    public static let shortDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = localZone
        return f
    }()

    /// Display format: "Sat, Mar 28"
    public static let dayDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E, MMM d"
        f.timeZone = localZone
        return f
    }()

    /// Display format: "Monday, Jul 20" — the workout-detail header.
    public static let longDayDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d, yyyy"
        f.timeZone = localZone
        return f
    }()

    /// Display format: "March 2026"
    public static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        f.timeZone = localZone
        return f
    }()

    /// Short time display: "8:30 AM"
    public static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = localZone
        return f
    }()

    /// SQLite datetime format: "YYYY-MM-DD HH:MM:SS"
    public static let sqliteDatetime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Today's date as "YYYY-MM-DD".
    public static var todayString: String {
        dateOnly.string(from: Date())
    }
}
