import Foundation
import GRDB

struct DEXAScan: Identifiable, Codable, Sendable {
    var id: Int64?
    var scanDate: String
    var location: String?
    var totalMassKg: Double?
    var fatMassKg: Double?
    var leanMassKg: Double?
    var boneMassKg: Double?
    var bodyFatPct: Double?
    var visceralFatKg: Double?
    var trunkFatPct: Double?
    var armsFatPct: Double?
    var legsFatPct: Double?
    var boneDensityTotal: Double?
    var notes: String?
    var createdAt: String
    // v7 fields
    var rmrCalories: Double?
    var vatVolumeIn3: Double?
    var agRatio: Double?

    enum CodingKeys: String, CodingKey {
        case id, location, notes
        case scanDate = "scan_date"
        case totalMassKg = "total_mass_kg"
        case fatMassKg = "fat_mass_kg"
        case leanMassKg = "lean_mass_kg"
        case boneMassKg = "bone_mass_kg"
        case bodyFatPct = "body_fat_pct"
        case visceralFatKg = "visceral_fat_kg"
        case trunkFatPct = "trunk_fat_pct"
        case armsFatPct = "arms_fat_pct"
        case legsFatPct = "legs_fat_pct"
        case boneDensityTotal = "bone_density_total"
        case createdAt = "created_at"
        case rmrCalories = "rmr_calories"
        case vatVolumeIn3 = "vat_volume_in3"
        case agRatio = "ag_ratio"
    }

    init(
        id: Int64? = nil, scanDate: String, location: String? = nil,
        totalMassKg: Double? = nil, fatMassKg: Double? = nil, leanMassKg: Double? = nil,
        boneMassKg: Double? = nil, bodyFatPct: Double? = nil, visceralFatKg: Double? = nil,
        trunkFatPct: Double? = nil, armsFatPct: Double? = nil, legsFatPct: Double? = nil,
        boneDensityTotal: Double? = nil, notes: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date()),
        rmrCalories: Double? = nil, vatVolumeIn3: Double? = nil, agRatio: Double? = nil
    ) {
        self.id = id; self.scanDate = scanDate; self.location = location
        self.totalMassKg = totalMassKg; self.fatMassKg = fatMassKg; self.leanMassKg = leanMassKg
        self.boneMassKg = boneMassKg; self.bodyFatPct = bodyFatPct; self.visceralFatKg = visceralFatKg
        self.trunkFatPct = trunkFatPct; self.armsFatPct = armsFatPct; self.legsFatPct = legsFatPct
        self.boneDensityTotal = boneDensityTotal; self.notes = notes; self.createdAt = createdAt
        self.rmrCalories = rmrCalories; self.vatVolumeIn3 = vatVolumeIn3; self.agRatio = agRatio
    }

    var totalMassLbs: Double? { totalMassKg.map { $0 * 2.20462 } }
    var fatMassLbs: Double? { fatMassKg.map { $0 * 2.20462 } }
    var leanMassLbs: Double? { leanMassKg.map { $0 * 2.20462 } }
    var visceralFatLbs: Double? { visceralFatKg.map { $0 * 2.20462 } }
    var bmcLbs: Double? { boneMassKg.map { $0 * 2.20462 } }
}

extension DEXAScan: FetchableRecord, PersistableRecord {
    static let databaseTableName = "dexa_scan"
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
