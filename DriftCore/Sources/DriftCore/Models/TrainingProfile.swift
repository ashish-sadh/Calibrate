import Foundation

/// Persisted training profile — who the user is as a lifter, gathered by the
/// Coach interview ("set me up") and consumed by every workout generator
/// (buildSmartSession, suggestForSplitDay, the interview routine builder).
/// Mirrors WeightGoal's UserDefaults-JSON persistence.
public struct TrainingProfile: Codable, Equatable, Sendable {

    public enum Experience: String, Codable, CaseIterable, Sendable {
        case beginner, intermediate, advanced

        public var displayName: String { rawValue.capitalized }
    }

    public enum Location: String, Codable, CaseIterable, Sendable {
        case gym, home, both

        public var displayName: String {
            switch self {
            case .gym: "Gym"
            case .home: "Home"
            case .both: "Gym + Home"
            }
        }
    }

    public var experience: Experience?
    public var location: Location?
    /// Catalog equipment slugs the user can access (see
    /// `ExerciseDatabase.equipmentSlugs`). Empty + home location =
    /// bodyweight only; empty + gym = everything.
    public var equipment: [String]
    /// Freeform constraints exactly as the user said them — "postpartum",
    /// "left knee pain", "lower back injury". Gate exercise selection and
    /// travel into the AI context verbatim.
    public var constraints: [String]
    /// Set when a constraint implies medical sign-off (postpartum, injury
    /// rehab): did the user confirm clearance for light exercise?
    public var medicalClearance: Bool?
    public var daysPerWeek: Int?
    public var sessionMinutes: Int?
    /// Muscle group or activity to prioritize ("shoulders", "walking").
    public var priority: String?
    public var updatedAt: String

    public static let storageKey = "drift_training_profile"

    public init(experience: Experience? = nil, location: Location? = nil,
                equipment: [String] = [], constraints: [String] = [],
                medicalClearance: Bool? = nil, daysPerWeek: Int? = nil,
                sessionMinutes: Int? = nil, priority: String? = nil,
                updatedAt: String = DateFormatters.iso8601.string(from: Date())) {
        self.experience = experience
        self.location = location
        self.equipment = equipment
        self.constraints = constraints
        self.medicalClearance = medicalClearance
        self.daysPerWeek = daysPerWeek
        self.sessionMinutes = sessionMinutes
        self.priority = priority
        self.updatedAt = updatedAt
    }

    // MARK: - Persistence

    public static func load() -> TrainingProfile? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(TrainingProfile.self, from: data)
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Derived

    /// True when workout generation should restrict the exercise pool to the
    /// user's equipment: training at home, or an explicit equipment list.
    public var restrictsEquipment: Bool {
        location == .home || (!equipment.isEmpty && location != .gym)
    }

    /// One-line summary injected into the Coach context and echoed back in
    /// chat ("Training profile: intermediate · home · dumbbells, bands ·
    /// 3 days/week · watch: left knee pain").
    public var summary: String {
        var parts: [String] = []
        if let experience { parts.append(experience.rawValue) }
        if let location { parts.append(location.displayName.lowercased()) }
        if !equipment.isEmpty { parts.append(equipment.joined(separator: ", ")) }
        if let daysPerWeek { parts.append("\(daysPerWeek) days/week") }
        if let sessionMinutes { parts.append("~\(sessionMinutes) min") }
        if let priority { parts.append("focus: \(priority)") }
        if !constraints.isEmpty { parts.append("watch: \(constraints.joined(separator: "; "))") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Equipment normalization

    /// Map free text ("I have dumbbells and a resistance band") to catalog
    /// equipment slugs. Unknown words are dropped — the caller treats an
    /// empty result as bodyweight-only when the user said "nothing".
    public static func normalizeEquipment(_ text: String) -> [String] {
        let t = text.lowercased()
        var slugs: [String] = []
        func add(_ slug: String, when keywords: [String]) {
            if keywords.contains(where: { t.contains($0) }) { slugs.append(slug) }
        }
        add("dumbbell", when: ["dumbbell", "dumbell"])
        add("barbell", when: ["barbell", "olympic bar", "squat rack", "power rack", "bench press"])
        add("kettlebells", when: ["kettlebell"])
        add("bands", when: ["band"])
        add("cable", when: ["cable", "pulley"])
        add("machine", when: ["machine", "smith"])
        add("medicine ball", when: ["medicine ball", "med ball", "slam ball"])
        add("exercise ball", when: ["exercise ball", "swiss ball", "stability ball", "yoga ball"])
        add("foam roll", when: ["foam roll"])
        add("e-z curl bar", when: ["ez bar", "e-z", "curl bar"])
        add("other", when: ["pull-up bar", "pull up bar", "pullup bar", "trx", "rings"])
        return slugs
    }
}
