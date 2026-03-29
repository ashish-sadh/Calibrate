import Foundation

enum DateFormatters {
    /// "YYYY-MM-DD" for database date columns.
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// ISO 8601 for timestamps.
    nonisolated(unsafe) static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Display format: "Mar 28"
    static let shortDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// Display format: "Sat, Mar 28"
    static let dayDisplay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "E, MMM d"
        return f
    }()

    /// Display format: "March 2026"
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// Today's date as "YYYY-MM-DD".
    static var todayString: String {
        dateOnly.string(from: Date())
    }
}
