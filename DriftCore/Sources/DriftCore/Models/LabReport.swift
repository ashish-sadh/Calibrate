import Foundation
import GRDB

/// A lab report uploaded by the user (PDF or image).
public struct LabReport: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var reportDate: String         // ISO 8601 date (YYYY-MM-DD)
    public var labName: String?           // "Quest", "Labcorp", etc.
    public var fileName: String           // original file name
    public var fileDataHash: String       // SHA256 hash of encrypted file data
    public var markerCount: Int           // how many biomarkers were extracted
    public var notes: String?
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, notes
        case reportDate = "report_date"
        case labName = "lab_name"
        case fileName = "file_name"
        case fileDataHash = "file_data_hash"
        case markerCount = "marker_count"
        case createdAt = "created_at"
    }

    public init(
        id: Int64? = nil,
        reportDate: String,
        labName: String? = nil,
        fileName: String,
        fileDataHash: String = "",
        markerCount: Int = 0,
        notes: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.reportDate = reportDate
        self.labName = labName
        self.fileName = fileName
        self.fileDataHash = fileDataHash
        self.markerCount = markerCount
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Display-friendly date.
    public var displayDate: String {
        guard let date = DateFormatters.dateOnly.date(from: reportDate) else { return reportDate }
        return DateFormatters.dayDisplay.string(from: date)
    }
}

extension LabReport: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "lab_report"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
