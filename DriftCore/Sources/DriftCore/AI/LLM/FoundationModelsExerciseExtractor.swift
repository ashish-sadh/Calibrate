import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Public output type (available on all OS versions)

/// One exercise entry extracted from a free-text multi-exercise transcript.
/// Multi-entry sibling of `FMWorkoutEntry` — same numeric shape, but produced
/// as part of an array from ONE FM call so transcripts with novel separators
/// ("3x10 squats then 5x5 bench", "sūryanamaskār 12 sets followed by deadlifts
/// 3x5") work without comma-splitting. `unit` is fixed to lbs (downstream is
/// already lbs-canonical post-prompt-conversion).
public struct FMExerciseEntry: Sendable, Equatable {
    public enum Category: String, Sendable {
        case strength, cardio, mobility, sports
    }

    public enum Unit: String, Sendable {
        case lbs, kg
    }

    public let exerciseName: String
    public let sets: Int?
    public let reps: Int?
    public let weight: Double?
    public let unit: Unit
    public let durationMinutes: Int?
    public let category: Category

    public init(
        exerciseName: String,
        sets: Int? = nil,
        reps: Int? = nil,
        weight: Double? = nil,
        unit: Unit = .lbs,
        durationMinutes: Int? = nil,
        category: Category
    ) {
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.unit = unit
        self.durationMinutes = durationMinutes
        self.category = category
    }
}

public enum FMExerciseExtractorError: Error, Sendable {
    case unavailable
    case sessionFailed(String)
    /// Model returned an empty entry array — the message wasn't a workout
    /// transcript. Caller falls back to the regex/comma-split path.
    case empty
    /// One entry's numeric is out of plausible range. Caller falls back to
    /// regex; downstream bounds checks would have caught it anyway.
    case bounded(index: Int, field: String, value: Double)
}

// MARK: - Bounds (mirrors WorkoutBounds; per-entry validation)

public enum ExerciseTranscriptBounds {
    public static let setsRange: ClosedRange<Int> = 1...20
    public static let repsRange: ClosedRange<Int> = 1...500
    public static let weightLbsRange: ClosedRange<Double> = 0...1100
    public static let durationMinutesRange: ClosedRange<Int> = 1...600
    /// Realistic ceiling for "I did A then B then C ..." style transcripts.
    /// Above this is almost always the model splitting one movement into
    /// component cues ("breathe, brace, drive").
    public static let maxEntries: Int = 12

    /// Returns the first out-of-range field for the given entry, or nil when
    /// every numeric is sane. Strength entries are evaluated on sets/reps/weight;
    /// cardio / mobility / sports on durationMinutes.
    public static func violation(in e: FMExerciseEntry) -> String? {
        if e.exerciseName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "exerciseName"
        }
        switch e.category {
        case .strength:
            if let s = e.sets, !setsRange.contains(s) { return "sets" }
            if let r = e.reps, !repsRange.contains(r) { return "reps" }
            if let w = e.weight, !weightLbsRange.contains(w) { return "weight" }
        case .cardio, .mobility, .sports:
            if let d = e.durationMinutes, !durationMinutesRange.contains(d) { return "durationMinutes" }
        }
        return nil
    }
}

// MARK: - Extractor

public enum FoundationModelsExerciseExtractor {

    /// Extract zero-or-more workout entries from a free-text transcript via a
    /// single FoundationModels call. Throws `.unavailable` on iOS<26 / macOS<26
    /// or when FoundationModels is not linked; throws `.empty` when the model
    /// returns an empty array (non-workout message); throws `.bounded` when any
    /// entry's numerics fall outside `ExerciseTranscriptBounds`. All throws
    /// tell the caller to fall back to the comma-split regex path.
    public static func extract(text: String) async throws -> [FMExerciseEntry] {
#if canImport(FoundationModels)
        if #available(macOS 26, iOS 26, *) {
            let prompt = buildPrompt(for: text)
            do {
                let session = LanguageModelSession()
                let response = try await session.respond(to: prompt, generating: FMExerciseTranscriptSchema.self)
                let entries: [FMExerciseEntry] = response.content.entries.map { schemaEntry in
                    FMExerciseEntry(
                        exerciseName: schemaEntry.exerciseName,
                        sets: schemaEntry.sets,
                        reps: schemaEntry.reps,
                        weight: schemaEntry.weight,
                        unit: .lbs,
                        durationMinutes: schemaEntry.durationMinutes,
                        category: FMExerciseEntry.Category(rawValue: schemaEntry.category.lowercased()) ?? .strength
                    )
                }
                if entries.isEmpty { throw FMExerciseExtractorError.empty }
                if entries.count > ExerciseTranscriptBounds.maxEntries {
                    throw FMExerciseExtractorError.bounded(index: -1, field: "entryCount", value: Double(entries.count))
                }
                for (idx, e) in entries.enumerated() {
                    if let bad = ExerciseTranscriptBounds.violation(in: e) {
                        let badVal: Double
                        switch bad {
                        case "sets": badVal = Double(e.sets ?? 0)
                        case "reps": badVal = Double(e.reps ?? 0)
                        case "weight": badVal = e.weight ?? 0
                        case "durationMinutes": badVal = Double(e.durationMinutes ?? 0)
                        case "exerciseName": badVal = .nan
                        default: badVal = .nan
                        }
                        throw FMExerciseExtractorError.bounded(index: idx, field: bad, value: badVal)
                    }
                }
                return entries
            } catch let err as FMExerciseExtractorError {
                throw err
            } catch {
                throw FMExerciseExtractorError.sessionFailed("\(error)")
            }
        }
#endif
        throw FMExerciseExtractorError.unavailable
    }

    /// Prompt sent to the foundation model. Covers strength shorthand
    /// ("3x10", "3 sets of 10", "@135", "RPE 8"), mixed-language workout terms
    /// ("sūryanamaskār 12 sets", Hinglish "ek set mein 10 reps"), and novel
    /// separators ("then", "followed by", "after that") that the comma-split
    /// regex misses. Indian-food-bar equivalent for movement vocabulary.
    public static func buildPrompt(for text: String) -> String {
        """
        Parse the user's free-text workout transcript into a structured list of exercise entries. The user may describe one or many exercises in a single message; produce one entry per distinct exercise.

        Strength shorthand patterns:
        - "3x10" = 3 sets of 10 reps
        - "3 sets of 10" = 3 sets of 10 reps
        - "@135" = 135 lbs; "at 60 kg" = ~132 lbs (convert kg×2.205 to lbs, round to nearest pound)
        - "RPE 8" = use the given reps as-is
        - "8-12 reps" = use the middle (10)

        Cardio / duration patterns:
        - "30 min yoga" → mobility, durationMinutes=30
        - "ran 5k" = 5k run with no duration → cardio
        - "1h30m" = 90 minutes
        - "for half an hour" = 30 minutes; "for an hour" = 60

        Mixed-language / regional movement terms (Indian-language bar):
        - "sūryanamaskār 12 sets" → mobility, exerciseName="surya namaskar", sets=12
        - "push-ups 3x20" → strength, exerciseName="push-ups", sets=3, reps=20
        - "biceps curl 3x12 @20kg ke saath" → strength, exerciseName="biceps curl", sets=3, reps=12, weight=44 (20kg→lbs)
        - "ek set mein 10 reps" = "one set of 10 reps"
        - "deadlift 5x5 80kg" → strength, exerciseName="deadlift", sets=5, reps=5, weight=176 (80kg→lbs)

        Categorize each entry:
        - strength = lifts/calisthenics with sets+reps (bench, squat, push-ups, deadlift, curl)
        - cardio = aerobic with duration or distance (running, cycling, rowing, swim)
        - mobility = stretching, yoga, surya namaskar, foam rolling
        - sports = soccer, basketball, climbing

        Multi-exercise separators — split into multiple entries:
        - Commas: "3x10 squats, 5x5 bench"
        - "then" / "followed by" / "after that": "squats 3x10 then bench 5x5"
        - Conjunctions: "squats 3x10 and bench 5x5"

        Numeric rules:
        - For bodyweight movements, leave weight nil
        - For cardio, leave sets/reps/weight nil; set durationMinutes
        - Use canonical exercise names (e.g. "bench press" not "bench"; "running" not "ran"; "surya namaskar" for sūryanamaskār)
        - Weights ALWAYS in pounds — convert kg by multiplying by 2.205 (round to nearest pound)
        - Return EMPTY array when the message is not a workout (e.g. "show me my weight", "what did I eat")

        Text:

        \(text)
        """
    }
}

// MARK: - Generable schema (compiled only on macOS 26+ / iOS 26+)

#if canImport(FoundationModels)
@available(macOS 26, iOS 26, *)
@Generable
struct FMExerciseTranscriptSchema: Sendable {
    @Guide(description: "Each distinct exercise mentioned in the transcript, in the order the user said. Empty array when the message is not a workout (data request, weight log, food log, etc.).")
    let entries: [FMExerciseSchema]

    @Generable
    struct FMExerciseSchema: Sendable {
        @Guide(description: "Canonical exercise name, e.g. 'bench press' not 'bench', 'surya namaskar' for sūryanamaskār, 'running' not 'ran'")
        let exerciseName: String
        @Guide(description: "Strength: number of sets. Nil for cardio/mobility/sports.")
        let sets: Int?
        @Guide(description: "Strength: reps per set; for ranges, use the middle value. Nil for cardio/mobility/sports.")
        let reps: Int?
        @Guide(description: "Strength: weight in POUNDS (convert kg×2.205 if needed, round to nearest pound); nil for bodyweight or cardio")
        let weight: Double?
        @Guide(description: "Cardio/mobility/sports: total duration in minutes; nil for strength sets")
        let durationMinutes: Int?
        @Guide(description: "Movement category: 'strength', 'cardio', 'mobility', or 'sports'")
        let category: String
    }
}
#endif
