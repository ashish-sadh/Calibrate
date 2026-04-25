import Foundation
import GRDB

public struct SupplementLog: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var supplementId: Int64
    public var date: String         // "YYYY-MM-DD"
    public var taken: Bool
    public var takenAt: String?     // ISO 8601 datetime
    public var notes: String?

    enum CodingKeys: String, CodingKey {
        case id, date, taken, notes
        case supplementId = "supplement_id"
        case takenAt = "taken_at"
    }

    public init(
        id: Int64? = nil,
        supplementId: Int64,
        date: String,
        taken: Bool = false,
        takenAt: String? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.supplementId = supplementId
        self.date = date
        self.taken = taken
        self.takenAt = takenAt
        self.notes = notes
    }
}

extension SupplementLog: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "supplement_log"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
