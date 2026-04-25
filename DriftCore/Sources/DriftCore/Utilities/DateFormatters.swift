import Foundation

public enum DateFormatters {
    /// "YYYY-MM-DD" for database date columns.
    public static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
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
        return f
    }()

    /// Display format: "Sat, Mar 28"
    public static let dayDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E, MMM d"
        return f
    }()

    /// Display format: "March 2026"
    public static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Short time display: "8:30 AM"
    public static let shortTime: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
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
