import Foundation
import GRDB

public struct GlucoseReading: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var timestamp: String     // ISO 8601 datetime
    public var glucoseMgdl: Double
    public var source: String        // "lingo_csv"
    public var importBatch: String?  // UUID grouping readings from same import

    enum CodingKeys: String, CodingKey {
        case id, timestamp, source
        case glucoseMgdl = "glucose_mgdl"
        case importBatch = "import_batch"
    }

    public init(
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
    public static let databaseTableName = "glucose_reading"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

enum GlucoseZone: Sendable {
    case low, normal, elevated, high
}
