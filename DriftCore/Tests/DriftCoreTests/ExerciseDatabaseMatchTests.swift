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
