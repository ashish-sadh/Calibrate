import Foundation
import GRDB

public struct MealLog: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var date: String         // "YYYY-MM-DD"
    public var mealType: String     // "breakfast" | "lunch" | "dinner" | "snack"
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, date
        case mealType = "meal_type"
        case createdAt = "created_at"
    }

    public init(
        id: Int64? = nil,
        date: String,
        mealType: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.date = date
        self.mealType = mealType
        self.createdAt = createdAt
    }
}

extension MealLog: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "meal_log"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum MealType: String, CaseIterable, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    public var displayName: String {
        rawValue.capitalized
    }

    public var icon: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "cup.and.saucer"
        }
    }

    /// Resolve meal type from recent logs + current time.
    /// If the most recent entry is within `inheritWindow` of `now` AND its meal type is
    /// breakfast/lunch/dinner, inherit it — lets a second bowl at 10am after a 7am breakfast
    /// stay `breakfast`. Otherwise fall back to hour ranges.
    public static func resolve(now: Date = Date(), recentEntries: [FoodEntry],
                        inheritWindow: TimeInterval = 3 * 3600) -> MealType {
        let iso = DateFormatters.iso8601
        let sqlite = DateFormatters.sqliteDatetime
        let sorted = recentEntries.compactMap { entry -> (FoodEntry, Date)? in
            guard let d = iso.date(from: entry.loggedAt) ?? sqlite.date(from: entry.loggedAt) else { return nil }
            return (entry, d)
        }.sorted { $0.1 > $1.1 }

        if let (prev, prevDate) = sorted.first {
            let delta = now.timeIntervalSince(prevDate)
            if delta >= 0, delta < inheritWindow,
               let rawType = prev.mealType,
               let meal = MealType(rawValue: rawType),
               meal != .snack {
                return meal
            }
        }

        let hour = Calendar.current.component(.hour, from: now)
        switch hour {
        case 5..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<21: return .dinner
        default: return .snack
        }
    }

    /// Detect meal type from hour alone (no recent-entry inheritance).
    /// Used by AI chat parser when user doesn't specify a meal keyword.
    /// Ranges: 5–10 breakfast, 10–15 lunch, 15–18 snack, 18–22 dinner, else snack.
    public static func fromHour(_ hour: Int = Calendar.current.component(.hour, from: Date())) -> MealType {
        switch hour {
        case 5..<10: return .breakfast
        case 10..<15: return .lunch
        case 15..<18: return .snack
        case 18..<22: return .dinner
        default: return .snack
        }
    }
}
