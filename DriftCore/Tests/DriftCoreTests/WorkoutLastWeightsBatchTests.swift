import Foundation
@testable import DriftCore
import Testing
import GRDB

// Tier-0: DB-backed but deterministic — no LLM, no network.
//
// `WorkoutService.lastWeights(for:)` (#1074) replaces a per-row `lastWeight(for:)`
// loop in the exercise picker — 50-60 serial SQLite round-trips per keystroke,
// each crossing JNI on Android. These are differential tests: the batch result
// must equal the per-name result it replaced, including the subtle cases (warmup
// filtering, a nil weight on the newest set, unknown names).
//
// `WorkoutService.db` is `AppDatabase.shared`, which is a real file shared by
// parallel tests, so every fixture uses a UUID-suffixed exercise name and is
// deleted afterwards — the same pattern as WorkoutTests.

private struct SetSpec {
    let exercise: String
    let weight: Double?
    let reps: Int?
    let warmup: Bool
}

/// Inserts a throwaway workout with `specs` in order (so the last spec for an
/// exercise is the newest by rowid) and hands back the workout id for cleanup.
/// `Workout` is a non-mutating `PersistableRecord`, so the inserted id comes
/// back via `lastInsertedRowID` rather than the struct — without it the sets
/// fail the workout_id foreign key.
@discardableResult
private func seedWorkout(_ specs: [SetSpec]) throws -> Int64 {
    try AppDatabase.shared.writer.write { dbConn in
        let workout = Workout(name: "LastWeightsBatchFixture", date: "2026-07-19",
                              durationSeconds: 60, createdAt: "2026-07-19T10:00:00Z")
        try workout.insert(dbConn)
        let workoutId = dbConn.lastInsertedRowID
        for (index, spec) in specs.enumerated() {
            let set = WorkoutSet(workoutId: workoutId, exerciseName: spec.exercise, setOrder: index + 1,
                                 weightLbs: spec.weight, reps: spec.reps, isWarmup: spec.warmup)
            try set.insert(dbConn)
        }
        return workoutId
    }
}

private func deleteWorkout(_ id: Int64) {
    try? AppDatabase.shared.writer.write { dbConn in
        try WorkoutSet.filter(Column("workout_id") == id).deleteAll(dbConn)
        try Workout.filter(Column("id") == id).deleteAll(dbConn)
    }
}

@Test func lastWeightsMatchesPerNameLastWeight() throws {
    let suffix = UUID().uuidString.prefix(6)
    let bench = "Batch Bench \(suffix)"
    let squat = "Batch Squat \(suffix)"
    let warmupOnly = "Batch WarmupOnly \(suffix)"
    let unknown = "Batch Never Logged \(suffix)"

    let id = try seedWorkout([
        SetSpec(exercise: bench, weight: 135, reps: 10, warmup: false),
        SetSpec(exercise: bench, weight: 185, reps: 5, warmup: false),   // newest bench
        SetSpec(exercise: squat, weight: 225, reps: 5, warmup: false),
        SetSpec(exercise: warmupOnly, weight: 45, reps: 10, warmup: true),
    ])
    defer { deleteWorkout(id) }

    let names = [bench, squat, warmupOnly, unknown]
    let batch = try WorkoutService.lastWeights(for: names)
    for name in names {
        #expect(batch[name] == (try WorkoutService.lastWeight(for: name)),
                "batch disagreed with per-name lastWeight for \(name)")
    }
    #expect(batch[bench] == 185)
    #expect(batch[squat] == 225)
    #expect(batch[warmupOnly] == nil)
    #expect(batch[unknown] == nil)
}

/// `lastWeight(for:)` fetches the newest non-warmup set and returns ITS weight —
/// a nil weight there yields nil, it does not fall through to an older set with
/// a weight. The batch version groups rows itself, so this is the case most
/// likely to drift apart.
@Test func lastWeightsNilWeightOnNewestSetYieldsNoEntry() throws {
    let name = "Batch NilNewest \(UUID().uuidString.prefix(6))"
    let id = try seedWorkout([
        SetSpec(exercise: name, weight: 100, reps: 8, warmup: false),
        SetSpec(exercise: name, weight: nil, reps: nil, warmup: false),  // newest, bodyweight
    ])
    defer { deleteWorkout(id) }

    #expect(try WorkoutService.lastWeight(for: name) == nil)
    #expect(try WorkoutService.lastWeights(for: [name])[name] == nil)
}

/// Warmup sets are excluded, so the newest *working* set wins even when a
/// warmup was logged after it.
@Test func lastWeightsSkipsWarmupSets() throws {
    let name = "Batch WarmupAfter \(UUID().uuidString.prefix(6))"
    let id = try seedWorkout([
        SetSpec(exercise: name, weight: 200, reps: 5, warmup: false),
        SetSpec(exercise: name, weight: 45, reps: 10, warmup: true),     // newest overall
    ])
    defer { deleteWorkout(id) }

    #expect(try WorkoutService.lastWeights(for: [name])[name] == 200)
    #expect(try WorkoutService.lastWeights(for: [name])[name] == (try WorkoutService.lastWeight(for: name)))
}

@Test func lastWeightsIsExactNameMatch() throws {
    let suffix = UUID().uuidString.prefix(6)
    let name = "Batch Exact \(suffix)"
    let id = try seedWorkout([SetSpec(exercise: name, weight: 95, reps: 5, warmup: false)])
    defer { deleteWorkout(id) }

    // Same collation as `lastWeight(for:)` — a case variant is a different key.
    #expect(try WorkoutService.lastWeights(for: [name])[name] == 95)
    let variant = name.uppercased()
    #expect(try WorkoutService.lastWeights(for: [variant])[variant]
            == (try WorkoutService.lastWeight(for: variant)))
}

@Test func lastWeightsEmptyInputReturnsEmpty() throws {
    #expect(try WorkoutService.lastWeights(for: []).isEmpty)
}

/// The picker asks for every visible row at once; unlogged exercises simply
/// have no entry rather than producing a partial or padded dictionary.
@Test func lastWeightsReturnsOnlyLoggedNames() throws {
    let suffix = UUID().uuidString.prefix(6)
    let logged = "Batch Logged \(suffix)"
    let id = try seedWorkout([SetSpec(exercise: logged, weight: 155, reps: 6, warmup: false)])
    defer { deleteWorkout(id) }

    let names = [logged] + (1...20).map { "Batch Unlogged \($0) \(suffix)" }
    let batch = try WorkoutService.lastWeights(for: names)
    #expect(batch.count == 1)
    #expect(batch[logged] == 155)
}
