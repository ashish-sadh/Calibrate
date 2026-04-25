import Foundation
import GRDB

public struct DEXARegion: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var scanId: Int64
    public var region: String      // "arms", "legs", "trunk", "android", "gynoid", "total", "r_arm", "l_arm", "r_leg", "l_leg"
    public var fatPct: Double?
    public var totalMassLbs: Double?
    public var fatMassLbs: Double?
    public var leanMassLbs: Double?
    public var bmcLbs: Double?

    public init(id: Int64? = nil, scanId: Int64, region: String, fatPct: Double? = nil, totalMassLbs: Double? = nil, fatMassLbs: Double? = nil, leanMassLbs: Double? = nil, bmcLbs: Double? = nil) {
        self.id = id
        self.scanId = scanId
        self.region = region
        self.fatPct = fatPct
        self.totalMassLbs = totalMassLbs
        self.fatMassLbs = fatMassLbs
        self.leanMassLbs = leanMassLbs
        self.bmcLbs = bmcLbs
    }

    enum CodingKeys: String, CodingKey {
        case id, region
        case scanId = "scan_id"
        case fatPct = "fat_pct"
        case totalMassLbs = "total_mass_lbs"
        case fatMassLbs = "fat_mass_lbs"
        case leanMassLbs = "lean_mass_lbs"
        case bmcLbs = "bmc_lbs"
    }
}

extension DEXARegion: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "dexa_region"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
