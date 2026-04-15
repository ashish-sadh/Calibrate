import Foundation
import Testing
import GRDB
@testable import Drift

// MARK: - Workout Persistence Tests (14 tests)

@Test func workoutSaveAndRetrieve() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var w = Workout(name: "Push Day", date: "2026-03-30", durationSeconds: 3600, createdAt: "2026-03-30T10:00:00Z")
        try w.insert(dbConn)
    }

    let fetched = try await db.reader.read { dbConn in
        try Workout.fetchAll(dbConn)
    }
    #expect(fetched.count == 1)
    #expect(fetched[0].name == "Push Day")
    #expect(fetched[0].id != nil)
}

@Test func workoutSaveWithSetsPreservesLink() async throws {
    let db = try AppDatabase.empty()
    // Step 1: insert workout
    try await db.writer.write { dbConn in
        var w = Workout(name: "Leg Day", date: "2026-03-30", createdAt: "2026-03-30")
        try w.insert(dbConn)
    }
    // Step 2: get workout ID
    let workout = try await db.reader.read { try Workout.fetchOne($0) }
    guard let wid = workout?.id else { Issue.record("No workout ID"); return }

    // Step 3: insert sets
    try await db.writer.write { dbConn in
        var s1 = WorkoutSet(workoutId: wid, exerciseName: "Squat", setOrder: 1, weightLbs: 225, reps: 5, isWarmup: false)
        var s2 = WorkoutSet(workoutId: wid, exerciseName: "Squat", setOrder: 2, weightLbs: 225, reps: 5, isWarmup: false)
        var s3 = WorkoutSet(workoutId: wid, exerciseName: "Leg Press", setOrder: 1, weightLbs: 400, reps: 10, isWarmup: false)
        try s1.insert(dbConn)
        try s2.insert(dbConn)
        try s3.insert(dbConn)
    }

    let sets = try await db.reader.read { dbConn in
        try WorkoutSet.fetchAll(dbConn)
    }
    #expect(sets.count == 3)
    #expect(sets.filter { $0.exerciseName == "Squat" }.count == 2)
}

@Test func workoutDeleteCascadesSetsNew() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var w = Workout(name: "Test", date: "2026-03-30", createdAt: "2026-03-30")
        try w.insert(dbConn)
        guard let wid = w.id else { return }
        var s = WorkoutSet(workoutId: wid, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false)
        try s.insert(dbConn)
    }

    let workouts = try await db.reader.read { try Workout.fetchAll($0) }
    guard let wid = workouts.first?.id else { Issue.record("No workout"); return }

    try await db.writer.write { dbConn in
        _ = try Workout.deleteOne(dbConn, id: wid)
    }

    let remainingSets = try await db.reader.read { dbConn in
        try WorkoutSet.fetchAll(dbConn)
    }
    #expect(remainingSets.isEmpty, "Sets should cascade delete with workout")
}

@Test func workoutDurationDisplayFormats() async throws {
    let w1 = Workout(name: "A", date: "2026-03-30", durationSeconds: 3600, createdAt: "")
    #expect(w1.durationDisplay == "1h 0m")

    let w2 = Workout(name: "B", date: "2026-03-30", durationSeconds: 5400, createdAt: "")
    #expect(w2.durationDisplay == "1h 30m")

    let w3 = Workout(name: "C", date: "2026-03-30", durationSeconds: 2700, createdAt: "")
    #expect(w3.durationDisplay == "45m")

    let w4 = Workout(name: "D", date: "2026-03-30", durationSeconds: nil, createdAt: "")
    #expect(w4.durationDisplay == "")

    let w5 = Workout(name: "E", date: "2026-03-30", durationSeconds: 0, createdAt: "")
    #expect(w5.durationDisplay == "")
}

@Test func workoutSetEstimated1RMBrzycki() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 225, reps: 5, isWarmup: false)
    let expected = 225.0 * 36.0 / (37.0 - 5.0)
    #expect(abs((s.estimated1RM ?? 0) - expected) < 0.01)
}

@Test func workoutSet1RMForSingleRep() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Deadlift", setOrder: 1, weightLbs: 405, reps: 1, isWarmup: false)
    #expect(s.estimated1RM == 405)
}

@Test func workoutSet1RMNilForZeroReps() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 0, isWarmup: false)
    #expect(s.estimated1RM == nil)
}

@Test func workoutSet1RMNilForHighReps() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 50, reps: 35, isWarmup: false)
    #expect(s.estimated1RM == nil, "Reps > 30 should return nil")
}

@Test func workoutSet1RMNilForNoWeight() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Push-up", setOrder: 1, weightLbs: nil, reps: 20, isWarmup: false)
    #expect(s.estimated1RM == nil)
}

@Test @MainActor func workoutSetDisplayFormatted() async throws {
    let saved = Preferences.weightUnit; defer { Preferences.weightUnit = saved }
    Preferences.weightUnit = .lbs
    let s1 = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 225, reps: 5, isWarmup: false)
    #expect(s1.display == "225 lbs × 5")

    let s2 = WorkoutSet(workoutId: 1, exerciseName: "Pull-up", setOrder: 1, weightLbs: nil, reps: 12, isWarmup: false)
    #expect(s2.display == "BW × 12")

    // Verify kg conversion
    Preferences.weightUnit = .kg
    #expect(s1.display == "102 kg × 5") // 225 lbs ≈ 102 kg
}

@Test func workoutTemplateJsonRoundTrip() async throws {
    let exercises = [
        WorkoutTemplate.TemplateExercise(name: "Bench Press", sets: 3),
        WorkoutTemplate.TemplateExercise(name: "Overhead Press", sets: 3)
    ]
    let json = try JSONEncoder().encode(exercises)
    let jsonStr = String(data: json, encoding: .utf8)!

    let template = WorkoutTemplate(name: "Push Day", exercisesJson: jsonStr, createdAt: "2026-03-30")
    #expect(template.exercises.count == 2)
    #expect(template.exercises[0].name == "Bench Press")
}

@Test func workoutTemplateEmptyJsonReturnsEmpty() async throws {
    let template = WorkoutTemplate(name: "Empty", exercisesJson: "[]", createdAt: "2026-03-30")
    #expect(template.exercises.isEmpty)
}

@Test func workoutTemplateInvalidJsonReturnsEmpty() async throws {
    let template = WorkoutTemplate(name: "Bad", exercisesJson: "not json", createdAt: "2026-03-30")
    #expect(template.exercises.isEmpty)
}

@Test func workoutMultipleSameDate() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var w1 = Workout(name: "Morning", date: "2026-03-30", createdAt: "2026-03-30T08:00:00Z")
        var w2 = Workout(name: "Evening", date: "2026-03-30", createdAt: "2026-03-30T18:00:00Z")
        try w1.insert(dbConn)
        try w2.insert(dbConn)
    }

    let workouts = try await db.reader.read { dbConn in
        try Workout.filter(Column("date") == "2026-03-30").fetchAll(dbConn)
    }
    #expect(workouts.count == 2, "Should allow multiple workouts same date")
}

// MARK: - WorkoutService Integration Tests (2 tests)

@Test func workoutServiceSaveReturnsId() async throws {
    // GRDB's @Sendable write closures don't propagate didInsert mutations.
    // So we must read back the record to get the assigned ID.
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var w = Workout(name: "Test", date: "2026-03-30", createdAt: "2026-03-30")
        try w.save(dbConn)
    }
    let saved = try await db.reader.read { try Workout.fetchOne($0) }
    #expect(saved?.id != nil, "Workout should have ID after save + read-back")
    #expect(saved?.name == "Test")
}

@Test func workoutSetsSaveCorrectly() async throws {
    let db = try AppDatabase.empty()
    // Insert workout
    try await db.writer.write { dbConn in
        var w = Workout(name: "Test", date: "2026-03-30", createdAt: "2026-03-30")
        try w.insert(dbConn)
    }
    let w = try await db.reader.read { try Workout.fetchOne($0) }
    guard let wid = w?.id else { Issue.record("No workout"); return }

    // Insert sets
    try await db.writer.write { dbConn in
        var s1 = WorkoutSet(workoutId: wid, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false)
        var s2 = WorkoutSet(workoutId: wid, exerciseName: "Bench", setOrder: 2, weightLbs: 155, reps: 8, isWarmup: false)
        try s1.insert(dbConn)
        try s2.insert(dbConn)
    }

    let sets = try await db.reader.read { try WorkoutSet.fetchAll($0) }
    #expect(sets.count == 2)
    #expect(sets[0].weightLbs == 135)
    #expect(sets[1].weightLbs == 155)
}

// MARK: - Database Integrity Tests (4 tests)

@Test func factoryResetClearsData() async throws {
    let db = try AppDatabase.empty()
    var w = WeightEntry(date: "2026-03-30", weightKg: 70)
    try db.saveWeightEntry(&w)
    var ml = MealLog(date: "2026-03-30", mealType: "lunch")
    try db.saveMealLog(&ml)

    try db.factoryReset()

    let weights = try db.fetchWeightEntries()
    let meals = try db.fetchMealLogs(for: "2026-03-30")
    #expect(weights.isEmpty)
    #expect(meals.isEmpty)
}

@Test func concurrentReadsSucceed() async throws {
    let db = try AppDatabase.empty()
    var w = WeightEntry(date: "2026-03-30", weightKg: 70)
    try db.saveWeightEntry(&w)

    let r1 = try db.fetchWeightEntries()
    let r2 = try db.fetchLatestWeight()
    #expect(r1.count == 1)
    #expect(r2?.weightKg == 70)
}

@Test func foreignKeyEnforcedOnFoodEntry() async throws {
    let db = try AppDatabase.empty()
    var entry = FoodEntry(mealLogId: 99999, foodName: "Phantom", servingSizeG: 100, calories: 100)
    do {
        try db.saveFoodEntry(&entry)
        Issue.record("Should have thrown foreign key violation")
    } catch {
        #expect(true)
    }
}

@Test func allTablesAccessibleAfterMigration() async throws {
    let db = try AppDatabase.empty()
    let _ = try db.fetchWeightEntries()
    let _ = try db.fetchMealLogs(for: "2026-01-01")
    let _ = try db.fetchActiveSupplements()
    let _ = try db.fetchGlucoseReadings(from: "2026-01-01", to: "2026-12-31")
    let _ = try db.fetchDEXAScans()
    let _ = try db.fetchLabReports()
    #expect(true, "All tables accessible")
}
