import Foundation
import GRDB

/// A tape-measurement site. Values are always stored in centimetres; the UI
/// converts for display based on the user's unit preference. The set is the
/// "usual ones" the best physique-tracking apps expose — kept deliberately
/// small so the entry form stays quick.
public enum MeasurementSite: String, CaseIterable, Codable, Sendable, Identifiable {
    public var id: String { rawValue }

    case neck, shoulders, chest
    case leftBicep, rightBicep
    case leftForearm, rightForearm
    case waist, hips
    case leftThigh, rightThigh
    case leftCalf, rightCalf

    public var displayName: String {
        switch self {
        case .neck: "Neck"
        case .shoulders: "Shoulders"
        case .chest: "Chest"
        case .leftBicep: "Left Bicep"
        case .rightBicep: "Right Bicep"
        case .leftForearm: "Left Forearm"
        case .rightForearm: "Right Forearm"
        case .waist: "Waist"
        case .hips: "Hips"
        case .leftThigh: "Left Thigh"
        case .rightThigh: "Right Thigh"
        case .leftCalf: "Left Calf"
        case .rightCalf: "Right Calf"
        }
    }

    /// Section the site belongs to, for grouping the entry form.
    public var group: Group {
        switch self {
        case .neck, .shoulders, .chest, .leftBicep, .rightBicep, .leftForearm, .rightForearm: .upper
        case .waist, .hips: .core
        case .leftThigh, .rightThigh, .leftCalf, .rightCalf: .lower
        }
    }

    public enum Group: String, CaseIterable, Sendable {
        case upper = "Upper Body"
        case core = "Core"
        case lower = "Lower Body"
    }

    /// A left/right paired site (used to compute symmetry).
    public var mirror: MeasurementSite? {
        switch self {
        case .leftBicep: .rightBicep
        case .rightBicep: .leftBicep
        case .leftForearm: .rightForearm
        case .rightForearm: .leftForearm
        case .leftThigh: .rightThigh
        case .rightThigh: .leftThigh
        case .leftCalf: .rightCalf
        case .rightCalf: .leftCalf
        default: nil
        }
    }

    /// Sites in a stable display order grouped by body region.
    public static let displayOrder: [MeasurementSite] = [
        .neck, .shoulders, .chest, .leftBicep, .rightBicep, .leftForearm, .rightForearm,
        .waist, .hips,
        .leftThigh, .rightThigh, .leftCalf, .rightCalf,
    ]

    // MARK: - How-to guidance (check-in "i" popovers)

    /// Where exactly the tape goes for this site — the one sentence that
    /// makes readings comparable week to week.
    public var tapePlacement: String {
        switch self {
        case .neck:
            "Around the narrowest point, just below the Adam's apple — tape level, head straight."
        case .shoulders:
            "Around the widest point over the peak of both shoulders, arms relaxed at your sides."
        case .chest:
            "Around the fullest part at nipple level, tape level all the way round, after a normal exhale."
        case .leftBicep, .rightBicep:
            "Around the peak of the flexed bicep, elbow at 90°. (Relaxed works too — just always measure the same way.)"
        case .leftForearm, .rightForearm:
            "Around the widest point below the elbow, fist gently clenched, arm straight."
        case .waist:
            "Around the navel, belly relaxed — don't pull in. Measure after a normal exhale."
        case .hips:
            "Around the widest point of the glutes, feet together, tape level."
        case .leftThigh, .rightThigh:
            "Around the widest point of the upper thigh, just below the glute fold, standing with weight even."
        case .leftCalf, .rightCalf:
            "Around the widest point of the calf, standing with weight even on both feet."
        }
    }

    /// Universal consistency rules — shown once per guide, not per site.
    public static let measuringTips: [String] = [
        "Same time of day — first thing in the morning is most repeatable.",
        "Tape snug against the skin but never compressing it.",
        "Keep the tape parallel to the floor (a mirror helps).",
        "Measure twice; if they differ, take the average.",
    ]

    /// Drift muscle names whose region the body figure highlights for this
    /// site (vocabulary of `BodyDiagram.librarySlugs(forDriftMuscle:)`).
    public var highlightMuscles: [String] {
        switch self {
        case .neck: ["neck"]
        case .shoulders: ["shoulders"]
        case .chest: ["chest"]
        case .leftBicep, .rightBicep: ["biceps"]
        case .leftForearm, .rightForearm: ["forearms"]
        case .waist: ["abdominals"]
        case .hips: ["glutes"]
        case .leftThigh, .rightThigh: ["quadriceps"]
        case .leftCalf, .rightCalf: ["calves"]
        }
    }
}

/// A dated set of body-circumference measurements. Values live in a JSON map
/// (site rawValue → centimetres) so users can record only the sites they care
/// about without a wide, mostly-null schema. Weight is intentionally NOT here —
/// it has its own tracking (`WeightEntry`).
public struct BodyMeasurement: Identifiable, Codable, Sendable {
    public var id: Int64?
    public var date: String              // "YYYY-MM-DD"
    /// site.rawValue → centimetres.
    public var measurementsCm: [String: Double]
    public var notes: String?
    public var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, date, notes
        case measurementsCm = "measurements_cm"
        case createdAt = "created_at"
    }

    public init(
        id: Int64? = nil, date: String,
        measurementsCm: [String: Double] = [:],
        notes: String? = nil,
        createdAt: String = ISO8601DateFormatter().string(from: Date())
    ) {
        self.id = id
        self.date = date
        self.measurementsCm = measurementsCm
        self.notes = notes
        self.createdAt = createdAt
    }

    public func value(for site: MeasurementSite) -> Double? {
        measurementsCm[site.rawValue]
    }

    public var isEmpty: Bool { measurementsCm.isEmpty }
}

// GRDB stores the map as a JSON string column; encode/decode transparently.
extension BodyMeasurement: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "body_measurement"
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["date"] = date
        container["notes"] = notes
        container["created_at"] = createdAt
        container["measurements_cm"] = (try? String(data: JSONEncoder().encode(measurementsCm), encoding: .utf8)) ?? "{}"
    }

    public init(row: Row) {
        id = row["id"]
        date = row["date"]
        notes = row["notes"]
        createdAt = row["created_at"]
        if let json: String = row["measurements_cm"],
           let data = json.data(using: .utf8),
           let map = try? JSONDecoder().decode([String: Double].self, from: data) {
            measurementsCm = map
        } else {
            measurementsCm = [:]
        }
    }
}
