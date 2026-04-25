import Foundation
import GRDB

public struct BodyComposition: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var date: String            // "YYYY-MM-DD"
    public var bodyFatPct: Double?     // 0-100
    public var bmi: Double?            // e.g. 22.5
    public var waterPct: Double?       // 0-100
    public var muscleMassKg: Double?   // kg
    public var boneMassKg: Double?     // kg
    public var visceralFat: Double?    // rating 1-59
    public var metabolicAge: Int?      // years
    public var source: String          // "manual" | "healthkit" | "smart_scale"
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, source, bmi
        case bodyFatPct = "body_fat_pct"
        case waterPct = "water_pct"
        case muscleMassKg = "muscle_mass_kg"
        case boneMassKg = "bone_mass_kg"
        case visceralFat = "visceral_fat"
        case metabolicAge = "metabolic_age"
        case createdAt = "created_at"
    }

    public init(
        id: Int64? = nil, date: String,
        bodyFatPct: Double? = nil, bmi: Double? = nil, waterPct: Double? = nil,
        muscleMassKg: Double? = nil, boneMassKg: Double? = nil,
        visceralFat: Double? = nil, metabolicAge: Int? = nil,
        source: String = "manual",
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id; self.date = date
        self.bodyFatPct = bodyFatPct; self.bmi = bmi; self.waterPct = waterPct
        self.muscleMassKg = muscleMassKg; self.boneMassKg = boneMassKg
        self.visceralFat = visceralFat; self.metabolicAge = metabolicAge
        self.source = source; self.createdAt = createdAt
    }

    public var hasData: Bool {
        bodyFatPct != nil || bmi != nil || waterPct != nil ||
        muscleMassKg != nil || boneMassKg != nil || visceralFat != nil || metabolicAge != nil
    }
}

extension BodyComposition: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "body_composition"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
