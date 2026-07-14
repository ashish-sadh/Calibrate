import Foundation
import GRDB

/// A physique-photo pose. Front / back / left / right — the standard four that
/// physique-tracking apps use so shots line up for side-by-side comparison.
public enum ProgressPose: String, CaseIterable, Codable, Sendable {
    case front, back, left, right

    public var displayName: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .left: "Left Side"
        case .right: "Right Side"
        }
    }

    public var shortName: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .left: "Left"
        case .right: "Right"
        }
    }

    /// Measurement sites most visible / relevant to this pose — surfaced as
    /// stat overlays on the photo viewer. Front shows torso girths, the sides
    /// show that side's limbs, back shows the posterior chain girths. Weight is
    /// shown separately (always).
    public var relevantSites: [MeasurementSite] {
        switch self {
        case .front: [.shoulders, .chest, .waist, .hips]
        case .back:  [.shoulders, .waist, .hips]
        case .left:  [.leftBicep, .leftForearm, .waist, .leftThigh, .leftCalf]
        case .right: [.rightBicep, .rightForearm, .waist, .rightThigh, .rightCalf]
        }
    }
}

/// Metadata for one progress photo. The image bytes live on disk in the app
/// container (privacy-first — never leaves the device); the DB stores only the
/// pose, date, and the relative `filename` the on-device store resolves. One
/// row per (date, pose) — re-shooting a pose on the same day replaces it.
public struct ProgressPhoto: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var date: String              // "YYYY-MM-DD"
    public var pose: String              // ProgressPose rawValue
    public var filename: String          // relative filename in the ProgressPhotos dir
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, pose, filename
        case createdAt = "created_at"
    }

    public init(
        id: Int64? = nil, date: String, pose: ProgressPose, filename: String,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.date = date
        self.pose = pose.rawValue
        self.filename = filename
        self.createdAt = createdAt
    }

    public var poseEnum: ProgressPose? { ProgressPose(rawValue: pose) }
}

extension ProgressPhoto: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "progress_photo"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

/// A single day's progress entry — the photos and the measurement set taken
/// together. Purely a view-model grouping; not persisted as its own row.
public struct ProgressEntry: Sendable {
    public let date: String
    public let photos: [ProgressPhoto]
    public let measurement: BodyMeasurement?

    public init(date: String, photos: [ProgressPhoto], measurement: BodyMeasurement?) {
        self.date = date
        self.photos = photos
        self.measurement = measurement
    }

    public func photo(for pose: ProgressPose) -> ProgressPhoto? {
        photos.first { $0.pose == pose.rawValue }
    }

    public var hasPhotos: Bool { !photos.isEmpty }
}
