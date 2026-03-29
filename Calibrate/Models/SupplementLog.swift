import Foundation
import GRDB

struct SupplementLog: Identifiable, Codable, Sendable {
    var id: Int64?
    var supplementId: Int64
    var date: String         // "YYYY-MM-DD"
    var taken: Bool
    var takenAt: String?     // ISO 8601 datetime
    var notes: String?

    init(
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
    static let databaseTableName = "supplement_log"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
