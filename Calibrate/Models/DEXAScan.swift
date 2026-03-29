import Foundation
import GRDB

struct DEXAScan: Identifiable, Codable, Sendable {
    var id: Int64?
    var scanDate: String      // "YYYY-MM-DD"
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

    init(
        id: Int64? = nil,
        scanDate: String,
        location: String? = nil,
        totalMassKg: Double? = nil,
        fatMassKg: Double? = nil,
        leanMassKg: Double? = nil,
        boneMassKg: Double? = nil,
        bodyFatPct: Double? = nil,
        visceralFatKg: Double? = nil,
        trunkFatPct: Double? = nil,
        armsFatPct: Double? = nil,
        legsFatPct: Double? = nil,
        boneDensityTotal: Double? = nil,
        notes: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.scanDate = scanDate
        self.location = location
        self.totalMassKg = totalMassKg
        self.fatMassKg = fatMassKg
        self.leanMassKg = leanMassKg
        self.boneMassKg = boneMassKg
        self.bodyFatPct = bodyFatPct
        self.visceralFatKg = visceralFatKg
        self.trunkFatPct = trunkFatPct
        self.armsFatPct = armsFatPct
        self.legsFatPct = legsFatPct
        self.boneDensityTotal = boneDensityTotal
        self.notes = notes
        self.createdAt = createdAt
    }

    // Convenience: lbs conversions
    var totalMassLbs: Double? { totalMassKg.map { $0 * 2.20462 } }
    var fatMassLbs: Double? { fatMassKg.map { $0 * 2.20462 } }
    var leanMassLbs: Double? { leanMassKg.map { $0 * 2.20462 } }
    var visceralFatLbs: Double? { visceralFatKg.map { $0 * 2.20462 } }
}

extension DEXAScan: FetchableRecord, PersistableRecord {
    static let databaseTableName = "dexa_scan"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
