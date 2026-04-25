import Foundation
import GRDB

/// A single biomarker value extracted from a lab report.
public struct BiomarkerResult: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var reportId: Int64            // FK to lab_report
    public var biomarkerId: String        // matches BiomarkerDefinition.id (e.g. "total_cholesterol")
    public var value: Double
    public var unit: String               // original unit from report
    public var normalizedValue: Double    // value converted to standard unit
    public var normalizedUnit: String     // standard unit (from BiomarkerDefinition)
    public var referenceLow: Double?      // lab's reference range (if provided)
    public var referenceHigh: Double?
    public var confidence: Double?        // LLM extraction confidence (0–1); nil = regex-extracted
    public var isAIParsed: Bool           // true when value was extracted by LLM (not regex)
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, value, unit, confidence
        case reportId = "report_id"
        case biomarkerId = "biomarker_id"
        case normalizedValue = "normalized_value"
        case normalizedUnit = "normalized_unit"
        case referenceLow = "reference_low"
        case referenceHigh = "reference_high"
        case isAIParsed = "is_ai_parsed"
        case createdAt = "created_at"
    }

    public init(
        id: Int64? = nil,
        reportId: Int64,
        biomarkerId: String,
        value: Double,
        unit: String,
        normalizedValue: Double? = nil,
        normalizedUnit: String? = nil,
        referenceLow: Double? = nil,
        referenceHigh: Double? = nil,
        confidence: Double? = nil,
        isAIParsed: Bool = false,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.reportId = reportId
        self.biomarkerId = biomarkerId
        self.value = value
        self.unit = unit
        self.normalizedValue = normalizedValue ?? value
        self.normalizedUnit = normalizedUnit ?? unit
        self.referenceLow = referenceLow
        self.referenceHigh = referenceHigh
        self.confidence = confidence
        self.isAIParsed = isAIParsed
        self.createdAt = createdAt
    }
}

extension BiomarkerResult: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "biomarker_result"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
