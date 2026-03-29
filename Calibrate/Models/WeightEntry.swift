import Foundation
import GRDB

struct WeightEntry: Identifiable, Codable, Sendable {
    var id: Int64?
    var date: String           // "YYYY-MM-DD"
    var weightKg: Double
    var source: String         // "manual" | "healthkit"
    var createdAt: String
    var syncedFromHk: Bool

    init(
        id: Int64? = nil,
        date: String,
        weightKg: Double,
        source: String = "manual",
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        syncedFromHk: Bool = false
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.source = source
        self.createdAt = createdAt
        self.syncedFromHk = syncedFromHk
    }

    /// Weight in lbs.
    var weightLbs: Double { weightKg * 2.20462 }
}

extension WeightEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "weight_entry"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
