import Foundation
import GRDB

struct DEXARegion: Identifiable, Codable, Sendable {
    var id: Int64?
    var scanId: Int64
    var region: String      // "arms", "legs", "trunk", "android", "gynoid", "total", "r_arm", "l_arm", "r_leg", "l_leg"
    var fatPct: Double?
    var totalMassLbs: Double?
    var fatMassLbs: Double?
    var leanMassLbs: Double?
    var bmcLbs: Double?

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
    static let databaseTableName = "dexa_region"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
