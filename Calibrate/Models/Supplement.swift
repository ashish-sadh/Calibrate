import Foundation
import GRDB

struct Supplement: Identifiable, Codable, Sendable {
    var id: Int64?
    var name: String
    var dosage: String?
    var unit: String?
    var isActive: Bool
    var sortOrder: Int

    init(
        id: Int64? = nil,
        name: String,
        dosage: String? = nil,
        unit: String? = nil,
        isActive: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.unit = unit
        self.isActive = isActive
        self.sortOrder = sortOrder
    }

    var dosageDisplay: String {
        guard let dosage, let unit else { return "" }
        return "\(dosage) \(unit)"
    }
}

extension Supplement: FetchableRecord, PersistableRecord {
    static let databaseTableName = "supplement"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
