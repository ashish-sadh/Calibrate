import Foundation
import DriftCore

@MainActor
public enum FoodTimingInsightTool {

    nonisolated static let toolName = "food_timing_insight"

    static func syncRegistration(registry: ToolRegistry = .shared) {
        registry.register(schema)
    }

    static var schema: ToolSchema {
        ToolSchema(
            id: "insights.food_timing_insight",
            name: toolName,
            service: "insights",
            description: "User asks about meal timing patterns — 'when do I usually eat?', 'what time is my first meal?', 'do I eat late at night?', 'what's my eating window?'.",
            parameters: [
                ToolParam("window_days", "number", "Lookback window in days (default 14)", required: false)
            ],
            handler: { params in
                let window = max(7, min(30, params.int("window_days") ?? 14))
                return .text(run(windowDays: window))
            }
        )
    }

    // MARK: - Entry point

    public static func run(windowDays: Int) -> String {
        let (startStr, endStr) = dateWindow(windowDays: windowDays)
        let dates = datesInRange(startDate: startStr, endDate: endStr)
        var allEntries: [FoodEntry] = []
        for date in dates {
            allEntries.append(contentsOf: (try? AppDatabase.shared.fetchFoodEntries(for: date)) ?? [])
        }
        guard !allEntries.isEmpty else {
            return "No food logged in the last \(windowDays) days."
        }
        let stats = timingStats(entries: allEntries)
        return formatResult(stats: stats, windowDays: windowDays)
    }

    // MARK: - Pure stats (testable)

    public struct MealTimingStats: Sendable {
        public let avgBreakfastHour: Double?
        public let avgLunchHour: Double?
        public let avgDinnerHour: Double?
        public let lateNightDays: Int
        public let totalLoggedDays: Int
        public let lateNightPct: Int
        public let earliestMealHour: Double?
        public let latestMealHour: Double?
    }

    nonisolated public static func timingStats(entries: [FoodEntry]) -> MealTimingStats {
        var mealHours: [String: [Double]] = ["breakfast": [], "lunch": [], "dinner": [], "snack": []]
        var lateNightDays = Set<String>()
        var loggedDays = Set<String>()
        var allHours: [Double] = []

        for entry in entries {
            guard let hour = parseLocalHour(entry.loggedAt) else { continue }
            let dateKey = String(entry.loggedAt.prefix(10))
            loggedDays.insert(dateKey)
            allHours.append(hour)
            if hour >= 21.0 { lateNightDays.insert(dateKey) }
            let meal = (entry.mealType ?? "").lowercased()
            if mealHours[meal] != nil { mealHours[meal]!.append(hour) }
        }

        func avg(_ arr: [Double]) -> Double? { arr.isEmpty ? nil : arr.reduce(0, +) / Double(arr.count) }

        let total = loggedDays.count
        let lateCount = lateNightDays.count
        let latePct = total > 0 ? Int(Double(lateCount) / Double(total) * 100) : 0

        // Crash-audit (2026-05-20): dict bangs on `mealHours[key]!`
        // were guaranteed safe at init time (the dict is seeded with
        // these 4 keys on line 59) but fragile — if a refactor swaps
        // the init shape, the bangs would crash on the first user
        // who triggers this tool. Nil-coalesce is the same cost.
        return MealTimingStats(
            avgBreakfastHour: avg(mealHours["breakfast"] ?? []),
            avgLunchHour: avg(mealHours["lunch"] ?? []),
            avgDinnerHour: avg(mealHours["dinner"] ?? []),
            lateNightDays: lateCount,
            totalLoggedDays: total,
            lateNightPct: latePct,
            earliestMealHour: allHours.min(),
            latestMealHour: allHours.max()
        )
    }

    /// Parse the local-time hour from an ISO 8601 timestamp stored in the DB.
    /// Uses Calendar.current so the result reflects the user's timezone.
    nonisolated public static func parseLocalHour(_ loggedAt: String) -> Double? {
        guard let date = DateFormatters.iso8601.date(from: loggedAt) else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = comps.hour, let minute = comps.minute else { return nil }
        return Double(hour) + Double(minute) / 60.0
    }

    // MARK: - Formatting

    nonisolated static func formatHour(_ h: Double) -> String {
        let totalMinutes = Int((h * 60).rounded())
        let hr = (totalMinutes / 60) % 24
        let min = totalMinutes % 60
        let suffix = hr >= 12 ? "PM" : "AM"
        let displayHr = hr > 12 ? hr - 12 : (hr == 0 ? 12 : hr)
        return String(format: "%d:%02d %@", displayHr, min, suffix)
    }

    nonisolated static func formatResult(stats: MealTimingStats, windowDays: Int) -> String {
        var lines: [String] = ["Meal timing (\(windowDays)d, \(stats.totalLoggedDays) days logged):"]
        if let b = stats.avgBreakfastHour { lines.append("Avg breakfast: \(formatHour(b))") }
        if let l = stats.avgLunchHour     { lines.append("Avg lunch: \(formatHour(l))") }
        if let d = stats.avgDinnerHour    { lines.append("Avg dinner: \(formatHour(d))") }
        if let e = stats.earliestMealHour, let l = stats.latestMealHour {
            lines.append("Eating window: \(formatHour(e)) – \(formatHour(l))")
        }
        if stats.lateNightDays > 0 {
            lines.append("Late-night eating (after 9pm): \(stats.lateNightDays) day\(stats.lateNightDays == 1 ? "" : "s") (\(stats.lateNightPct)%)")
            if stats.lateNightPct >= 50 {
                lines.append("Tip: try finishing meals by 8pm — late-night eating is linked to poorer sleep quality.")
            }
        } else {
            lines.append("No late-night eating detected.")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Date helpers

    nonisolated static func dateWindow(windowDays: Int, now: Date = Date()) -> (start: String, end: String) {
        let cal = Calendar.current
        let start = cal.date(byAdding: .day, value: -(windowDays - 1), to: now) ?? now
        let fmt = DateFormatters.dateOnly
        return (fmt.string(from: start), fmt.string(from: now))
    }

    nonisolated static func datesInRange(startDate: String, endDate: String) -> [String] {
        let fmt = DateFormatters.dateOnly
        guard let start = fmt.date(from: startDate), let end = fmt.date(from: endDate) else { return [] }
        var out: [String] = []
        var cur = start
        let cal = Calendar.current
        while cur <= end {
            out.append(fmt.string(from: cur))
            guard let next = cal.date(byAdding: .day, value: 1, to: cur) else { break }
            cur = next
        }
        return out
    }
}
