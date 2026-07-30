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
    /// Uses `entry.date` — the DIARY day the food belongs to — not `loggedAt`.
    ///
    /// The first version parsed `loggedAt`, a timestamp, through two formatters
    /// and DROPPED any entry that matched neither. Older rows (imports, earlier
    /// schema versions, anything with an empty or differently-shaped timestamp)
    /// silently vanished, so a real streak running since April reported 27 days
    /// — it stopped exactly where the parseable timestamps stopped. A `compactMap`
    /// that discards unparseable input is invisible until someone's history is
    /// older than the format.
    ///
    /// `date` is already `yyyy-MM-dd`, needs no parsing, cannot fail, and is what
    /// the query filters on anyway. It's also the honest definition: a
    /// food-logging streak is about which days have food logged, not which days
    /// you happened to open the app — someone back-filling last night's dinner
    /// this morning should not break their own streak.
    ///
    /// Parsing nothing also removes the timezone hazard: an unpinned formatter
    /// is UTC on Android, so a date-only round trip could shift a day.
    public static func mine(today: Date = Date()) -> Int {
        let since = Calendar.current.date(byAdding: .day, value: -400, to: today)
        let from = since.map { DateFormatters.dateOnly.string(from: $0) }
        guard let entries = try? AppDatabase.shared.fetchFoodEntries(fromDate: from) else { return 0 }
        // `date` is optional on the model; an entry without one has no day to
        // count, but it must not stop the scan the way a parse failure did.
        return current(loggedDays: Set(entries.compactMap(\.date)), today: today)
    }
}
