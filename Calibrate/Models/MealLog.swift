import Foundation
import GRDB

struct MealLog: Identifiable, Codable, Sendable {
    var id: Int64?
    var date: String         // "YYYY-MM-DD"
    var mealType: String     // "breakfast" | "lunch" | "dinner" | "snack"
    var createdAt: String

    init(
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
    static let databaseTableName = "meal_log"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

enum MealType: String, CaseIterable, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "cup.and.saucer"
        }
    }
}
