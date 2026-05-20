import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for #832 multi-exercise FM transcript extractor.
// Pure helpers only: bounds + prompt anchoring + flag-off / unavailable
// fallback equivalence. Real-FM golden coverage lives in
// DriftLLMEvalMacOS/FoundationModelsExerciseTranscriptEval.swift (Tier-3).

// MARK: - ExerciseTranscriptBounds — hallucination guard

@Test func transcriptBounds_strengthClean() {
    let e = FMExerciseEntry(exerciseName: "bench press", sets: 3, reps: 10, weight: 135, category: .strength)
    #expect(ExerciseTranscriptBounds.violation(in: e) == nil)
}

@Test func transcriptBounds_rejectImpossibleWeight() {
    // 2000 lbs is double the world record — guaranteed hallucination
    let e = FMExerciseEntry(exerciseName: "bench press", sets: 3, reps: 10, weight: 2000, category: .strength)
    #expect(ExerciseTranscriptBounds.violation(in: e) == "weight")
}

@Test func transcriptBounds_rejectTooManySets() {
    let e = FMExerciseEntry(exerciseName: "squat", sets: 99, reps: 10, weight: 200, category: .strength)
    #expect(ExerciseTranscriptBounds.violation(in: e) == "sets")
}

@Test func transcriptBounds_rejectTooManyReps() {
    let e = FMExerciseEntry(exerciseName: "push-ups", sets: 1, reps: 9999, weight: nil, category: .strength)
    #expect(ExerciseTranscriptBounds.violation(in: e) == "reps")
}

@Test func transcriptBounds_rejectEmptyName() {
    let e = FMExerciseEntry(exerciseName: "   ", sets: 3, reps: 10, weight: nil, category: .strength)
    #expect(ExerciseTranscriptBounds.violation(in: e) == "exerciseName")
}

@Test func transcriptBounds_cardioClean() {
    let e = FMExerciseEntry(exerciseName: "running", durationMinutes: 30, category: .cardio)
    #expect(ExerciseTranscriptBounds.violation(in: e) == nil)
}

@Test func transcriptBounds_mobilityClean() {
    let e = FMExerciseEntry(exerciseName: "surya namaskar", durationMinutes: 20, category: .mobility)
    #expect(ExerciseTranscriptBounds.violation(in: e) == nil)
}

@Test func transcriptBounds_rejectMarathonDurationOutOfRange() {
    let e = FMExerciseEntry(exerciseName: "running", durationMinutes: 9999, category: .cardio)
    #expect(ExerciseTranscriptBounds.violation(in: e) == "durationMinutes")
}

@Test func transcriptBounds_bodyweightStrengthNoWeight() {
    let e = FMExerciseEntry(exerciseName: "pull-ups", sets: 4, reps: 12, weight: nil, category: .strength)
    #expect(ExerciseTranscriptBounds.violation(in: e) == nil)
}

// MARK: - Prompt anchoring

@Test func transcriptPromptCoversAllPatternFamilies() {
    let p = FoundationModelsExerciseExtractor.buildPrompt(for: "any")
    #expect(p.contains("3x10"))
    #expect(p.contains("5x5"))
    #expect(p.contains("@135") || p.contains("at 60 kg"))
    #expect(p.lowercased().contains("rpe"))
    #expect(p.lowercased().contains("30 min"))
    #expect(p.contains("strength"))
    #expect(p.contains("cardio"))
    #expect(p.contains("mobility"))
    #expect(p.contains("sports"))
}

@Test func transcriptPromptCoversMixedLanguageCues() {
    let p = FoundationModelsExerciseExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("sūryanamaskār") || p.contains("surya namaskar"))
    #expect(p.contains("push-ups") || p.contains("push ups"))
    #expect(p.contains("ke saath") || p.contains("ek set mein"))
}

@Test func transcriptPromptCoversNovelSeparators() {
    let p = FoundationModelsExerciseExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("then"))
    #expect(p.contains("followed by"))
}

@Test func transcriptPromptDocsKgToLbConversion() {
    let p = FoundationModelsExerciseExtractor.buildPrompt(for: "any")
    #expect(p.contains("2.205"))
    #expect(p.lowercased().contains("pounds"))
}

@Test func transcriptPromptIncludesTheInputText() {
    let unique = "MARKER_\(UUID().uuidString.prefix(8))"
    let p = FoundationModelsExerciseExtractor.buildPrompt(for: unique)
    #expect(p.contains(unique))
}

@Test func transcriptPromptAsksForCanonicalNames() {
    let p = FoundationModelsExerciseExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("canonical exercise names"))
}

@Test func transcriptPromptAsksEmptyForNonWorkout() {
    let p = FoundationModelsExerciseExtractor.buildPrompt(for: "any").lowercased()
    #expect(p.contains("empty array"))
}

// MARK: - Fallback paths (serialized — touch the shared UserDefaults flag)

@Suite(.serialized) struct ExerciseTranscriptFallback {
    private let key = "drift_fm_workout_extract"

    @Test func flagOff_asyncMatchesSync() async {
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences.fmWorkoutExtractEnabled = false
        let input = "Push Ups 3x15, Bench Press 3x10@135"
        let async = await AIActionParser.parseWorkoutExercisesAsync(input)
        let sync = AIActionParser.parseWorkoutExercises(input)
        #expect(async == sync,
                "Flag-off path must short-circuit to sync regex — bit-identical output")
    }

    @Test func unavailablePlatform_fallsBackToRegex() async {
        // On Linux / macOS<26 (anywhere #if canImport(FoundationModels) is
        // false or @available fails), extract() throws .unavailable. The
        // async parser routes that to the regex path so callers always get a
        // result. When run on a real-FM device the call may succeed; the
        // contract is "fallback equivalence when .unavailable is observed",
        // and the non-empty-result invariant holds in both cases.
        defer { UserDefaults.standard.removeObject(forKey: key) }
        Preferences.fmWorkoutExtractEnabled = true
        let input = "Push Ups 3x15, Bench Press 3x10@135"

        var sawUnavailable = false
        do {
            _ = try await FoundationModelsExerciseExtractor.extract(text: input)
        } catch FMExerciseExtractorError.unavailable {
            sawUnavailable = true
        } catch {
            // Other errors (.empty, .bounded, .sessionFailed) on real-FM
            // platforms — also fine; the async parser handles them too.
        }

        let async = await AIActionParser.parseWorkoutExercisesAsync(input)
        let sync = AIActionParser.parseWorkoutExercises(input)
        if sawUnavailable {
            #expect(async == sync,
                    ".unavailable error path must fall back to regex output unchanged")
        }
        #expect(!async.isEmpty)
    }
}
