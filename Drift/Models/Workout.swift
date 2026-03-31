import Foundation
import GRDB

// MARK: - Exercise

struct Exercise: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var bodyPart: String
    var category: String
    var isCustom: Bool

    static let databaseTableName = "exercise"
    enum CodingKeys: String, CodingKey {
        case id, name, category
        case bodyPart = "body_part"
        case isCustom = "is_custom"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    static let bodyParts = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body"]
    static let categories = ["Barbell", "Dumbbell", "Machine", "Cable", "Bodyweight", "Other"]
}

// MARK: - Workout

struct Workout: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var date: String
    var durationSeconds: Int?
    var notes: String?
    var createdAt: String

    static let databaseTableName = "workout"
    enum CodingKeys: String, CodingKey {
        case id, name, date, notes
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    var durationDisplay: String {
        guard let s = durationSeconds, s > 0 else { return "" }
        let h = s / 3600; let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - WorkoutSet

struct WorkoutSet: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var workoutId: Int64
    var exerciseName: String
    var setOrder: Int
    var weightLbs: Double?
    var reps: Int?
    var isWarmup: Bool
    var rpe: Double?

    static let databaseTableName = "workout_set"
    enum CodingKeys: String, CodingKey {
        case id, reps, rpe
        case workoutId = "workout_id"
        case exerciseName = "exercise_name"
        case setOrder = "set_order"
        case weightLbs = "weight_lbs"
        case isWarmup = "is_warmup"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Estimated 1RM using Brzycki formula
    var estimated1RM: Double? {
        guard let w = weightLbs, w > 0, let r = reps, r > 0, r <= 30 else { return nil }
        if r == 1 { return w }
        return w * (36.0 / (37.0 - Double(r)))
    }

    var display: String {
        let w = weightLbs.map { "\(Int($0)) lb" } ?? "BW"
        let r = reps.map { "× \($0)" } ?? ""
        return "\(w) \(r)"
    }
}

// MARK: - WorkoutTemplate

struct WorkoutTemplate: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    var id: Int64?
    var name: String
    var exercisesJson: String  // JSON: [{"name": "Bench Press", "sets": 3}]
    var createdAt: String

    static let databaseTableName = "workout_template"
    enum CodingKeys: String, CodingKey {
        case id, name
        case exercisesJson = "exercises_json"
        case createdAt = "created_at"
    }
    mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    struct TemplateExercise: Codable {
        let name: String
        let sets: Int
        var isWarmup: Bool = false
        var restSeconds: Int = 90
        var notes: String?

        init(name: String, sets: Int, isWarmup: Bool = false, restSeconds: Int = 90, notes: String? = nil) {
            self.name = name; self.sets = sets; self.isWarmup = isWarmup
            self.restSeconds = restSeconds; self.notes = notes
        }

        // Backward-compatible decoding (old templates without warmup/rest)
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            sets = try c.decode(Int.self, forKey: .sets)
            isWarmup = (try? c.decode(Bool.self, forKey: .isWarmup)) ?? false
            restSeconds = (try? c.decode(Int.self, forKey: .restSeconds)) ?? 90
            notes = try? c.decode(String.self, forKey: .notes)
        }

        private enum CodingKeys: String, CodingKey {
            case name, sets, isWarmup, restSeconds, notes
        }
    }

    var exercises: [TemplateExercise] {
        (try? JSONDecoder().decode([TemplateExercise].self, from: Data(exercisesJson.utf8))) ?? []
    }
}

// MARK: - Workout Summary (for history display)

struct WorkoutSummary: Sendable {
    let workout: Workout
    let exercises: [String]       // unique exercise names
    let totalSets: Int
    let totalVolume: Double       // sum of weight × reps
    let prs: Int                  // count of new PRs in this workout
    let bestSets: [(exercise: String, weight: Double, reps: Int)]
}
