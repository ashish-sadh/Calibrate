import Foundation
import GRDB

public struct Supplement: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var name: String
    public var dosage: String?
    public var unit: String?
    public var isActive: Bool
    public var sortOrder: Int
    public var dailyDoses: Int
    public var reminderTime: String?  // "HH:mm" or nil

    enum CodingKeys: String, CodingKey {
        case id, name, dosage, unit
        case isActive = "is_active"
        case sortOrder = "sort_order"
        case dailyDoses = "daily_doses"
        case reminderTime = "reminder_time"
    }

    public init(
        id: Int64? = nil, name: String, dosage: String? = nil, unit: String? = nil,
        isActive: Bool = true, sortOrder: Int = 0, dailyDoses: Int = 1, reminderTime: String? = nil
    ) {
        self.id = id; self.name = name; self.dosage = dosage; self.unit = unit
        self.isActive = isActive; self.sortOrder = sortOrder
        self.dailyDoses = dailyDoses; self.reminderTime = reminderTime
    }

    public var dosageDisplay: String {
        guard let dosage, let unit else { return "" }
        let freq = dailyDoses > 1 ? " × \(dailyDoses)/day" : ""
        return "\(dosage) \(unit)\(freq)"
    }
}

extension Supplement: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "supplement"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
