import Foundation
import GRDB

// MARK: - TrackingType

/// How an exercise's sets are measured. Reps-based exercises log weight × reps
/// (bench, squat); time-based exercises log a duration (planks, carries, agility
/// drills like "Ladder Drill") where a rep count is meaningless. Declared
/// per-exercise on the catalog via `ExerciseDatabase.trackingType(for:)` rather
/// than guessed from the raw name.
public enum TrackingType: String, Codable, Sendable {
    case reps
    case time
}

// MARK: - Exercise

public struct Exercise: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var name: String
    public var bodyPart: String
    public var category: String
    public var isCustom: Bool

    public static let databaseTableName = "exercise"
    enum CodingKeys: String, CodingKey {
        case id, name, category
        case bodyPart = "body_part"
        case isCustom = "is_custom"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public init(id: Int64? = nil, name: String, bodyPart: String, category: String, isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.bodyPart = bodyPart
        self.category = category
        self.isCustom = isCustom
    }

    public static let bodyParts = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core", "Full Body"]
    public static let categories = ["Barbell", "Dumbbell", "Machine", "Cable", "Bodyweight", "Other"]
}

// MARK: - Workout

public struct Workout: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var name: String
    public var date: String
    public var durationSeconds: Int?
    public var notes: String?
    public var createdAt: String

    public static let databaseTableName = "workout"
    enum CodingKeys: String, CodingKey {
        case id, name, date, notes
        case durationSeconds = "duration_seconds"
        case createdAt = "created_at"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public init(id: Int64? = nil, name: String, date: String, durationSeconds: Int? = nil, notes: String? = nil, createdAt: String) {
        self.id = id
        self.name = name
        self.date = date
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.createdAt = createdAt
    }

    public var durationDisplay: String {
        guard let s = durationSeconds, s > 0 else { return "" }
        let h = s / 3600; let m = (s % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}

// MARK: - WorkoutSet

public struct WorkoutSet: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var workoutId: Int64
    public var exerciseName: String
    public var setOrder: Int
    public var weightLbs: Double?
    public var reps: Int?
    public var isWarmup: Bool
    public var rpe: Double?
    public var durationSec: Int?
    public var exerciseOrder: Int = 0

    public static let databaseTableName = "workout_set"
    enum CodingKeys: String, CodingKey {
        case id, reps, rpe
        case workoutId = "workout_id"
        case exerciseName = "exercise_name"
        case setOrder = "set_order"
        case weightLbs = "weight_lbs"
        case isWarmup = "is_warmup"
        case durationSec = "duration_sec"
        case exerciseOrder = "exercise_order"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public init(id: Int64? = nil, workoutId: Int64, exerciseName: String, setOrder: Int, weightLbs: Double? = nil, reps: Int? = nil, isWarmup: Bool = false, rpe: Double? = nil, durationSec: Int? = nil, exerciseOrder: Int = 0) {
        self.id = id
        self.workoutId = workoutId
        self.exerciseName = exerciseName
        self.setOrder = setOrder
        self.weightLbs = weightLbs
        self.reps = reps
        self.isWarmup = isWarmup
        self.rpe = rpe
        self.durationSec = durationSec
        self.exerciseOrder = exerciseOrder
    }

    /// Estimated 1RM using Brzycki formula
    public var estimated1RM: Double? {
        guard let w = weightLbs, w > 0, let r = reps, r > 0, r <= 30 else { return nil }
        if r == 1 { return w }
        return w * (36.0 / (37.0 - Double(r)))
    }

    /// Whether this exercise is tracked by duration instead of reps. Delegates
    /// to the per-exercise tracking type declared on the exercise catalog
    /// (`ExerciseDatabase.trackingType`) so the decision is data-driven, not a
    /// substring guess. Kept as a convenience for the reps-vs-timer UI branches.
    public static func isDurationExercise(_ name: String) -> Bool {
        ExerciseDatabase.trackingType(for: name) == .time
    }
}

// MARK: - WorkoutTemplate

public struct WorkoutTemplate: Identifiable, Codable, Sendable, FetchableRecord, PersistableRecord {
    public var id: Int64?
    public var name: String
    public var exercisesJson: String  // JSON: [{"name": "Bench Press", "sets": 3}]
    public var createdAt: String
    public var isFavorite: Bool = false

    public static let databaseTableName = "workout_template"
    enum CodingKeys: String, CodingKey {
        case id, name
        case exercisesJson = "exercises_json"
        case createdAt = "created_at"
        case isFavorite = "is_favorite"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    public init(id: Int64? = nil, name: String, exercisesJson: String, createdAt: String, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.exercisesJson = exercisesJson
        self.createdAt = createdAt
        self.isFavorite = isFavorite
    }

    public struct TemplateExercise: Codable {
        public let name: String
        public let sets: Int
        public var isWarmup: Bool = false
        public var restSeconds: Int = 90
        public var notes: String?
        /// Per-exercise reps↔timer override (nil = classify by name via
        /// `WorkoutSet.isDurationExercise`). Set when the user flips the
        /// tracking mode in a workout/template edit.
        public var isDuration: Bool?

        public init(name: String, sets: Int, isWarmup: Bool = false, restSeconds: Int = 90, notes: String? = nil, isDuration: Bool? = nil) {
            self.name = name; self.sets = sets; self.isWarmup = isWarmup
            self.restSeconds = restSeconds; self.notes = notes; self.isDuration = isDuration
        }

        // Backward-compatible decoding (old templates without warmup/rest/isDuration)
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            sets = try c.decode(Int.self, forKey: .sets)
            isWarmup = (try? c.decode(Bool.self, forKey: .isWarmup)) ?? false
            restSeconds = (try? c.decode(Int.self, forKey: .restSeconds)) ?? 90
            notes = try? c.decode(String.self, forKey: .notes)
            isDuration = try? c.decode(Bool.self, forKey: .isDuration)
        }

        private enum CodingKeys: String, CodingKey {
            case name, sets, isWarmup, restSeconds, notes, isDuration
        }
    }

    public var exercises: [TemplateExercise] {
        (try? JSONDecoder().decode([TemplateExercise].self, from: Data(exercisesJson.utf8))) ?? []
    }
}

// MARK: - Workout Summary (for history display)

public struct WorkoutSummary: Sendable {
    public let workout: Workout
    public let exercises: [String]       // unique exercise names
    public let totalSets: Int
    public let totalVolume: Double       // sum of weight × reps
    public let prs: Int                  // count of new PRs in this workout
    public let bestSets: [(exercise: String, weight: Double, reps: Int)]

    public init(workout: Workout, exercises: [String], totalSets: Int, totalVolume: Double, prs: Int, bestSets: [(exercise: String, weight: Double, reps: Int)]) {
        self.workout = workout
        self.exercises = exercises
        self.totalSets = totalSets
        self.totalVolume = totalVolume
        self.prs = prs
        self.bestSets = bestSets
    }
}
