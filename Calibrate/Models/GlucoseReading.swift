import Foundation
import GRDB

struct GlucoseReading: Identifiable, Codable, Sendable {
    var id: Int64?
    var timestamp: String     // ISO 8601 datetime
    var glucoseMgdl: Double
    var source: String        // "lingo_csv"
    var importBatch: String?  // UUID grouping readings from same import

    init(
        id: Int64? = nil,
        timestamp: String,
        glucoseMgdl: Double,
        source: String = "lingo_csv",
        importBatch: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.glucoseMgdl = glucoseMgdl
        self.source = source
        self.importBatch = importBatch
    }

    /// Glucose zone for color coding.
    var zone: GlucoseZone {
        switch glucoseMgdl {
        case ..<70: .low
        case 70..<100: .normal
        case 100..<140: .elevated
        default: .high
        }
    }
}

extension GlucoseReading: FetchableRecord, PersistableRecord {
    static let databaseTableName = "glucose_reading"

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

enum GlucoseZone: Sendable {
    case low, normal, elevated, high
}
