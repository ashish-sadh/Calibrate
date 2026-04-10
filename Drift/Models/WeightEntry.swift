import Foundation
import GRDB

struct WeightEntry: Identifiable, Codable, Sendable {
    var id: Int64?
    var date: String           // "YYYY-MM-DD"
    var weightKg: Double
    var source: String         // "manual" | "healthkit"
    var createdAt: String
    var syncedFromHk: Bool
    var bodyFatPct: Double?    // 0-100, optional
    var bmi: Double?           // e.g. 22.5, optional
    var waterPct: Double?      // 0-100, optional
    var hidden: Bool = false   // soft-delete: hidden entries aren't shown but block HealthKit re-sync

    enum CodingKeys: String, CodingKey {
        case id, date, source, bmi, hidden
        case weightKg = "weight_kg"
        case createdAt = "created_at"
        case syncedFromHk = "synced_from_hk"
        case bodyFatPct = "body_fat_pct"
        case waterPct = "water_pct"
    }

    init(
        id: Int64? = nil,
        date: String,
        weightKg: Double,
        source: String = "manual",
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        syncedFromHk: Bool = false,
        bodyFatPct: Double? = nil,
        bmi: Double? = nil,
        waterPct: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.weightKg = weightKg
        self.source = source
        self.createdAt = createdAt
        self.syncedFromHk = syncedFromHk
        self.bodyFatPct = bodyFatPct
        self.bmi = bmi
        self.waterPct = waterPct
    }

    /// Weight in lbs.
    var weightLbs: Double { weightKg * 2.20462 }

    /// Whether this entry has any body composition data.
    var hasBodyComposition: Bool { bodyFatPct != nil || bmi != nil || waterPct != nil }
}

extension WeightEntry: FetchableRecord, PersistableRecord {
    static let databaseTableName = "weight_entry"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
