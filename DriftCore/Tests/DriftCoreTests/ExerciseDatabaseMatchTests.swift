import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for ExerciseDatabase.match(name:) — the grounding gate that
// resolves a spoken/parsed exercise name to a canonical library entry, or
// returns nil so voice logging can flag a garbled/novel name instead of
// silently inventing an exercise (the "two chest ups → squats + bench" bug).

@Test func match_exactNameCaseInsensitive() {
    #expect(ExerciseDatabase.match(name: "Plank")?.name == "Plank")
    #expect(ExerciseDatabase.match(name: "plank")?.name == "Plank")
    #expect(ExerciseDatabase.match(name: "PLANK")?.name == "Plank")
}

@Test func match_pluralResolvesToSingular() {
    // "squats" must map to a real squat entry despite the trailing 's'.
    let hit = ExerciseDatabase.match(name: "squats")
    #expect(hit != nil)
    #expect(hit?.name.lowercased().contains("squat") == true)
}

@Test func match_singleWordPicksMostSpecific() {
    // Among many "... Squat" names, the bare "Squat" (fewest extra words) wins.
    #expect(ExerciseDatabase.match(name: "squat")?.name == "Squat")
}

@Test func match_multiWordCovered() {
    let bench = ExerciseDatabase.match(name: "bench press")
    #expect(bench != nil)
    #expect(bench?.name.lowercased().contains("bench") == true)
    #expect(bench?.name.lowercased().contains("press") == true)

    let dead = ExerciseDatabase.match(name: "deadlift")
    #expect(dead?.name.lowercased().contains("deadlift") == true)
}

@Test func match_garbledNameReturnsNil() {
    // The reported regression: "chest ups" is not a real movement — no single
    // catalog name covers BOTH "chest" and "ups", so we must flag, not invent.
    #expect(ExerciseDatabase.match(name: "chest ups") == nil)
}

@Test func match_nonsenseReturnsNil() {
    #expect(ExerciseDatabase.match(name: "qwerty zzz") == nil)
    #expect(ExerciseDatabase.match(name: "") == nil)
    #expect(ExerciseDatabase.match(name: "x") == nil)
}

@Test func match_extraDescriptiveWordsAreFlagged() {
    // "heavy bench" adds a word that's not in any canonical name → flagged so the
    // user can confirm, rather than silently dropping "heavy".
    #expect(ExerciseDatabase.match(name: "heavy super bench thing") == nil)
}

// MARK: - trackingType (#925 — per-exercise time-vs-reps classification)

@Test func trackingType_declaredDrillsAreTimeBased() {
    // Agility drills are declared time-based as data (an explicit name set), not
    // matched by a fuzzy substring — the fix the issue asked for.
    #expect(ExerciseDatabase.trackingType(for: "Ladder Drill") == .time)
    #expect(ExerciseDatabase.trackingType(for: "Agility Ladder") == .time)
    #expect(ExerciseDatabase.classifyTrackingType("Speed Ladder") == .time)
}

@Test func trackingType_holdFamiliesStayTimeBased() {
    // Family roots kept verbatim from the prior keyword list → no duration
    // exercise regresses to reps.
    for name in ["Plank", "Side Plank", "Wall Sit", "Dead Hang", "Farmer's Walk"] {
        #expect(ExerciseDatabase.trackingType(for: name) == .time, "\(name) should be time-based")
    }
}

@Test func trackingType_commonLiftsAreReps() {
    for name in ["Bench Press", "Back Squat", "Deadlift", "Bicep Curl", "Overhead Press"] {
        #expect(ExerciseDatabase.trackingType(for: name) == .reps, "\(name) should be reps-based")
    }
}

@Test func exerciseInfo_carriesExplicitTrackingType() {
    // The exercise model distinguishes tracking type as a per-exercise enum.
    let timed = ExerciseDatabase.ExerciseInfo(
        name: "x", bodyPart: "Core", primaryMuscles: [], secondaryMuscles: [],
        equipment: "other", category: "strength", level: "intermediate", trackingType: .time)
    #expect(timed.trackingType == .time)
}

@Test func exerciseInfo_catalogDecodesWithNilTrackingType() {
    // Back-compat: exercises.json has no trackingType field, so the optional
    // decodes to nil (treated as reps by the resolver) rather than throwing.
    let all = ExerciseDatabase.all
    #expect(!all.isEmpty)  // fixture loaded (else the assertion below is vacuous)
    #expect(all.allSatisfy { $0.trackingType == nil })
}
