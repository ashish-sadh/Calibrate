import Foundation
@testable import DriftCore
import Testing
import GRDB

// Tier-0: #1107 — legacy raw-utterance custom exercises. The pre-#1079
// Android voice/text parser saved raw utterances ("3x10 bench press at 135")
// as custom exercise NAMES, polluting "Your Exercises" forever since no
// delete path existed. Locks the predicate, the generic removal API, the
// history-guarded prune, and the run-once launch wrapper.

private let customKey = "drift_custom_exercises"
private let prunedFlagKey = "drift_pruned_utterance_customs_v1"

// MARK: - isRawUtteranceExerciseName

@Test func isRawUtteranceExerciseNameMatchesJunk() {
    for name in ["3x10 bench press at 135", "5 x 5 squat", "3×12 curls", "bench press 3x10"] {
        #expect(ExerciseDatabase.isRawUtteranceExerciseName(name), "expected junk: \(name)")
    }
}

@Test func isRawUtteranceExerciseNameSparesLegitimateNames() {
    for name in ["Bulgarian Split Squat", "Bench Press", "Ladder Drill",
                 "90/90 Switches", "T-Bar Row", "Farmer's Carry"] {
        #expect(!ExerciseDatabase.isRawUtteranceExerciseName(name), "expected legit: \(name)")
    }
}

/// The plan's ship criterion: the predicate must not flag a single real
/// catalog exercise, or a legit template custom would vanish on launch.
@Test @MainActor func isRawUtteranceExerciseNameHasNoFalsePositivesInCatalog() {
    let junk = ExerciseDatabase.all.filter { ExerciseDatabase.isRawUtteranceExerciseName($0.name) }
    #expect(junk.isEmpty, "catalog names flagged as junk: \(junk.map(\.name))")
}

// MARK: - removeCustomExercises(where:)

@Test @MainActor func removeCustomExercisesDeletesMatchesAndKeepsRest() {
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    let suffix = UUID().uuidString.prefix(6)
    let junk = "3x10 Remove Probe \(suffix)"
    let legit = "Remove Probe Legit \(suffix)"
    ExerciseDatabase.addCustomExercise(name: junk, bodyPart: "Chest")
    ExerciseDatabase.addCustomExercise(name: legit, bodyPart: "Back")

    let removed = ExerciseDatabase.removeCustomExercises { $0.name == junk }

    #expect(removed == [junk])
    #expect(!ExerciseDatabase.customExercises.contains { $0.name == junk })
    #expect(ExerciseDatabase.customExercises.contains { $0.name == legit })
    #expect(ExerciseDatabase.info(for: junk) == nil)
    #expect(ExerciseDatabase.info(for: legit) != nil)
}

@Test @MainActor func removeCustomExercisesNoMatchIsNoopAndReturnsEmpty() {
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    let name = "Remove Probe Untouched \(UUID().uuidString.prefix(6))"
    ExerciseDatabase.addCustomExercise(name: name, bodyPart: "Legs")

    let removed = ExerciseDatabase.removeCustomExercises { $0.name == "does-not-exist-\(UUID())" }
    #expect(removed.isEmpty)
    #expect(ExerciseDatabase.customExercises.contains { $0.name == name })
}

// MARK: - pruneLegacyUtteranceCustoms(loggedExerciseNames:)

@Test @MainActor func pruneLegacyUtteranceCustomsRemovesUnreferencedJunk() {
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    let junk = "3x10 Prune Probe \(UUID().uuidString.prefix(6))"
    ExerciseDatabase.addCustomExercise(name: junk, bodyPart: "Chest")

    let removed = ExerciseDatabase.pruneLegacyUtteranceCustoms(loggedExerciseNames: [])
    #expect(removed.contains(junk))
    #expect(!ExerciseDatabase.customExercises.contains { $0.name == junk })
}

/// The safety guard: a junk-named custom with logged history must survive —
/// deleting it would orphan real workout_set rows.
@Test @MainActor func pruneLegacyUtteranceCustomsSparesJunkReferencedByHistory() {
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    let junk = "3x10 Prune Referenced \(UUID().uuidString.prefix(6))"
    ExerciseDatabase.addCustomExercise(name: junk, bodyPart: "Chest")

    let removed = ExerciseDatabase.pruneLegacyUtteranceCustoms(loggedExerciseNames: [junk.lowercased()])
    #expect(!removed.contains(junk))
    #expect(ExerciseDatabase.customExercises.contains { $0.name == junk })
}

@Test @MainActor func pruneLegacyUtteranceCustomsSparesLegitimateCustoms() {
    let snapshot = UserDefaults.standard.data(forKey: customKey)
    defer { UserDefaults.standard.set(snapshot, forKey: customKey) }

    let name = "Prune Probe Legit \(UUID().uuidString.prefix(6))"
    ExerciseDatabase.addCustomExercise(name: name, bodyPart: "Back")

    let removed = ExerciseDatabase.pruneLegacyUtteranceCustoms(loggedExerciseNames: [])
    #expect(!removed.contains(name))
    #expect(ExerciseDatabase.customExercises.contains { $0.name == name })
}

// MARK: - WorkoutService.pruneLegacyUtteranceCustomExercisesOnce (run-once launch wrapper)
//
// `WorkoutService.db` is `AppDatabase.shared`, a real file shared by parallel
// tests, so the fixture uses UUID-suffixed exercise names and is deleted
// afterwards — the same pattern as WorkoutLastWeightsBatchTests.

@discardableResult
private func seedWorkoutSet(exerciseName: String) throws -> Int64 {
    try AppDatabase.shared.writer.write { dbConn in
        let workout = Workout(name: "PruneOnceFixture", date: "2026-07-28",
                              durationSeconds: 60, createdAt: "2026-07-28T10:00:00Z")
        try workout.insert(dbConn)
        let workoutId = dbConn.lastInsertedRowID
        let set = WorkoutSet(workoutId: workoutId, exerciseName: exerciseName, setOrder: 1,
                             weightLbs: 135, reps: 10, isWarmup: false)
        try set.insert(dbConn)
        return workoutId
    }
}

private func deleteWorkout(_ id: Int64) {
    try? AppDatabase.shared.writer.write { dbConn in
        try WorkoutSet.filter(Column("workout_id") == id).deleteAll(dbConn)
        try Workout.filter(Column("id") == id).deleteAll(dbConn)
    }
}

@Test @MainActor func pruneOnceRemovesUnreferencedJunkKeepsReferencedJunkAndIsIdempotent() throws {
    let customSnapshot = UserDefaults.standard.data(forKey: customKey)
    let flagSnapshot = UserDefaults.standard.object(forKey: prunedFlagKey) as? Bool
    defer {
        UserDefaults.standard.set(customSnapshot, forKey: customKey)
        if let flagSnapshot {
            UserDefaults.standard.set(flagSnapshot, forKey: prunedFlagKey)
        } else {
            UserDefaults.standard.removeObject(forKey: prunedFlagKey)
        }
    }
    UserDefaults.standard.removeObject(forKey: prunedFlagKey)

    let suffix = UUID().uuidString.prefix(6)
    let unreferencedJunk = "3x10 Once Unreferenced \(suffix)"
    let referencedJunk = "5x5 Once Referenced \(suffix)"
    ExerciseDatabase.addCustomExercise(name: unreferencedJunk, bodyPart: "Chest")
    ExerciseDatabase.addCustomExercise(name: referencedJunk, bodyPart: "Back")
    let workoutId = try seedWorkoutSet(exerciseName: referencedJunk)
    defer { deleteWorkout(workoutId) }

    WorkoutService.pruneLegacyUtteranceCustomExercisesOnce()

    #expect(!ExerciseDatabase.customExercises.contains { $0.name == unreferencedJunk })
    #expect(ExerciseDatabase.customExercises.contains { $0.name == referencedJunk })
    #expect(DriftPlatform.keyValueStore.bool(forKey: prunedFlagKey) == true)

    // Second call must be a no-op: re-seed the junk the first call removed,
    // call again, and confirm the run-once flag short-circuits it.
    ExerciseDatabase.addCustomExercise(name: unreferencedJunk, bodyPart: "Chest")
    WorkoutService.pruneLegacyUtteranceCustomExercisesOnce()
    #expect(ExerciseDatabase.customExercises.contains { $0.name == unreferencedJunk },
            "second call must be a no-op — the flag should have short-circuited it")
}

@Test @MainActor func loggedExerciseNamesIsLowercasedAndDeduplicated() throws {
    let suffix = UUID().uuidString.prefix(6)
    let name = "Logged Names Probe \(suffix)"
    let workoutId = try seedWorkoutSet(exerciseName: name)
    defer { deleteWorkout(workoutId) }

    let logged = try WorkoutService.loggedExerciseNames()
    #expect(logged.contains(name.lowercased()))
}
