import Foundation

/// How many days in a row someone has logged food.
///
/// The metric almost everyone has. Steps need a phone in your pocket, lifts need
/// a barbell and a friend who trains the same one — but anyone who has opened
/// Drift twice has a streak, which is what makes it the board that actually
/// populates (operator 2026-07-30: "at least they will show up as one for most
/// people who have tried, and for some it will be 90-100 days").
public enum FoodLoggingStreak {

    /// Consecutive days ending TODAY or YESTERDAY, counting back.
    ///
    /// Yesterday counts as still-alive on purpose: someone who logs dinner every
    /// night shouldn't watch their streak read zero every morning until they eat.
    /// A streak that resets at midnight punishes people for sleeping.
    ///
    /// Returns 0 when the last log is older than yesterday — broken is broken,
    /// and inflating it would make the number meaningless to compare.
    public static func current(loggedDays: Set<String>,
                              today: Date = Date(),
                              calendar: Calendar = .current) -> Int {
        let fmt = DateFormatters.dateOnly
        guard !loggedDays.isEmpty else { return 0 }

        // Anchor on today if it's logged, else yesterday. Anything older means
        // the streak is over.
        var cursor = today
        if !loggedDays.contains(fmt.string(from: cursor)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor),
                  loggedDays.contains(fmt.string(from: yesterday)) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        // Bounded: a decade is far past any real streak, and an unbounded loop
        // over a corrupt date set would spin forever.
        while streak < 3_650, loggedDays.contains(fmt.string(from: cursor)) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }

    /// The caller's own streak, from the local food log.
    ///
    /// Reads a year of entries — enough for any streak worth showing, and
    /// bounded so this stays cheap on the publish path.
    public static func mine(today: Date = Date()) -> Int {
        let since = Calendar.current.date(byAdding: .day, value: -365, to: today)
        let from = since.map { DateFormatters.dateOnly.string(from: $0) }
        guard let entries = try? AppDatabase.shared.fetchFoodEntries(fromDate: from) else { return 0 }
        // `loggedAt` is a timestamp; the streak is about DAYS.
        let days = Set(entries.compactMap { entry -> String? in
            guard let when = DateFormatters.iso8601.date(from: entry.loggedAt)
                ?? DateFormatters.sqliteDatetime.date(from: entry.loggedAt) else { return nil }
            return DateFormatters.dateOnly.string(from: when)
        })
        return current(loggedDays: days, today: today)
    }
}
