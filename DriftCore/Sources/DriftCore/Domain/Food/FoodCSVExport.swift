import Foundation

/// A food entry paired with the day it belongs to. The day is resolved at fetch
/// time: `food_entry.date` when the row has one, else the parent meal_log's date
/// (pre-v26 rows), else the date part of `logged_at`.
public struct FoodExportRow: Sendable {
    public let date: String
    public let entry: FoodEntry

    public init(date: String, entry: FoodEntry) {
        self.date = date
        self.entry = entry
    }
}

/// CSV rendering for "Export Food Logs". Pure — the caller owns the fetch and the
/// file write, so the whole format is testable without a database or a share sheet.
public enum FoodCSVExport {
    public static let header = "Date,Time,Food,Calories,Protein,Carbs,Fat,Fiber,Servings\n"

    public static func csv(rows: [FoodExportRow]) -> String {
        rows.reduce(into: header) { $0 += line(for: $1) }
    }

    private static func line(for row: FoodExportRow) -> String {
        let e = row.entry
        let name = e.foodName.replacingOccurrences(of: "\"", with: "\"\"")
        let time = (DateFormatters.iso8601.date(from: e.loggedAt) ?? DateFormatters.sqliteDatetime.date(from: e.loggedAt))
            .map { DateFormatters.shortTime.string(from: $0) } ?? ""
        return "\"\(row.date)\",\"\(time)\",\"\(name)\","
            + "\(Int(e.totalCalories)),\(Int(e.totalProtein)),\(Int(e.totalCarbs)),"
            + "\(Int(e.totalFat)),\(Int(e.totalFiber)),\(String(format: "%.1f", e.servings))\n"
    }
}
