import Foundation
import GRDB

struct BodyComposition: Identifiable, Codable, Sendable {
    var id: Int64?
    var date: String            // "YYYY-MM-DD"
    var bodyFatPct: Double?     // 0-100
    var bmi: Double?            // e.g. 22.5
    var waterPct: Double?       // 0-100
    var muscleMassKg: Double?   // kg
    var boneMassKg: Double?     // kg
    var visceralFat: Double?    // rating 1-59
    var metabolicAge: Int?      // years
    var source: String          // "manual" | "healthkit" | "smart_scale"
    var createdAt: String

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

    init(
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

    var hasData: Bool {
        bodyFatPct != nil || bmi != nil || waterPct != nil ||
        muscleMassKg != nil || boneMassKg != nil || visceralFat != nil || metabolicAge != nil
    }
}

extension BodyComposition: FetchableRecord, PersistableRecord {
    static let databaseTableName = "body_composition"
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
