import Foundation
import GRDB

public struct DEXAScan: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var scanDate: String
    public var location: String?
    public var totalMassKg: Double?
    public var fatMassKg: Double?
    public var leanMassKg: Double?
    public var boneMassKg: Double?
    public var bodyFatPct: Double?
    public var visceralFatKg: Double?
    public var trunkFatPct: Double?
    public var armsFatPct: Double?
    public var legsFatPct: Double?
    public var boneDensityTotal: Double?
    public var notes: String?
    public var createdAt: String
    // v7 fields
    public var rmrCalories: Double?
    public var vatVolumeIn3: Double?
    public var agRatio: Double?

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

    public init(
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

    public var totalMassLbs: Double? { totalMassKg.map { $0 * 2.20462 } }
    public var fatMassLbs: Double? { fatMassKg.map { $0 * 2.20462 } }
    public var leanMassLbs: Double? { leanMassKg.map { $0 * 2.20462 } }
    public var visceralFatLbs: Double? { visceralFatKg.map { $0 * 2.20462 } }
    public var bmcLbs: Double? { boneMassKg.map { $0 * 2.20462 } }
}

extension DEXAScan: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dexa_scan"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
