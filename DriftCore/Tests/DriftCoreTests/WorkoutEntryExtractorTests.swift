import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for the design-666 QW3 unified workout extractor.
// Pure helpers only — bounds + prompt + flag default + sync-path regex fallback.
// The FM-backed Tier-3 gold set lives in FoundationModelsExtractionEvalTests
// (when the eval target catches up to workout fixtures).

// MARK: - WorkoutBounds — hallucination guard

@Test func workoutBounds_strengthClean() {
    let e = FMWorkoutEntry(exerciseName: "bench press", sets: 3, reps: 10, weight: 135, category: .strength)
    #expect(WorkoutBounds.violation(in: e) == nil)
}

@Test func workoutBounds_rejectImpossibleWeight() {
    // 2000 lbs is double the world record — guaranteed hallucination
    let e = FMWorkoutEntry(exerciseName: "bench press", sets: 3, reps: 10, weight: 2000, category: .strength)
    #expect(WorkoutBounds.violation(in: e) == "weight")
}

@Test func workoutBounds_rejectTooManySets() {
    let e = FMWorkoutEntry(exerciseName: "squat", sets: 99, reps: 10, weight: 200, category: .strength)
    #expect(WorkoutBounds.violation(in: e) == "sets")
}

@Test func workoutBounds_rejectTooManyReps() {
    let e = FMWorkoutEntry(exerciseName: "push ups", sets: 1, reps: 9999, weight: nil, category: .strength)
    #expect(WorkoutBounds.violation(in: e) == "reps")
}

@Test func workoutBounds_cardioClean() {
    let e = FMWorkoutEntry(exerciseName: "running", durationMinutes: 30, category: .cardio)
    #expect(WorkoutBounds.violation(in: e) == nil)
}

@Test func workoutBounds_rejectMarathon24Hour() {
    let e = FMWorkoutEntry(exerciseName: "running", durationMinutes: 9999, category: .cardio)
    #expect(WorkoutBounds.violation(in: e) == "durationMinutes")
}

@Test func workoutBounds_cardioIgnoresStrengthFields() {
    // A cardio entry that happens to have weight set should still pass —
    // weight is only validated for strength entries (the user might log
    // "ran with a weighted vest"; the data is meaningful, just routed differently).
    let e = FMWorkoutEntry(
        exerciseName: "running", sets: nil, reps: nil, weight: 5000,
        durationMinutes: 30, category: .cardio
    )
    #expect(WorkoutBounds.violation(in: e) == nil)
}

@Test func workoutBounds_bodyweightStrengthNoWeight() {
    // Push-ups, pull-ups — strength with no weight. Must not flag.
    let e = FMWorkoutEntry(exerciseName: "pull ups", sets: 4, reps: 12, weight: nil, category: .strength)
    #expect(WorkoutBounds.violation(in: e) == nil)
}

// MARK: - Feature flag default (serialized — both tests touch one UserDefaults key)

@Suite(.serialized) struct WorkoutFlagBehavior {
    private let key = "drift_fm_workout_extract"

    @Test func defaultsAndPersistence() {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        #expect(Preferences.fmWorkoutExtractEnabled == true,
                "Per design-666 the FM workout path defaults ON")

        Preferences.fmWorkoutExtractEnabled = false
        #expect(Preferences.fmWorkoutExtractEnabled == false)
        Preferences.fmWorkoutExtractEnabled = true
        #expect(Preferences.fmWorkoutExtractEnabled == true)
    }

    @Test func asyncParse_flagOffMatchesSync() async {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences.fmWorkoutExtractEnabled = false
        let input = "Push Ups 3x15, Bench Press 3x10@135"
        let async = await AIActionParser.parseWorkoutExercisesAsync(input)
        let sync = AIActionParser.parseWorkoutExercises(input)
        #expect(async == sync, "Flag-off async path must match sync regex output exactly")
    }
}

// MARK: - Prompt anchoring

@Test func workoutPromptCoversAllPatternFamilies() {
    let p = WorkoutEntryExtractor.buildPrompt(for: "any")
    // Strength shorthand families
    #expect(p.contains("3x10") || p.contains("3 sets of 10"))
    #expect(p.contains("@135") || p.contains("at 60 kg"))
    #expect(p.lowercased().contains("rpe"))
    // Cardio duration phrasings
    #expect(p.lowercased().contains("30 min"))
    #expect(p.lowercased().contains("half an hour"))
    // Category enum
    #expect(p.contains("strength"))
    #expect(p.contains("cardio"))
    #expect(p.contains("mobility"))
}

@Test func workoutPromptAsksForCanonicalNames() {
    let p = WorkoutEntryExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("canonical exercise names"))
}

@Test func workoutPromptIncludesTheInputText() {
    let unique = "MARKER_\(UUID().uuidString.prefix(8))"
    let p = WorkoutEntryExtractor.buildPrompt(for: unique)
    #expect(p.contains(unique))
}

@Test func workoutPromptDocsKgToLbConversion() {
    // Bench/squat numbers vary 2.2× between unit systems — pin the conversion ask
    let p = WorkoutEntryExtractor.buildPrompt(for: "any")
    #expect(p.contains("2.205") || p.lowercased().contains("convert"))
    #expect(p.lowercased().contains("pounds"))
}

// MARK: - Sync regex path (verifies existing behavior unchanged)

@Test func syncParse_compoundExercises() {
    let result = AIActionParser.parseWorkoutExercises("Push Ups 3x15, Bench Press 3x10@135")
    #expect(result.count == 2)
    #expect(result[0].name == "Push Ups")
    #expect(result[0].sets == 3 && result[0].reps == 15 && result[0].weight == nil)
    #expect(result[1].name == "Bench Press")
    #expect(result[1].sets == 3 && result[1].reps == 10 && result[1].weight == 135)
}

@Test func syncParse_unstructuredExerciseDefaults() {
    // No "NxM" pattern → fall back to default 3x10 with the raw name
    let result = AIActionParser.parseWorkoutExercises("Squat")
    #expect(result.count == 1)
    #expect(result[0].name == "Squat")
    #expect(result[0].sets == 3 && result[0].reps == 10)
}

// MARK: - FMExerciseEntry → WorkoutExercise mapper (cloud/FM extraction → chat workout)

@Test func mapEntry_strengthWithDefaults() {
    let e = FMExerciseEntry(exerciseName: "bench press", category: .strength)
    let mapped = AIActionParser.workoutExercise(from: e)
    #expect(mapped == AIActionParser.WorkoutExercise(name: "bench press", sets: 3, reps: 10, weight: nil))
}

@Test func mapEntry_lbsDisplayPassesWeightThrough() {
    let e = FMExerciseEntry(exerciseName: "bench press", sets: 3, reps: 8, weight: 135, category: .strength)
    let mapped = AIActionParser.workoutExercise(from: e, displayUnit: .lbs)
    #expect(mapped?.weight == 135)
}

@Test func mapEntry_kgDisplayConvertsFromCanonicalLbs() {
    // Extractors store lbs ("at 60 kg" → 132 lbs); a kg user must see 60 back, not 132
    let e = FMExerciseEntry(exerciseName: "deadlift", sets: 5, reps: 5, weight: 132, category: .strength)
    let mapped = AIActionParser.workoutExercise(from: e, displayUnit: .kg)
    #expect(mapped?.weight == 60)
}

@Test func mapEntry_nonStrengthReturnsNil() {
    // Cardio/mobility/sports must not synthesize sets/reps rows
    let cardio = FMExerciseEntry(exerciseName: "running", durationMinutes: 20, category: .cardio)
    let mobility = FMExerciseEntry(exerciseName: "surya namaskar", sets: 12, category: .mobility)
    #expect(AIActionParser.workoutExercise(from: cardio) == nil)
    #expect(AIActionParser.workoutExercise(from: mobility) == nil)
}

