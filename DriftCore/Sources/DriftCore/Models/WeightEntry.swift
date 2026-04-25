import Foundation
import GRDB

public struct WeightEntry: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var date: String           // "YYYY-MM-DD"
    public var weightKg: Double
    public var source: String         // "manual" | "healthkit"
    public var createdAt: String
    public var syncedFromHk: Bool
    public var bodyFatPct: Double?    // 0-100, optional
    public var bmi: Double?           // e.g. 22.5, optional
    public var waterPct: Double?      // 0-100, optional
    public var hidden: Bool = false   // soft-delete: hidden entries aren't shown but block HealthKit re-sync

    enum CodingKeys: String, CodingKey {
        case id, date, source, bmi, hidden
        case weightKg = "weight_kg"
        case createdAt = "created_at"
        case syncedFromHk = "synced_from_hk"
        case bodyFatPct = "body_fat_pct"
        case waterPct = "water_pct"
    }

    public init(
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
    public var weightLbs: Double { weightKg * 2.20462 }

    /// Whether this entry has any body composition data.
    public var hasBodyComposition: Bool { bodyFatPct != nil || bmi != nil || waterPct != nil }
}

extension WeightEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "weight_entry"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
