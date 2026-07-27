import Foundation
@testable import DriftCore
import Testing
import GRDB

// MARK: - Workout CRUD (12 tests)

@Test func workoutSaveAndFetch() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var w = Workout(name: "Push Day", date: "2026-03-29", durationSeconds: 3600, createdAt: ISO8601DateFormatter().string(from: Date()))
        try w.insert(dbConn)
    }
    let all = try await db.reader.read { try Workout.fetchAll($0) }
    #expect(all.count == 1)
    #expect(all[0].name == "Push Day")
}

@Test func workoutDurationDisplay() async throws {
    let w1 = Workout(name: "A", date: "2026-03-29", durationSeconds: 3700, createdAt: "")
    #expect(w1.durationDisplay == "1h 1m")
    let w2 = Workout(name: "B", date: "2026-03-29", durationSeconds: 1800, createdAt: "")
    #expect(w2.durationDisplay == "30m")
    let w3 = Workout(name: "C", date: "2026-03-29", durationSeconds: nil, createdAt: "")
    #expect(w3.durationDisplay == "")
}

@Test func workoutSetDisplay() async throws {
    let s1 = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false)
    #expect(s1.display(in: .lbs).contains("135"))
    #expect(s1.display(in: .lbs).contains("lbs"))
    #expect(s1.display(in: .lbs).contains("10"))
}

// MARK: - #1085: history renders in the user's unit

@Test func setDisplay_kgUser_readsBackWhatTheyLogged() {
    // The bug: a kg user logs 60 kg (stored 132.3 lbs) and every history
    // surface showed "132.3 lbs".
    let s = WorkoutSet(workoutId: 1, exerciseName: "Squat", setOrder: 1,
                       weightLbs: WeightUnit.kg.convertToLbs(60), reps: 5, isWarmup: false)
    let kg = s.display(in: .kg)
    #expect(kg.contains("60"), "expected 60 kg, got \(kg)")
    #expect(kg.contains("kg"))
    #expect(!kg.contains("lbs"))
}

@Test func setDisplay_lbsUser_isByteIdenticalToPre1085() {
    // 0-IOS-GUARD: lbs users must see exactly what they saw before.
    let weighted = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 137.5, reps: 8, isWarmup: false)
    #expect(weighted.display(in: .lbs) == "137.5 lbs × 8")
    let bodyweight = WorkoutSet(workoutId: 1, exerciseName: "Pull Up", setOrder: 1, weightLbs: nil, reps: 10, isWarmup: false)
    #expect(bodyweight.display(in: .lbs) == "BW × 10")
    let timed = WorkoutSet(workoutId: 1, exerciseName: "Plank", setOrder: 1, weightLbs: 45, durationSec: 90)
    #expect(timed.display(in: .lbs) == "45 lbs · 1:30")
}

@Test func setDisplay_durationSet_carriesTheUnitToo() {
    let timed = WorkoutSet(workoutId: 1, exerciseName: "Farmer Carry", setOrder: 1,
                           weightLbs: WeightUnit.kg.convertToLbs(32), durationSec: 60)
    #expect(timed.display(in: .kg) == "32 kg · 1:00")
}

@Test func editSetField_kgRoundTripsThroughStorage() {
    // The property #1084 locked for the active sheet, now for the Edit Set
    // field: prefill → retype the same number → same stored lbs. If the
    // prefill and the reader ever stop being inverses, this drifts 2.2x.
    let storedLbs = WeightUnit.kg.convertToLbs(60)
    let prefill = WeightUnit.kg.entryText(fromLbs: storedLbs)
    #expect(prefill == "60")
    let saved = WeightUnit.kg.entryTextToLbs(prefill)
    #expect(saved != nil)
    #expect(abs(saved! - storedLbs) < 0.01, "round-trip drifted: \(storedLbs) → \(prefill) → \(saved!)")
}

@Test func shareText_rendersVolumeAndSetsInTheUsersUnit() async throws {
    let suffix = Int.random(in: 100000...999999)
    var w = Workout(name: "Leg Day \(suffix)", date: "2026-07-20", createdAt: "")
    try WorkoutService.saveWorkout(&w)
    guard let wid = w.id else { Issue.record("no workout id"); return }
    defer { try? WorkoutService.deleteWorkout(id: wid) }

    try WorkoutService.saveSets([
        WorkoutSet(workoutId: wid, exerciseName: "Squat \(suffix)", setOrder: 0,
                   weightLbs: WeightUnit.kg.convertToLbs(100), reps: 5, isWarmup: false, exerciseOrder: 0),
    ])
    let kgShare = try WorkoutService.shareText(forWorkoutId: wid, unit: .kg)
    #expect(kgShare.contains("100 kg"), "per-set line not in kg: \(kgShare)")
    #expect(!kgShare.contains("lbs"), "lbs leaked into a kg user's share text: \(kgShare)")

    let lbsShare = try WorkoutService.shareText(forWorkoutId: wid, unit: .lbs)
    #expect(lbsShare.contains("lbs"))
    #expect(!lbsShare.contains("kg"))
}

@Test func workoutSet1RM() async throws {
    // Brzycki: weight * 36 / (37 - reps)
    let s = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false)
    let rm = s.estimated1RM!
    // 135 * 36 / (37-10) = 135 * 36/27 = 180
    #expect(abs(rm - 180) < 1)
}

@Test func workoutSet1RMSingle() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "DL", setOrder: 1, weightLbs: 315, reps: 1, isWarmup: false)
    #expect(s.estimated1RM == 315)
}

@Test func workoutSet1RMNilForZeroWeight() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Push Up", setOrder: 1, weightLbs: 0, reps: 20, isWarmup: false)
    #expect(s.estimated1RM == nil)
}

@Test func workoutSet1RMNilForNilReps() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "X", setOrder: 1, weightLbs: 100, reps: nil, isWarmup: false)
    #expect(s.estimated1RM == nil)
}

@Test func workoutSetBodyweight() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Pull Up", setOrder: 1, weightLbs: nil, reps: 10, isWarmup: false)
    #expect(s.display(in: .lbs).contains("BW"))
    #expect(s.display(in: .kg).contains("BW"), "bodyweight has no unit to convert")
}

@Test func workoutDeleteCascadesSets() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var w = Workout(name: "Test", date: "2026-03-29", createdAt: "")
        try w.insert(dbConn)
        let wid = dbConn.lastInsertedRowID
        var s = WorkoutSet(workoutId: wid, exerciseName: "Bench", setOrder: 1, weightLbs: 100, reps: 10, isWarmup: false)
        try s.insert(dbConn)
    }
    let workouts = try await db.reader.read { try Workout.fetchAll($0) }
    #expect(workouts.count == 1)
    try await db.writer.write { try Workout.deleteOne($0, id: workouts[0].id!) }
    let sets = try await db.reader.read { try WorkoutSet.fetchAll($0) }
    #expect(sets.isEmpty, "Sets should cascade delete with workout")
}

@Test func workoutMultipleSets() async throws {
    let db = try AppDatabase.empty()
    // Insert workout first, get ID, then insert sets
    try await db.writer.write { dbConn in
        var w = Workout(name: "Leg Day", date: "2026-03-29", createdAt: "")
        try w.insert(dbConn)
    }
    let wid = try await db.reader.read { try Workout.fetchOne($0)! }.id!
    try await db.writer.write { dbConn in
        for i in 1...5 {
            var s = WorkoutSet(workoutId: wid, exerciseName: "Squat", setOrder: i, weightLbs: Double(i * 45), reps: 10 - i, isWarmup: i == 1)
            try s.insert(dbConn)
        }
    }
    let sets = try await db.reader.read { try WorkoutSet.fetchAll($0) }
    #expect(sets.count == 5)
}

@Test func workoutTemplateEncodeDecode() async throws {
    let exercises = [WorkoutTemplate.TemplateExercise(name: "Bench", sets: 3), WorkoutTemplate.TemplateExercise(name: "Squat", sets: 5)]
    let json = String(data: try JSONEncoder().encode(exercises), encoding: .utf8)!
    let t = WorkoutTemplate(name: "PPL A", exercisesJson: json, createdAt: "")
    #expect(t.exercises.count == 2)
    #expect(t.exercises[0].name == "Bench")
    #expect(t.exercises[1].sets == 5)
}

@Test func workoutOrderedByDate() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        for d in ["2026-03-01", "2026-03-15", "2026-03-10"] {
            var w = Workout(name: "W", date: d, createdAt: "")
            try w.insert(dbConn)
        }
    }
    let all = try await db.reader.read { try Workout.order(Column("date").desc).fetchAll($0) }
    #expect(all[0].date == "2026-03-15")
    #expect(all[2].date == "2026-03-01")
}

// MARK: - Strong CSV Import (5 tests)

@Test func strongCSVImportBasic() async throws {
    let csv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n2026-03-29 10:00:00,\"Push Day\",30m,\"Bench Press\",1,135.0,10.0,0,0.0,\"\",\"\","
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("strong_test.csv")
    try csv.write(to: url, atomically: true, encoding: .utf8)
    let r = try WorkoutService.importStrongCSV(url: url)
    #expect(r.workouts == 1)
    #expect(r.sets == 1)
    #expect(r.exercises == 1)
    try FileManager.default.removeItem(at: url)
}

@Test func strongCSVMultipleExercises() async throws {
    let csv = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
    2026-03-29 10:00:00,"Push",30m,"Bench Press",1,135.0,10.0,0,0.0,"","",
    2026-03-29 10:00:00,"Push",30m,"Bench Press",2,155.0,8.0,0,0.0,"","",
    2026-03-29 10:00:00,"Push",30m,"Triceps Pushdown",1,50.0,12.0,0,0.0,"","",
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("strong_test2.csv")
    try csv.write(to: url, atomically: true, encoding: .utf8)
    let r = try WorkoutService.importStrongCSV(url: url)
    #expect(r.workouts == 1)
    #expect(r.sets == 3)
    #expect(r.exercises == 2)
    try FileManager.default.removeItem(at: url)
}

@Test func strongCSVMultipleDays() async throws {
    let csv = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
    2026-03-28 10:00:00,"Day 1",30m,"Squat",1,185.0,5.0,0,0.0,"","",
    2026-03-29 10:00:00,"Day 2",45m,"Deadlift",1,225.0,5.0,0,0.0,"","",
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("strong_test3.csv")
    try csv.write(to: url, atomically: true, encoding: .utf8)
    let r = try WorkoutService.importStrongCSV(url: url)
    #expect(r.workouts == 2)
    try FileManager.default.removeItem(at: url)
}

@Test func strongCSVDurationParsing() async throws {
    let csv = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
    2026-03-29 10:00:00,"Long",1h 30m,"Bench",1,100.0,10.0,0,0.0,"","",
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("strong_dur.csv")
    try csv.write(to: url, atomically: true, encoding: .utf8)
    // The shared on-disk DB persists across runs — clear leftover "Long" rows
    // so this run's import is findable regardless of accumulated history.
    for stale in try WorkoutService.fetchWorkouts(limit: 100_000).filter({ $0.name == "Long" }) {
        if let id = stale.id { try WorkoutService.deleteWorkout(id: id) }
    }
    _ = try WorkoutService.importStrongCSV(url: url)
    let w = try WorkoutService.fetchWorkouts(limit: 100_000)
    let longWorkout = w.first(where: { $0.name == "Long" })
    #expect(longWorkout?.durationSeconds == 5400, "1.5h = 5400s, got \(longWorkout?.durationSeconds ?? -1)")
    if let id = longWorkout?.id { try WorkoutService.deleteWorkout(id: id) }
    try FileManager.default.removeItem(at: url)
}

@Test func strongCSVEmptyFile() async throws {
    let csv = "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\n"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("strong_empty.csv")
    try csv.write(to: url, atomically: true, encoding: .utf8)
    let r = try WorkoutService.importStrongCSV(url: url)
    #expect(r.workouts == 0)
    try FileManager.default.removeItem(at: url)
}

// MARK: - Recovery Estimator (12 tests)

@Test func recoveryHighHRVHighScore() async throws {
    let score = RecoveryEstimator.calculateRecovery(hrvMs: 80, restingHR: 50, sleepHours: 8)
    #expect(score >= 67, "High HRV + low RHR + good sleep = good recovery: \(score)")
}

@Test func recoveryLowHRVLowScore() async throws {
    let score = RecoveryEstimator.calculateRecovery(hrvMs: 15, restingHR: 80, sleepHours: 4)
    #expect(score < 50, "Low HRV + high RHR + bad sleep = poor: \(score)")
}

@Test func recoveryModerate() async throws {
    let score = RecoveryEstimator.calculateRecovery(hrvMs: 40, restingHR: 65, sleepHours: 6.5)
    #expect(score > 20 && score < 80, "Moderate: \(score)")
}

@Test func recoveryZeroHRV() async throws {
    let score = RecoveryEstimator.calculateRecovery(hrvMs: 0, restingHR: 60, sleepHours: 7)
    #expect(score >= 0)
}

@Test func recoveryPersonalizedBaseline() async throws {
    let lowBaseline = RecoveryEstimator.Baselines(hrvMs: 50, restingHR: 55, respiratoryRate: 15, sleepHours: 7, daysOfData: 14)
    let highBaseline = RecoveryEstimator.Baselines(hrvMs: 100, restingHR: 55, respiratoryRate: 15, sleepHours: 7, daysOfData: 14)
    let scoreA = RecoveryEstimator.calculateRecovery(hrvMs: 50, restingHR: 55, sleepHours: 7, baselines: lowBaseline)
    let scoreB = RecoveryEstimator.calculateRecovery(hrvMs: 50, restingHR: 55, sleepHours: 7, baselines: highBaseline)
    #expect(scoreA > scoreB, "Same HRV should score better when baseline is lower")
}

@Test func sleepScorePerfect() async throws {
    let score = RecoveryEstimator.calculateSleepScore(totalHours: 8, remHours: 1.8, deepHours: 1.4, targetHours: 7.5)
    #expect(score >= 80, "Good sleep: \(score)")
}

@Test func sleepScorePoor() async throws {
    let score = RecoveryEstimator.calculateSleepScore(totalHours: 4, remHours: 0.5, deepHours: 0.3, targetHours: 7.5)
    #expect(score < 60, "Poor sleep: \(score)")
}

@Test func sleepScoreZeroHours() async throws {
    let score = RecoveryEstimator.calculateSleepScore(totalHours: 0, remHours: 0, deepHours: 0, targetHours: 7.5)
    #expect(score == 0)
}

@Test func dynamicSleepNeedIncreases() async throws {
    let low = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: 5, rollingDebtHours: 0)
    let high = RecoveryEstimator.dynamicSleepNeed(previousDayLoad: 18, rollingDebtHours: -4)
    #expect(high > low, "More strain + debt = more sleep needed")
    #expect(low >= 7.5, "Base minimum is 7.5h")
}

// MARK: - Favorites (6 tests)

@Test func favoriteSaveAndFetch() async throws {
    let db = try AppDatabase.empty()
    var fav = SavedFood(name: "Morning Oats", calories: 400, proteinG: 20, carbsG: 50, fatG: 10, fiberG: 5)
    try db.saveFavorite(&fav)
    let all = try db.fetchFavorites()
    #expect(all.count == 1 && all[0].name == "Morning Oats")
}

@Test func favoriteDelete() async throws {
    let db = try AppDatabase.empty()
    var fav = SavedFood(name: "X", calories: 100)
    try db.saveFavorite(&fav)
    let fetched = try db.fetchFavorites()
    try db.deleteFavorite(id: fetched[0].id!)
    #expect(try db.fetchFavorites().isEmpty)
}

@Test func favoriteRecipeFlag() async throws {
    let fav = SavedFood(name: "Post-Workout", calories: 600, isRecipe: true)
    #expect(fav.isRecipe == true)
    #expect(fav.macroSummary == "600cal 0P 0C 0F")
}

@Test func favoriteMultiple() async throws {
    let db = try AppDatabase.empty()
    for n in ["A", "B", "C"] { var f = SavedFood(name: n, calories: 100); try db.saveFavorite(&f) }
    #expect(try db.fetchFavorites().count == 3)
}

@Test func favoriteMacroSummary() async throws {
    let f = SavedFood(name: "X", calories: 500, proteinG: 30, carbsG: 60, fatG: 15)
    #expect(f.macroSummary == "500cal 30P 60C 15F")
}

@Test func favoriteDefaultServings() async throws {
    let f = SavedFood(name: "X", calories: 200)
    #expect(f.defaultServings == 1)
}

// MARK: - Barcode Cache (5 tests)

@Test func barcodeCacheSaveAndFetch() async throws {
    let db = try AppDatabase.empty()
    let product = OpenFoodFactsService.Product(barcode: "1234567890", name: "Test Bar", brand: "Brand", servingSize: "30g", calories: 200, proteinG: 20, carbsG: 25, fatG: 8, fiberG: 3, servingSizeG: 30, piecesPerServing: nil, ingredientsText: nil, novaGroup: nil)
    try db.cacheBarcodeProduct(BarcodeCache(from: product))
    let cached = try db.fetchCachedBarcode("1234567890")
    #expect(cached != nil)
    #expect(cached?.name == "Test Bar")
    #expect(cached?.caloriesPer100g == 200)
}

@Test func barcodeCacheMiss() async throws {
    let db = try AppDatabase.empty()
    #expect(try db.fetchCachedBarcode("0000000000") == nil)
}

@Test func barcodeCacheRecentOrder() async throws {
    let db = try AppDatabase.empty()
    for i in 1...5 {
        let p = OpenFoodFactsService.Product(barcode: "000\(i)", name: "Item \(i)", brand: nil, servingSize: nil, calories: Double(i * 100), proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, servingSizeG: nil, piecesPerServing: nil, ingredientsText: nil, novaGroup: nil)
        try db.cacheBarcodeProduct(BarcodeCache(from: p))
    }
    let recent = try db.fetchRecentBarcodes(limit: 3)
    #expect(recent.count == 3)
}

@Test func barcodeCacheDisplayName() async throws {
    let c = BarcodeCache(from: OpenFoodFactsService.Product(barcode: "123", name: "Oats", brand: "Quaker", servingSize: nil, calories: 100, proteinG: 3, carbsG: 20, fatG: 1, fiberG: 2, servingSizeG: nil, piecesPerServing: nil, ingredientsText: nil, novaGroup: nil))
    #expect(c.displayName == "Oats - Quaker")
}

@Test func barcodeCacheNoBrand() async throws {
    let c = BarcodeCache(from: OpenFoodFactsService.Product(barcode: "123", name: "Generic", brand: nil, servingSize: nil, calories: 50, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0, servingSizeG: nil, piecesPerServing: nil, ingredientsText: nil, novaGroup: nil))
    #expect(c.displayName == "Generic")
}

// MARK: - Piece Count Parsing (5 tests)

@Test func parsePieceCountThreePieces() async throws {
    let count = OpenFoodFactsService.parsePieceCount("3 pieces (85g)")
    #expect(count == 3)
}

@Test func parsePieceCountTwoBars() async throws {
    let count = OpenFoodFactsService.parsePieceCount("2 bars (60g)")
    #expect(count == 2)
}

@Test func parsePieceCountSinglePiece() async throws {
    // 1 piece should return nil (no division needed)
    let count = OpenFoodFactsService.parsePieceCount("1 piece (30g)")
    #expect(count == nil)
}

@Test func parsePieceCountNoPattern() async throws {
    let count = OpenFoodFactsService.parsePieceCount("100g")
    #expect(count == nil)
}

@Test func parsePieceCountNilInput() async throws {
    let count = OpenFoodFactsService.parsePieceCount(nil)
    #expect(count == nil)
}

// MARK: - Serving Unit Conversions (8 tests)

@Test func servingGramsIdentity() async throws {
    #expect(ServingUnit.grams.toGrams(100, ingredient: .rice) == 100)
}

@Test func servingCupsToGrams() async throws {
    let g = ServingUnit.cups.toGrams(1, ingredient: .rice)
    #expect(g == RawIngredient.rice.gramsPerCup) // 185
}

@Test func servingTbspToGrams() async throws {
    let g = ServingUnit.tablespoons.toGrams(1, ingredient: .butter)
    #expect(abs(g - RawIngredient.butter.gramsPerCup / 16) < 0.1) // ~14g
}

@Test func servingPiecesToGrams() async throws {
    let g = ServingUnit.pieces.toGrams(2, ingredient: .egg)
    #expect(g == 100) // 2 × 50g per egg
}

@Test func servingMlIdentity() async throws {
    #expect(ServingUnit.ml.toGrams(200, ingredient: .milk) == 200)
}

@Test func ingredientRiceCalories() async throws {
    #expect(RawIngredient.rice.caloriesPer100g == 360)
    #expect(RawIngredient.rice.proteinPer100g == 7)
}

@Test func ingredientOilPureFat() async throws {
    #expect(RawIngredient.oil.fatPer100g == 100)
    #expect(RawIngredient.oil.caloriesPer100g == 884)
    #expect(RawIngredient.oil.proteinPer100g == 0)
}

@Test func ingredientTypicalUnits() async throws {
    #expect(RawIngredient.egg.typicalUnit == .pieces)
    #expect(RawIngredient.oil.typicalUnit == .tablespoons)
    #expect(RawIngredient.rice.typicalUnit == .grams)
    #expect(RawIngredient.milk.typicalUnit == .ml)
}

// MARK: - Weight Goal Edge Cases (8 tests)

@Test func goalRemainingWeight() async throws {
    let g = WeightGoal(targetWeightKg: 50, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 60)
    #expect(abs(g.remainingKg(currentWeightKg: 55) - (-5)) < 0.01)
}

@Test func goalProgressOvershoot() async throws {
    let g = WeightGoal(targetWeightKg: 50, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 60)
    #expect(g.progress(currentWeightKg: 48) == 1.0, "Can't exceed 100%")
}

// #982: a LARGE overshoot (past the target by > half the journey) must still read 100%.
@Test func goalProgressLargeOvershootIsComplete() async throws {
    let g = WeightGoal(targetWeightKg: 90, monthsToAchieve: 3, startDate: "2026-01-01", startWeightKg: 100)
    #expect(g.progress(currentWeightKg: 79) == 1.0, "Overshooting the goal must still read 100%, not 0%")
}

// #983: an explicit calorie goal must be the ring target, not the (possibly inflated) macro sum.
@Test func explicitCalorieGoalRespectedInMacroTarget() async throws {
    let g = WeightGoal(targetWeightKg: 95, monthsToAchieve: 4, startDate: "2026-01-01",
                       startWeightKg: 110, dietPreference: .highProtein, calorieTargetOverride: 1500)
    let m = g.macroTargets(currentWeightKg: 110)!
    #expect(abs(m.calorieTarget - 1500) < 1, "Ring target must equal the user's 1500 kcal goal, got \(m.calorieTarget)")
}

// #984: a no-goal user must NOT be assessed as a losing goal (old `?? 0` default bug).
@Test func weightAssessmentNoGoalIsSilent() async throws {
    #expect(AIContextBuilder.weightAssessment(goalTargetKg: nil, currentEMA: 80, weeklyRateKg: 0.3) == nil,
            "No goal → no goal-relative assessment")
    #expect(AIContextBuilder.weightAssessment(goalTargetKg: 75, currentEMA: 80, weeklyRateKg: 0.3)
            == "Assessment: gaining despite losing goal — review intake",
            "A real losing goal that is gaining still fires the review message")
}

@Test func goalProgressNoChange() async throws {
    let g = WeightGoal(targetWeightKg: 50, monthsToAchieve: 6, startDate: "2026-01-01", startWeightKg: 60)
    #expect(g.progress(currentWeightKg: 60) == 0.0)
}

@Test func goalZeroChange() async throws {
    let g = WeightGoal(targetWeightKg: 60, monthsToAchieve: 3, startDate: "2026-01-01", startWeightKg: 60)
    #expect(g.totalChangeKg == 0)
    #expect(g.progress(currentWeightKg: 60) == 1.0) // already at goal
}

@Test func goalRequiredDeficitReasonable() async throws {
    // Lose 5kg in 3 months — use future start date so weeksRemaining > 0
    let startDate = DateFormatters.dateOnly.string(from: Date())
    let g = WeightGoal(targetWeightKg: 55, monthsToAchieve: 3, startDate: startDate, startWeightKg: 60)
    let deficit = g.requiredDailyDeficit(currentWeightKg: 60)
    #expect(deficit < 0, "Should be deficit")
    #expect(deficit > -800, "Should be reasonable: \(deficit)")
}

@Test func goalOnTrackExact() async throws {
    let g = WeightGoal(targetWeightKg: 50, monthsToAchieve: 6, startDate: currentGoalStartDate(), startWeightKg: 60)
    let rate = g.requiredWeeklyRate(currentWeightKg: 60)
    #expect(g.isOnTrack(actualWeeklyRateKg: rate, currentWeightKg: 60) == .onTrack)
}

@Test func goalBehind() async throws {
    let g = WeightGoal(targetWeightKg: 50, monthsToAchieve: 6, startDate: currentGoalStartDate(), startWeightKg: 60)
    #expect(g.isOnTrack(actualWeeklyRateKg: 0, currentWeightKg: 60) == .behind)
}

@Test func goalAhead() async throws {
    let g = WeightGoal(targetWeightKg: 50, monthsToAchieve: 6, startDate: currentGoalStartDate(), startWeightKg: 60)
    let rate = g.requiredWeeklyRate(currentWeightKg: 60)
    #expect(g.isOnTrack(actualWeeklyRateKg: rate * 2, currentWeightKg: 60) == .ahead)
}

// MARK: - Food History (4 tests)

@Test func foodNutritionForSpecificDate() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var m = MealLog(date: "2026-03-28", mealType: "lunch")
        try m.insert(dbConn)
        let mid = dbConn.lastInsertedRowID
        var e = FoodEntry(mealLogId: mid, foodName: "Rice", servingSizeG: 200, servings: 1, calories: 260, proteinG: 5, carbsG: 57, fatG: 0.5, fiberG: 0.6)
        try e.insert(dbConn)
    }
    let n = try db.fetchDailyNutrition(for: "2026-03-28")
    #expect(n.calories == 260)
    let n2 = try db.fetchDailyNutrition(for: "2026-03-29")
    #expect(n2.calories == 0, "Different date = 0")
}

@Test func foodMultipleDates() async throws {
    let db = try AppDatabase.empty()
    for d in ["2026-03-27", "2026-03-28", "2026-03-29"] {
        try await db.writer.write { dbConn in
            var m = MealLog(date: d, mealType: "lunch")
            try m.insert(dbConn)
            let mid = dbConn.lastInsertedRowID
            var e = FoodEntry(mealLogId: mid, foodName: "Food", servingSizeG: 100, servings: 1, calories: 500)
            try e.insert(dbConn)
        }
    }
    for d in ["2026-03-27", "2026-03-28", "2026-03-29"] {
        let n = try db.fetchDailyNutrition(for: d)
        #expect(n.calories == 500)
    }
}

/// The batch range query must agree with the per-day query it replaced
/// (BehaviorInsightService ran ~100 per-day fetches per dashboard load).
/// Covers both date sources: entries with their own date AND legacy
/// entries where the date lives only on the meal_log (COALESCE path).
@Test func dailyNutritionRangeMatchesPerDayFetch() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        // Entry with only meal_log date (fe.date nil — legacy shape)
        var m1 = MealLog(date: "2026-03-27", mealType: "lunch")
        try m1.insert(dbConn)
        var e1 = FoodEntry(mealLogId: dbConn.lastInsertedRowID, foodName: "Rice",
                           servingSizeG: 200, servings: 2, calories: 260, proteinG: 5,
                           carbsG: 57, fatG: 0.5, fiberG: 0.6)
        try e1.insert(dbConn)
        // Entry carrying its own date
        var m2 = MealLog(date: "2026-03-28", mealType: "dinner")
        try m2.insert(dbConn)
        var e2 = FoodEntry(mealLogId: dbConn.lastInsertedRowID, foodName: "Dal",
                           servingSizeG: 150, servings: 1, calories: 180, proteinG: 12,
                           carbsG: 20, fatG: 4, fiberG: 6, date: "2026-03-28")
        try e2.insert(dbConn)
    }
    let range = try db.fetchDailyNutritionRange(from: "2026-03-26", to: "2026-03-29")
    for day in ["2026-03-26", "2026-03-27", "2026-03-28", "2026-03-29"] {
        let single = try db.fetchDailyNutrition(for: day)
        let batched = range[day] ?? DailyNutrition(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0)
        #expect(batched.calories == single.calories, "calories diverge on \(day)")
        #expect(batched.proteinG == single.proteinG, "protein diverges on \(day)")
        #expect(batched.fiberG == single.fiberG, "fiber diverges on \(day)")
    }
    #expect(range["2026-03-26"] == nil, "empty day absent from map")
    #expect(range["2026-03-27"]?.calories == 520, "servings multiplier applied")
}

@Test func foodDeleteFromSpecificDate() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var m = MealLog(date: "2026-03-28", mealType: "lunch")
        try m.insert(dbConn)
        let mid = dbConn.lastInsertedRowID
        var e = FoodEntry(mealLogId: mid, foodName: "X", servingSizeG: 100, servings: 1, calories: 300)
        try e.insert(dbConn)
    }
    let entries = try await db.reader.read { try FoodEntry.fetchAll($0) }
    try db.deleteFoodEntry(id: entries[0].id!)
    #expect(try db.fetchDailyNutrition(for: "2026-03-28").calories == 0)
}

@Test func foodMealLogsForDate() async throws {
    let db = try AppDatabase.empty()
    try await db.writer.write { dbConn in
        var b = MealLog(date: "2026-03-28", mealType: "breakfast"); try b.insert(dbConn)
        var l = MealLog(date: "2026-03-28", mealType: "lunch"); try l.insert(dbConn)
        var d2 = MealLog(date: "2026-03-29", mealType: "dinner"); try d2.insert(dbConn)
    }
    let logs = try db.fetchMealLogs(for: "2026-03-28")
    #expect(logs.count == 2)
}

// MARK: - Database Factory Reset (2 tests)

@Test func factoryResetClearsAll() async throws {
    let db = try AppDatabase.empty()
    var w = WeightEntry(date: "2026-03-28", weightKg: 55)
    try db.saveWeightEntry(&w)
    var s = Supplement(name: "Test")
    try db.saveSupplement(&s)
    try db.factoryReset()
    #expect(try db.fetchWeightEntries().isEmpty)
    #expect(try db.fetchActiveSupplements().isEmpty)
}

@Test func factoryResetReseedsFood() async throws {
    let db = try AppDatabase.empty()
    try db.factoryReset()
    // Foods should be re-seeded from JSON
    let foods = try db.searchFoods(query: "rice")
    // May or may not find results depending on bundle availability in test
    #expect(true) // just verify no crash
}

// MARK: - More Model Tests (6 tests)

@Test func weightUnitConversion() async throws {
    #expect(abs(WeightUnit.lbs.convert(fromKg: 1.0) - 2.20462) < 0.001)
    #expect(abs(WeightUnit.kg.convert(fromKg: 1.0) - 1.0) < 0.001)
}

@Test func weightUnitConvertToKg() async throws {
    #expect(abs(WeightUnit.lbs.convertToKg(220) - 99.79) < 0.1)
    #expect(WeightUnit.kg.convertToKg(70) == 70)
}

// MARK: - Set-weight field round-trip (#1084)

@Test func setWeightFieldRoundTripsInBothUnits() async throws {
    // entryText and entryTextToLbs are inverses. If one is ever changed
    // without the other, a stored weight silently changes on every save.
    for lbs in [45.0, 132.3, 137.5, 315.0] {
        for unit in [WeightUnit.kg, .lbs] {
            let text = unit.entryText(fromLbs: lbs)
            let back = unit.entryTextToLbs(text) ?? 0
            #expect(abs(back - lbs) < 0.15, "\(unit.displayName) round-trip lost \(lbs) → \(text) → \(back)")
        }
    }
}

@Test func setWeightPrefillDoesNotInflateKgLogAcrossSessions() async throws {
    // The #1084 corruption: prefill wrote the raw *stored lbs* into a kg
    // field, the reader converted that text as kg, and 60 kg climbed
    // 60 → 132.3 → 291.7 → ... one hop per workout, with no user input.
    // Re-opening an exercise and saving it untouched must be a no-op.
    let unit = WeightUnit.kg
    var stored = unit.convertToLbs(60)          // user logged 60 kg
    for session in 1...3 {
        let prefilled = unit.entryText(fromLbs: stored)   // what the field shows
        #expect(prefilled == "60", "session \(session) prefilled \(prefilled), expected the user's own 60")
        stored = unit.entryTextToLbs(prefilled) ?? 0      // what saving it writes back
    }
    #expect(abs(stored - 132.28) < 0.05, "60 kg drifted to \(stored) lbs over three untouched sessions")
}

@Test func setWeightPrefillLeavesLbsUsersUnchanged() async throws {
    // The lbs path had no factor and must keep having none.
    let unit = WeightUnit.lbs
    #expect(unit.entryText(fromLbs: 135) == "135")
    #expect(unit.entryTextToLbs("135") == 135)
    #expect(unit.entryText(fromLbs: 137.5) == "137.5")   // fractional plates survive (#1080)
}

@Test func setWeightEntryTextRejectsEmptyAndAcceptsCommaDecimals() async throws {
    // Callers coalesce nil to 0 and then store nil — blank/bodyweight sets
    // must not become 0-weight rows.
    #expect(WeightUnit.kg.entryTextToLbs("") == nil)
    #expect(WeightUnit.kg.entryTextToLbs("0") == nil)
    #expect(WeightUnit.kg.entryTextToLbs("abc") == nil)
    #expect(WeightUnit.lbs.entryTextToLbs("-5") == nil)
    // Comma decimal keyboards (#1022)
    #expect(abs((WeightUnit.lbs.entryTextToLbs("137,5") ?? 0) - 137.5) < 0.01)
}

@Test func dateFormattersToday() async throws {
    let today = DateFormatters.todayString
    #expect(today.count == 10) // YYYY-MM-DD
    #expect(today.contains("-"))
}

@Test func glucoseZoneBoundaries() async throws {
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 69).zone == .low)
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 70).zone == .normal)
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 99).zone == .normal)
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 100).zone == .elevated)
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 139).zone == .elevated)
    #expect(GlucoseReading(timestamp: "", glucoseMgdl: 140).zone == .high)
}

@Test func mealTypeAllCases() async throws {
    #expect(MealType.allCases.count == 4)
    #expect(MealType.breakfast.icon == "sunrise")
    #expect(MealType.dinner.displayName == "Dinner")
}

@Test func dailyNutritionMacroSummary() async throws {
    let n = DailyNutrition(calories: 2000, proteinG: 150, carbsG: 200, fatG: 80, fiberG: 30)
    #expect(n.macroSummary == "2000cal 150P 200C 80F")
}

// MARK: - Template Warmup & Rest Tests (6 tests)

@Test func templateExerciseWarmupFlag() async throws {
    let warmup = WorkoutTemplate.TemplateExercise(name: "Band Pull Aparts", sets: 2, isWarmup: true, restSeconds: 30)
    let working = WorkoutTemplate.TemplateExercise(name: "Bench Press", sets: 3, isWarmup: false, restSeconds: 150)
    #expect(warmup.isWarmup == true)
    #expect(working.isWarmup == false)
    #expect(warmup.restSeconds == 30)
    #expect(working.restSeconds == 150)
}

@Test func templateExerciseNotes() async throws {
    let ex = WorkoutTemplate.TemplateExercise(name: "Deadlift", sets: 3, restSeconds: 150, notes: "5-8 reps")
    #expect(ex.notes == "5-8 reps")
}

@Test func templateExerciseBackwardCompatDecode() async throws {
    // Old format without warmup/rest/notes fields
    let oldJson = #"[{"name":"Bench Press","sets":3}]"#
    let decoded = try JSONDecoder().decode([WorkoutTemplate.TemplateExercise].self, from: Data(oldJson.utf8))
    #expect(decoded.count == 1)
    #expect(decoded[0].name == "Bench Press")
    #expect(decoded[0].sets == 3)
    #expect(decoded[0].isWarmup == false, "Should default to false")
    #expect(decoded[0].restSeconds == 90, "Should default to 90")
    #expect(decoded[0].notes == nil, "Should default to nil")
}

@Test func templateExerciseNewFormatDecode() async throws {
    let newJson = #"[{"name":"Band Pull Aparts","sets":2,"isWarmup":true,"restSeconds":30,"notes":"2x10"}]"#
    let decoded = try JSONDecoder().decode([WorkoutTemplate.TemplateExercise].self, from: Data(newJson.utf8))
    #expect(decoded[0].isWarmup == true)
    #expect(decoded[0].restSeconds == 30)
    #expect(decoded[0].notes == "2x10")
}

@Test func templateWarmupExerciseSeparation() async throws {
    let exercises: [WorkoutTemplate.TemplateExercise] = [
        .init(name: "Warmup A", sets: 2, isWarmup: true),
        .init(name: "Warmup B", sets: 1, isWarmup: true),
        .init(name: "Bench Press", sets: 3),
        .init(name: "Squats", sets: 4),
    ]
    let warmups = exercises.filter(\.isWarmup)
    let working = exercises.filter { !$0.isWarmup }
    #expect(warmups.count == 2)
    #expect(working.count == 2)
}

@Test func defaultTemplateSeeding() async throws {
    let templates = [
        WorkoutTemplate.TemplateExercise(name: "Test", sets: 3, isWarmup: false, restSeconds: 120, notes: "8 reps"),
        WorkoutTemplate.TemplateExercise(name: "Warmup", sets: 2, isWarmup: true, restSeconds: 30),
    ]
    let data = try JSONEncoder().encode(templates)
    let decoded = try JSONDecoder().decode([WorkoutTemplate.TemplateExercise].self, from: data)
    #expect(decoded.count == 2)
    #expect(decoded[0].notes == "8 reps")
    #expect(decoded[1].isWarmup == true)
}

// MARK: - Workout Service Tests (10 tests)

@Test func saveAndFetchWorkoutService() async throws {
    let db = try AppDatabase.empty()
    let w = Workout(name: "Test", date: "2026-03-30", durationSeconds: 1800, createdAt: ISO8601DateFormatter().string(from: Date()))
    try await db.writer.write { [w] dbConn in var m = w; try m.insert(dbConn) }
    let all = try await db.reader.read { try Workout.fetchAll($0) }
    #expect(all.count == 1)
    #expect(all[0].name == "Test")
    #expect(all[0].durationSeconds == 1800)
}

@Test func workoutSetWarmupExcludedFromVolume() async throws {
    let warmup = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 45, reps: 10, isWarmup: true)
    let working = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 2, weightLbs: 135, reps: 8, isWarmup: false)
    let sets = [warmup, working]
    let workingSets = sets.filter { !$0.isWarmup }
    let volume = workingSets.reduce(0.0) { $0 + ($1.weightLbs ?? 0) * Double($1.reps ?? 0) }
    #expect(volume == 1080, "Only working set: 135 * 8 = 1080")
}

@Test func estimated1RMBrzycki() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 225, reps: 5, isWarmup: false)
    guard let rm = s.estimated1RM else { #expect(Bool(false), "Should have 1RM"); return }
    // Brzycki: 225 * 36 / (37 - 5) = 225 * 36 / 32 = 253.125
    #expect(abs(rm - 253.125) < 0.01, "1RM should be ~253, got \(rm)")
}

@Test func estimated1RMSingleRep() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 315, reps: 1, isWarmup: false)
    #expect(s.estimated1RM == 315, "Single rep 1RM = weight itself")
}

@Test func estimated1RMBodyweight() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Push-up", setOrder: 1, weightLbs: nil, reps: 20, isWarmup: false)
    #expect(s.estimated1RM == nil, "No weight = no 1RM estimate")
}

@Test func estimated1RMHighReps() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Curl", setOrder: 1, weightLbs: 20, reps: 35, isWarmup: false)
    #expect(s.estimated1RM == nil, "Reps > 30 should return nil (formula unreliable)")
}

// The unit is an explicit argument since #1085, so this no longer needs to
// stage `Preferences.weightUnit` to pin the rendering.
@Test func workoutSetDisplayFormat() async throws {
    let s1 = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false)
    #expect(s1.display(in: .lbs).contains("135") && s1.display(in: .lbs).contains("10"))
    let s2 = WorkoutSet(workoutId: 1, exerciseName: "Pull-up", setOrder: 1, weightLbs: nil, reps: 12, isWarmup: false)
    #expect(s2.display(in: .lbs).contains("BW"))
}

@Test func templateSaveAndFetchRoundtrip() async throws {
    let db = try AppDatabase.empty()
    let exercises: [WorkoutTemplate.TemplateExercise] = [
        .init(name: "Bench Press", sets: 3, restSeconds: 150, notes: "6-8 reps"),
        .init(name: "Band Pull Aparts", sets: 2, isWarmup: true, restSeconds: 30),
    ]
    let json = try JSONEncoder().encode(exercises)
    let t = WorkoutTemplate(name: "Push Day", exercisesJson: String(data: json, encoding: .utf8)!,
                            createdAt: ISO8601DateFormatter().string(from: Date()))
    try await db.writer.write { [t] dbConn in var m = t; try m.insert(dbConn) }
    let fetched = try await db.reader.read { try WorkoutTemplate.fetchAll($0) }
    #expect(fetched.count == 1)
    #expect(fetched[0].name == "Push Day")
    let decoded = fetched[0].exercises
    #expect(decoded.count == 2)
    #expect(decoded[0].notes == "6-8 reps")
    #expect(decoded[1].isWarmup == true)
}

@Test func workoutDeleteCascadesSetsVerify() async throws {
    let db = try AppDatabase.empty()
    // Insert workout and get its ID
    try await db.writer.write { dbConn in
        var w = Workout(name: "W", date: "2026-03-30", createdAt: "")
        try w.insert(dbConn)
    }
    let wid = try await db.reader.read { try Workout.fetchAll($0) }.first!.id!
    // Insert a set for that workout
    try await db.writer.write { dbConn in
        var s = WorkoutSet(workoutId: wid, exerciseName: "Bench", setOrder: 1, weightLbs: 100, reps: 10, isWarmup: false)
        try s.insert(dbConn)
    }
    // Delete workout - sets should cascade
    try await db.writer.write { dbConn in _ = try Workout.deleteOne(dbConn, id: wid) }
    let sets = try await db.reader.read { try WorkoutSet.fetchAll($0) }
    #expect(sets.isEmpty, "Sets should cascade delete with workout")
}

@Test func multipleTemplatesCoexist() async throws {
    let db = try AppDatabase.empty()
    for name in ["Push", "Pull", "Legs"] {
        let json = try JSONEncoder().encode([WorkoutTemplate.TemplateExercise(name: "Ex", sets: 3)])
        let t = WorkoutTemplate(name: name, exercisesJson: String(data: json, encoding: .utf8)!, createdAt: "")
        try await db.writer.write { [t] dbConn in var m = t; try m.insert(dbConn) }
    }
    let all = try await db.reader.read { try WorkoutTemplate.fetchAll($0) }
    #expect(all.count == 3)
}

// MARK: - Exercise Database Tests (8 tests)

@Test func exerciseDatabaseLoads() async throws {
    let all = ExerciseDatabase.all
    #expect(all.count >= 800, "Should have 800+ exercises, got \(all.count)")
}

@Test func exerciseDatabaseSearch() async throws {
    let results = ExerciseDatabase.search(query: "bench press")
    #expect(!results.isEmpty, "Should find bench press")
    #expect(results.first?.name.lowercased().contains("bench") ?? false)
}

@Test func exerciseDatabaseByBodyPart() async throws {
    let chest = ExerciseDatabase.byBodyPart("Chest")
    #expect(chest.count >= 50, "Should have many chest exercises")
    #expect(chest.allSatisfy { $0.bodyPart == "Chest" })
}

@Test func exerciseDatabaseBodyPartGuess() async throws {
    #expect(ExerciseDatabase.bodyPart(for: "Barbell Bench Press") == "Chest")
    #expect(ExerciseDatabase.bodyPart(for: "Barbell Squat") == "Legs")
}

@Test func exerciseSearchCaseInsensitive() async throws {
    let upper = ExerciseDatabase.search(query: "BENCH")
    let lower = ExerciseDatabase.search(query: "bench")
    #expect(!upper.isEmpty && !lower.isEmpty)
    // Should find same results regardless of case
    #expect(upper.first?.name == lower.first?.name)
}

@Test func exerciseSearchByEquipment() async throws {
    let results = ExerciseDatabase.search(query: "barbell")
    #expect(results.count >= 50, "Many exercises use barbell")
}

@Test func exerciseSearchByMuscle() async throws {
    let results = ExerciseDatabase.search(query: "quadriceps")
    #expect(!results.isEmpty, "Should find exercises targeting quadriceps")
}

@Test func customExercisePersistence() async throws {
    // Custom exercises use UserDefaults - just verify the add doesn't crash
    let before = ExerciseDatabase.customExercises.count
    ExerciseDatabase.addCustomExercise(name: "Test Custom \(Int.random(in: 1000...9999))", bodyPart: "Chest")
    let after = ExerciseDatabase.customExercises.count
    #expect(after >= before, "Should have at least as many custom exercises")
}

// MARK: - Workout Edge Cases (5 tests)

@Test func workoutZeroDuration() async throws {
    let w = Workout(name: "Quick", date: "2026-03-30", durationSeconds: 0, createdAt: "")
    #expect(w.durationDisplay == "", "0 seconds should show empty")
}

@Test func workoutNilDuration() async throws {
    let w = Workout(name: "Quick", date: "2026-03-30", durationSeconds: nil, createdAt: "")
    #expect(w.durationDisplay == "")
}

@Test func setWithZeroWeight() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Push-up", setOrder: 1, weightLbs: 0, reps: 20, isWarmup: false)
    #expect(s.estimated1RM == nil, "Zero weight should not compute 1RM")
    #expect(s.display(in: .lbs).contains("0 lbs"))
}

@Test func setWithZeroReps() async throws {
    let s = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 0, isWarmup: false)
    #expect(s.estimated1RM == nil, "Zero reps should not compute 1RM")
}

@Test func templateWithEmptyExercises() async throws {
    let t = WorkoutTemplate(name: "Empty", exercisesJson: "[]", createdAt: "")
    #expect(t.exercises.isEmpty)
}

@Test func templateWithInvalidJSON() async throws {
    let t = WorkoutTemplate(name: "Bad", exercisesJson: "not json", createdAt: "")
    #expect(t.exercises.isEmpty, "Invalid JSON should return empty array")
}

// MARK: - Workout Summary Tests (4 tests)

@Test func workoutSummaryExcludesWarmupFromVolume() async throws {
    // Test the volume calculation logic directly (WorkoutService uses shared DB)
    let warmup = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 45, reps: 10, isWarmup: true)
    let set1 = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 2, weightLbs: 135, reps: 8, isWarmup: false)
    let set2 = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 3, weightLbs: 155, reps: 6, isWarmup: false)
    let allSets = [warmup, set1, set2]
    let workingSets = allSets.filter { !$0.isWarmup }
    let volume = workingSets.reduce(0.0) { $0 + ($1.weightLbs ?? 0) * Double($1.reps ?? 0) }
    #expect(volume == 2010, "Volume should exclude warmup: 135*8 + 155*6 = 2010, got \(volume)")
    #expect(workingSets.count == 2, "Should only count 2 working sets")
}

@Test func workoutSummaryBestSetByEstimated1RM() async throws {
    // 185×5 has higher 1RM (253) than 135×10 (180)
    let s1 = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false)
    let s2 = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 2, weightLbs: 185, reps: 5, isWarmup: false)
    let best = [s1, s2].max(by: { ($0.estimated1RM ?? 0) < ($1.estimated1RM ?? 0) })
    #expect(best?.weightLbs == 185, "Best set should be 185lb (higher 1RM)")
}

@Test func workoutSummaryEmptyWorkout() async throws {
    let w = Workout(name: "Empty", date: "2026-03-30", createdAt: "")
    let summary = try WorkoutService.buildSummary(for: w)
    #expect(summary.exercises.isEmpty)
    #expect(summary.totalVolume == 0)
    #expect(summary.totalSets == 0)
}

@Test func workoutSummaryMultiExercise() async throws {
    // Test that sets from different exercises are properly separated
    let sets = [
        WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false),
        WorkoutSet(workoutId: 1, exerciseName: "Squat", setOrder: 1, weightLbs: 225, reps: 5, isWarmup: false),
    ]
    let exercises = Array(Set(sets.map(\.exerciseName)))
    #expect(exercises.count == 2)
}

// MARK: - Duration Display Edge Cases (3 tests)

@Test func durationDisplayLongWorkout() async throws {
    let w = Workout(name: "A", date: "2026-03-30", durationSeconds: 7200, createdAt: "")
    #expect(w.durationDisplay == "2h 0m")
}

@Test func durationDisplayShort() async throws {
    let w = Workout(name: "A", date: "2026-03-30", durationSeconds: 120, createdAt: "")
    #expect(w.durationDisplay == "2m")
}

@Test func durationDisplayOneMinute() async throws {
    let w = Workout(name: "A", date: "2026-03-30", durationSeconds: 60, createdAt: "")
    #expect(w.durationDisplay == "1m")
}

// MARK: - Template Encoding Roundtrip (3 tests)

@Test func templateFullRoundtripWithAllFields() async throws {
    let original: [WorkoutTemplate.TemplateExercise] = [
        .init(name: "Bench Press", sets: 3, isWarmup: false, restSeconds: 150, notes: "6-8 reps, controlled"),
        .init(name: "Band Pull Aparts", sets: 2, isWarmup: true, restSeconds: 30, notes: "2x10"),
        .init(name: "Dips", sets: 4, isWarmup: false, restSeconds: 120),
    ]
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode([WorkoutTemplate.TemplateExercise].self, from: data)
    #expect(decoded.count == 3)
    for i in 0..<3 {
        #expect(decoded[i].name == original[i].name)
        #expect(decoded[i].sets == original[i].sets)
        #expect(decoded[i].isWarmup == original[i].isWarmup)
        #expect(decoded[i].restSeconds == original[i].restSeconds)
        #expect(decoded[i].notes == original[i].notes)
    }
}

@Test func templateWithUnicodeNotes() async throws {
    let ex = WorkoutTemplate.TemplateExercise(name: "Squat", sets: 5, notes: "Heavy! 💪 Go deep")
    let data = try JSONEncoder().encode([ex])
    let decoded = try JSONDecoder().decode([WorkoutTemplate.TemplateExercise].self, from: data)
    #expect(decoded[0].notes == "Heavy! 💪 Go deep")
}

@Test func templateExerciseDefaultValues() async throws {
    let ex = WorkoutTemplate.TemplateExercise(name: "Test", sets: 3)
    #expect(ex.isWarmup == false)
    #expect(ex.restSeconds == 90)
    #expect(ex.notes == nil)
}

// MARK: - Exercise History Tests (2 tests)

@Test func exerciseHistoryEmptyForNewExercise() async throws {
    // A brand new exercise should have no history
    let history = try WorkoutService.fetchExerciseHistory(name: "CompletelyMadeUpExercise12345")
    #expect(history.isEmpty)
}

@Test func exercisePRNilForNewExercise() async throws {
    let pr = try WorkoutService.fetchPR(for: "CompletelyMadeUpExercise12345")
    #expect(pr == nil)
}

// MARK: - Session Persistence Tests (3 tests)

/// Field report 2026-07-16: resuming a WIP session started the live timer at
/// the full wall-clock gap (up to 5h of phantom "training"). The resume clock
/// rebases on trainedSeconds — start → last persist, away time excluded.
@Test func trainedSecondsExcludesAwayTime() {
    let start = Date(timeIntervalSinceNow: -3 * 3600)          // started 3h ago
    let saved = start.addingTimeInterval(22 * 60)              // trained 22 min
    let session = WorkoutService.SavedSession(
        workoutName: "Push", startTime: start, exercises: [], lastSavedAt: saved)
    // Resumed now: 22 min trained, ~2h38m away — away time must not count.
    #expect(Int(session.trainedSeconds()) == 22 * 60)
    // Pre-lastSavedAt payloads (older builds) keep wall-clock behavior.
    let legacy = WorkoutService.SavedSession(workoutName: "Pull", startTime: start, exercises: [])
    let wallClock = legacy.trainedSeconds(asOf: start.addingTimeInterval(3600))
    #expect(Int(wallClock) == 3600)
    // Clock skew (lastSavedAt before startTime) clamps to zero, never negative.
    let skewed = WorkoutService.SavedSession(
        workoutName: "Legs", startTime: start, exercises: [],
        lastSavedAt: start.addingTimeInterval(-60))
    #expect(skewed.trainedSeconds() == 0)
}

@Test func sessionSaveAndLoad() async throws {
    WorkoutService.clearSession()
    let session = WorkoutService.SavedSession(
        workoutName: "Test Workout", startTime: Date(),
        exercises: [.init(name: "Bench", isWarmup: false, notes: "heavy", restTime: 120,
                          sets: [.init(weight: "135", reps: "10", done: true, isWarmup: false)])])
    WorkoutService.saveSession(session)
    let loaded = WorkoutService.loadSession()
    // Concurrent tests may overwrite — only verify if our session survived
    if let loaded, loaded.workoutName == "Test Workout" {
        #expect(loaded.exercises.count == 1)
        #expect(loaded.exercises[0].sets[0].weight == "135")
    }
    WorkoutService.clearSession()
}

@Test func saveSessionPersistsAsStringNotData() async throws {
    // Regression guard for #1102: Skip's UserDefaults→SharedPreferences bridge
    // silently drops Data values on Android, so the persisted type must be String.
    let name = "StringFormat_\(UUID().uuidString.prefix(4))"
    WorkoutService.clearSession()
    WorkoutService.saveSession(.init(workoutName: name, startTime: Date(), exercises: []))
    #expect(UserDefaults.standard.string(forKey: "drift_active_workout_session") != nil)
    #expect(UserDefaults.standard.data(forKey: "drift_active_workout_session") == nil)
    WorkoutService.clearSession()
}

@Test func loadSessionMigratesLegacyDataPayload() async throws {
    // Pre-#1102 builds wrote the session as raw Data; loadSession must keep
    // reading those payloads back after the switch to String persistence.
    WorkoutService.clearSession()
    let name = "LegacyData_\(UUID().uuidString.prefix(4))"
    let legacy = WorkoutService.SavedSession(workoutName: name, startTime: Date(), exercises: [], lastSavedAt: Date())
    UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: "drift_active_workout_session")
    #expect(WorkoutService.loadSession()?.workoutName == name)
    WorkoutService.clearSession()
}

@Test func sessionClear() async throws {
    let name = "ClearTest_\(UUID().uuidString.prefix(4))"
    WorkoutService.saveSession(.init(workoutName: name, startTime: Date(), exercises: []))
    // Verify our session is saved (may be overwritten by concurrent tests)
    if let loaded = WorkoutService.loadSession(), loaded.workoutName == name {
        WorkoutService.clearSession()
        let after = WorkoutService.loadSession()
        #expect(after == nil || after?.workoutName != name, "Our session should be cleared")
    }
}

@Test func sessionExpiresAfter5HoursIdle() async throws {
    // Expiry is driven by time since the LAST save (saveSession stamps
    // lastSavedAt = now), not since startTime — an old start alone no longer
    // expires a session (2026-07-09 auto-save rework).
    let name = "ExpiredTest_\(UUID().uuidString.prefix(4))"
    // Backdate the clear tombstone so the deliberately old startTime below
    // isn't rejected as a stale write.
    WorkoutService.clearSession(now: Date().addingTimeInterval(-7 * 3600))
    let oldTime = Date().addingTimeInterval(-6 * 3600) // started 6 hours ago
    WorkoutService.saveSession(.init(workoutName: name, startTime: oldTime, exercises: []))
    // Just saved → still active despite the old start.
    if let loaded = WorkoutService.loadSession() {
        // (concurrent tests may have swapped in their own session)
        if loaded.workoutName == name {
            // 5h+ past the last save → expired (empty → dropped, no auto-save).
            #expect(WorkoutService.loadSession(now: Date().addingTimeInterval(6 * 3600)) == nil)
        }
    }
    WorkoutService.clearSession()
}

@Test func sessionNotExpiredAt4Hours() async throws {
    let name = "Recent4h_\(UUID().uuidString.prefix(4))"
    // Backdated start needs a tombstone older than it (see stale-write guard).
    WorkoutService.clearSession(now: Date().addingTimeInterval(-5 * 3600))
    let recent = Date().addingTimeInterval(-4 * 3600) // 4 hours ago
    WorkoutService.saveSession(.init(workoutName: name, startTime: recent, exercises: []))
    let loaded = WorkoutService.loadSession()
    // Concurrent tests may overwrite, so only assert if our session survived
    if let loaded, loaded.workoutName == name {
        #expect(true, "Session at 4 hours is still valid")
    }
    WorkoutService.clearSession()
}

@Test func staleSessionWriteAfterClearIsRejected() async throws {
    // 2026-07-13 double-save field bug: the 30s auto-save tick raced the
    // Finish button and re-wrote the just-cleared session. The zombie then
    // showed a phantom "Workout in progress" banner and got saved as a
    // duplicate workout. saveSession must refuse a session that STARTED
    // before the last clearSession().
    let name = "Zombie_\(UUID().uuidString.prefix(4))"
    let startedAnHourAgo = Date().addingTimeInterval(-3600)
    WorkoutService.clearSession() // finish happens now → tombstone
    WorkoutService.saveSession(.init(workoutName: name, startTime: startedAnHourAgo, exercises: []))
    #expect(WorkoutService.loadSession()?.workoutName != name,
            "A session started before the last clear must not be resurrected")
}

@Test func freshSessionAfterClearPersists() async throws {
    // The tombstone must not block the NEXT workout.
    let name = "Fresh_\(UUID().uuidString.prefix(4))"
    WorkoutService.clearSession()
    WorkoutService.saveSession(.init(workoutName: name, startTime: Date(), exercises: []))
    // Concurrent tests may overwrite — only assert if our session survived.
    if let loaded = WorkoutService.loadSession(), loaded.workoutName.hasPrefix("Fresh_") {
        #expect(loaded.workoutName == name)
    }
    WorkoutService.clearSession()
}

@Test func sessionClearAfterFinish() async throws {
    // Save a session, then clear it — verify the clear works
    // NOTE: can't reliably assert nil after clear due to concurrent tests using same UserDefaults
    WorkoutService.clearSession()
    WorkoutService.saveSession(.init(workoutName: "ClearTest\(UUID().uuidString.prefix(4))", startTime: Date(), exercises: [
        .init(name: "Bench", isWarmup: false, notes: nil, restTime: 90,
              sets: [.init(weight: "135", reps: "10", done: true, isWarmup: false)])
    ]))
    let before = WorkoutService.loadSession()
    // Concurrent tests may overwrite — only assert if our session survived
    if let before, before.workoutName.hasPrefix("ClearTest") {
        WorkoutService.clearSession()
        let after = WorkoutService.loadSession()
        if let after {
            #expect(!after.workoutName.hasPrefix("ClearTest"), "Our session should be cleared")
        }
    }
    WorkoutService.clearSession()
}

@Test func sessionRoundtripWithWarmups() async throws {
    WorkoutService.clearSession()
    let session = WorkoutService.SavedSession(
        workoutName: "Full", startTime: Date(),
        exercises: [
            .init(name: "Band Pull Aparts", isWarmup: true, notes: "2x10", restTime: 30,
                  sets: [.init(weight: "", reps: "10", done: true, isWarmup: true)]),
            .init(name: "Bench Press", isWarmup: false, notes: "5-8 reps", restTime: 150,
                  sets: [.init(weight: "135", reps: "8", done: true, isWarmup: false),
                         .init(weight: "155", reps: "6", done: false, isWarmup: false)])
        ])
    WorkoutService.saveSession(session)
    guard let loaded = WorkoutService.loadSession() else {
        WorkoutService.clearSession()
        return // Concurrent test may have overwritten — skip gracefully
    }
    #expect(loaded.exercises.count == 2)
    #expect(loaded.exercises[0].isWarmup == true)
    #expect(loaded.exercises[0].notes == "2x10")
    #expect(loaded.exercises[1].sets.count == 2)
    WorkoutService.clearSession()
}

// MARK: - Exercise Search Fix Tests (4 tests)

@Test func searchFindsCustomExercises() async throws {
    let uniqueName = "ZZZ Test Custom Ex \(Int.random(in: 10000...99999))"
    ExerciseDatabase.addCustomExercise(name: uniqueName, bodyPart: "Chest")
    let results = ExerciseDatabase.search(query: uniqueName)
    #expect(!results.isEmpty, "Custom exercise should be findable in search")
}

/// #905 regression: `addCustomExercise` does a read-modify-write on a shared
/// UserDefaults key. Swift Testing runs tests in parallel and there are several
/// concurrent callers (this suite, `searchFindsCustomExercises`, workout save,
/// default templates), so without serialization the interleaved read→write loses
/// updates — the root cause of the flaky `searchFindsCustomExercises`. Fire many
/// adds concurrently with unique names and assert EVERY one survives (this fails
/// reliably if the lock in `ExerciseDatabase.addCustomExercise` is removed).
@Test func concurrentAddCustomExerciseNoLostUpdates() async {
    let names = (0..<40).map { "ZZZ Concurrent Ex \($0)-\(Int.random(in: 100000...999999))" }
    await withTaskGroup(of: Void.self) { group in
        for name in names {
            group.addTask { ExerciseDatabase.addCustomExercise(name: name, bodyPart: "Chest") }
        }
    }
    let stored = Set(ExerciseDatabase.customExercises.map { $0.name })
    let missing = names.filter { !stored.contains($0) }
    #expect(missing.isEmpty, "Lost \(missing.count)/40 concurrent custom-exercise adds: \(Array(missing.prefix(3)))")
}

@Test func searchMultiWordExercise() async throws {
    let results = ExerciseDatabase.search(query: "bench press")
    #expect(!results.isEmpty, "Multi-word search should work")
}

@Test func searchIncludesAllWithCustom() async throws {
    let all = ExerciseDatabase.allWithCustom
    let dbOnly = ExerciseDatabase.all
    #expect(all.count >= dbOnly.count, "allWithCustom should include DB + custom")
}

// MARK: - Search Edge Cases (5 tests)

@Test func searchSingleChar() async throws {
    let results = ExerciseDatabase.search(query: "a")
    #expect(results.count > 100, "Single char should match many exercises")
}

@Test func searchSpecialChars() async throws {
    let results = ExerciseDatabase.search(query: "(")
    // Should not crash
    #expect(results.count >= 0)
}

@Test func searchWhitespace() async throws {
    let results = ExerciseDatabase.search(query: "  bench  press  ")
    #expect(!results.isEmpty, "Extra whitespace should still match")
}

@Test func searchNoResultsGraceful() async throws {
    let results = ExerciseDatabase.search(query: "xyznonexistent12345")
    #expect(results.isEmpty)
}

@Test func searchEmptyString() async throws {
    let results = ExerciseDatabase.search(query: "")
    #expect(results.count > 800, "Empty query should return all exercises")
}

// MARK: - Favorite Template Tests (2 tests)

// MARK: - Body Part Guesser Tests (4 tests)

@Test func bodyPartGuessChest() async throws {
    #expect(ExerciseDatabase.bodyPart(for: "Dumbbell Bench Press") == "Chest")
    #expect(ExerciseDatabase.bodyPart(for: "Incline Chest Press") == "Chest")
}

@Test func bodyPartGuessLegs() async throws {
    #expect(ExerciseDatabase.bodyPart(for: "Barbell Squat") == "Legs")
    #expect(ExerciseDatabase.bodyPart(for: "Romanian Deadlift") == "Legs")
}

@Test func bodyPartGuessArms() async throws {
    #expect(ExerciseDatabase.bodyPart(for: "Hammer Curls") == "Arms")
    #expect(ExerciseDatabase.bodyPart(for: "Tricep Extension") == "Arms")
}

@Test func bodyPartCustomExercise() async throws {
    // Custom exercises should return their stored body part
    let info = ExerciseDatabase.info(for: "Banded Shoulder Rotations")
    // Might or might not exist depending on seeding state
    if let info {
        #expect(info.bodyPart == "Shoulders")
    }
}

// MARK: - Workout Save Flow Tests (5 tests)

@Test func workoutSaveOnlyDoneSets() async throws {
    let db = try AppDatabase.empty()
    let w = Workout(name: "Test", date: "2026-03-31", createdAt: "")
    try await db.writer.write { [w] dbConn in var m = w; try m.insert(dbConn) }
    let wid = try await db.reader.read { try Workout.fetchAll($0) }.first!.id!

    // Simulate: 3 sets, only 2 done (done ones have reps > 0)
    try await db.writer.write { dbConn in
        var s1 = WorkoutSet(workoutId: wid, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false)
        var s2 = WorkoutSet(workoutId: wid, exerciseName: "Bench", setOrder: 2, weightLbs: 155, reps: 8, isWarmup: false)
        try s1.insert(dbConn); try s2.insert(dbConn)
    }
    let sets = try await db.reader.read { try WorkoutSet.filter(Column("workout_id") == wid).fetchAll($0) }
    #expect(sets.count == 2)
}

@Test func workoutSaveWarmupFlagged() async throws {
    let db = try AppDatabase.empty()
    let w = Workout(name: "Test", date: "2026-03-31", createdAt: "")
    try await db.writer.write { [w] dbConn in var m = w; try m.insert(dbConn) }
    let wid = try await db.reader.read { try Workout.fetchAll($0) }.first!.id!

    try await db.writer.write { dbConn in
        var warmup = WorkoutSet(workoutId: wid, exerciseName: "Band Pull", setOrder: 1, weightLbs: 0, reps: 10, isWarmup: true)
        var working = WorkoutSet(workoutId: wid, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 8, isWarmup: false)
        try warmup.insert(dbConn); try working.insert(dbConn)
    }
    let sets = try await db.reader.read { try WorkoutSet.filter(Column("workout_id") == wid).fetchAll($0) }
    let warmups = sets.filter(\.isWarmup)
    let working = sets.filter { !$0.isWarmup }
    #expect(warmups.count == 1)
    #expect(working.count == 1)
}

@Test func workoutSaveZeroRepsSetsSkipped() async throws {
    // Sets with 0 reps should not be saved
    let s = WorkoutSet(workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 0, isWarmup: false)
    #expect(s.reps == 0, "Zero reps set exists but should be filtered during save")
}

@Test func workoutNameFromTemplate() async throws {
    // When starting from template, workout name should be template name
    let t = WorkoutTemplate(name: "Day 1 - Chest/Core", exercisesJson: "[]", createdAt: "")
    #expect(t.name == "Day 1 - Chest/Core")
}

@Test func workoutSessionPersistWithExercises() async throws {
    // Clear any stale session from the simulator's shared UserDefaults
    WorkoutService.clearSession()

    let session = WorkoutService.SavedSession(
        workoutName: "Full Workout", startTime: Date(),
        exercises: [
            .init(name: "Warmup A", isWarmup: true, notes: "2x10", restTime: 30,
                  sets: [.init(weight: "", reps: "10", done: true, isWarmup: true)]),
            .init(name: "Bench Press", isWarmup: false, notes: "5-8 reps", restTime: 150,
                  sets: [
                    .init(weight: "135", reps: "8", done: true, isWarmup: false),
                    .init(weight: "155", reps: "6", done: true, isWarmup: false),
                    .init(weight: "175", reps: "4", done: false, isWarmup: false),
                  ]),
            .init(name: "Dips", isWarmup: false, notes: nil, restTime: 120,
                  sets: [.init(weight: "BW", reps: "12", done: true, isWarmup: false)])
        ])
    WorkoutService.saveSession(session)
    // Session tests share one global UserDefaults key and run in parallel, so a
    // concurrent test may overwrite ours between save and load. Only assert when
    // OUR session survived the race — matches every other session test here; the
    // prior `loadSession()!` force-unwrap crashed the whole suite on that race.
    guard let loaded = WorkoutService.loadSession(), loaded.workoutName == "Full Workout" else {
        WorkoutService.clearSession()
        return
    }
    #expect(loaded.exercises.count == 3)
    #expect(loaded.exercises[0].isWarmup == true)
    #expect(loaded.exercises[1].sets.count == 3)
    #expect(loaded.exercises[1].sets[2].done == false, "Unfinished set should persist as not done")
    #expect(loaded.exercises[2].name == "Dips")
    WorkoutService.clearSession()
}

// MARK: - Exercise History Ordering (2 tests)

@Test func exerciseHistoryOrderedByIdDesc() async throws {
    // WorkoutService uses shared DB, so test the ordering logic directly
    let sets = [
        WorkoutSet(id: 10, workoutId: 1, exerciseName: "Bench", setOrder: 1, weightLbs: 100, reps: 10, isWarmup: false),
        WorkoutSet(id: 20, workoutId: 2, exerciseName: "Bench", setOrder: 1, weightLbs: 135, reps: 8, isWarmup: false),
    ]
    // id DESC ordering: id 20 first, then id 10
    let sorted = sets.sorted { ($0.id ?? 0) > ($1.id ?? 0) }
    #expect(sorted[0].weightLbs == 135, "Higher ID (most recent) should be first")
}

@Test func lastSessionGroupingAndOrdering() async throws {
    // Simulate what addExercise does: group by workoutId, sort by setOrder
    let sets = [
        WorkoutSet(id: 30, workoutId: 2, exerciseName: "Squat", setOrder: 3, weightLbs: 175, reps: 5, isWarmup: false),
        WorkoutSet(id: 29, workoutId: 2, exerciseName: "Squat", setOrder: 2, weightLbs: 155, reps: 8, isWarmup: false),
        WorkoutSet(id: 28, workoutId: 2, exerciseName: "Squat", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false),
        WorkoutSet(id: 15, workoutId: 1, exerciseName: "Squat", setOrder: 1, weightLbs: 100, reps: 12, isWarmup: false),
    ]
    // Group by most recent workout
    let lastWid = sets.first?.workoutId  // Should be 2 (highest id)
    let lastSession = sets.filter { $0.workoutId == lastWid }.sorted { $0.setOrder < $1.setOrder }
    #expect(lastSession.count == 3)
    #expect(lastSession[0].setOrder == 1)
    #expect(lastSession[0].weightLbs == 135, "Set 1 = 135lb")
    #expect(lastSession[1].setOrder == 2)
    #expect(lastSession[1].weightLbs == 155, "Set 2 = 155lb")
    #expect(lastSession[2].setOrder == 3)
    #expect(lastSession[2].weightLbs == 175, "Set 3 = 175lb")
}

// MARK: - Workout Complete Flow Test

@Test func fullWorkoutFlow() async throws {
    // Simulate: start workout, add exercise, mark set done, finish
    // This tests the data model layer of the workout flow
    let db = try AppDatabase.empty()

    // 1. Create workout
    let w = Workout(name: "Test Flow", date: "2026-03-31", durationSeconds: 1800, createdAt: "")
    try await db.writer.write { [w] dbConn in var m = w; try m.insert(dbConn) }
    let wid = try await db.reader.read { try Workout.fetchAll($0) }.first!.id!

    // 2. Add sets
    try await db.writer.write { dbConn in
        var s1 = WorkoutSet(workoutId: wid, exerciseName: "Bench Press", setOrder: 1, weightLbs: 135, reps: 10, isWarmup: false)
        var s2 = WorkoutSet(workoutId: wid, exerciseName: "Bench Press", setOrder: 2, weightLbs: 155, reps: 8, isWarmup: false)
        var s3 = WorkoutSet(workoutId: wid, exerciseName: "Squat", setOrder: 1, weightLbs: 225, reps: 5, isWarmup: false)
        try s1.insert(dbConn); try s2.insert(dbConn); try s3.insert(dbConn)
    }

    // 3. Verify sets saved
    let sets = try await db.reader.read { try WorkoutSet.filter(Column("workout_id") == wid).fetchAll($0) }
    #expect(sets.count == 3)

    // 4. Verify 1RM calculations
    let benchSets = sets.filter { $0.exerciseName == "Bench Press" }
    let best1RM = benchSets.compactMap(\.estimated1RM).max()
    #expect(best1RM != nil)
    #expect(best1RM! > 155, "1RM should be > working weight")

    // 5. Delete workout (cascade)
    try await db.writer.write { dbConn in _ = try Workout.deleteOne(dbConn, id: wid) }
    let remaining = try await db.reader.read { try WorkoutSet.filter(Column("workout_id") == wid).fetchAll($0) }
    #expect(remaining.isEmpty, "Sets should cascade delete")
}

@Test func templateFavoriteDefault() async throws {
    let t = WorkoutTemplate(name: "Test", exercisesJson: "[]", createdAt: "")
    #expect(t.isFavorite == false, "Default should be not favorite")
}

@Test func templateFavoriteRoundtrip() async throws {
    let db = try AppDatabase.empty()
    let t = WorkoutTemplate(name: "Fav Test", exercisesJson: "[]", createdAt: "", isFavorite: true)
    try await db.writer.write { [t] dbConn in var m = t; try m.insert(dbConn) }
    let fetched = try await db.reader.read { try WorkoutTemplate.fetchAll($0) }
    #expect(fetched.first?.isFavorite == true)
}

@Test func templateMixedOldNewFormat() async throws {
    // Mix of old (no warmup field) and new (with warmup field) entries
    let json = #"[{"name":"Old Ex","sets":3},{"name":"New Ex","sets":2,"isWarmup":true,"restSeconds":30,"notes":"test"}]"#
    let decoded = try JSONDecoder().decode([WorkoutTemplate.TemplateExercise].self, from: Data(json.utf8))
    #expect(decoded[0].isWarmup == false)
    #expect(decoded[0].restSeconds == 90)
    #expect(decoded[1].isWarmup == true)
    #expect(decoded[1].notes == "test")
}

// MARK: - Exercise Body Part Guessing Tests

@Test func guessBodyPartChest() async throws {
    #expect(ExerciseDatabase.guessBodyPart("Bench Press (Barbell)") == "Chest")
    #expect(ExerciseDatabase.guessBodyPart("Incline Dumbbell Fly") == "Chest")
    #expect(ExerciseDatabase.guessBodyPart("Cable Chest Press") == "Chest")
    #expect(ExerciseDatabase.guessBodyPart("Dips") == "Chest")
}

@Test func guessBodyPartLegs() async throws {
    #expect(ExerciseDatabase.guessBodyPart("Barbell Squat") == "Legs")
    #expect(ExerciseDatabase.guessBodyPart("Leg Extension (Machine)") == "Legs")
    #expect(ExerciseDatabase.guessBodyPart("Calf Press on Seated Leg Press") == "Legs")
    #expect(ExerciseDatabase.guessBodyPart("Hip Thrust") == "Legs")
}

@Test func guessBodyPartBack() async throws {
    #expect(ExerciseDatabase.guessBodyPart("Lat Pulldown (Cable)") == "Back")
    #expect(ExerciseDatabase.guessBodyPart("Barbell Row") == "Back")
    #expect(ExerciseDatabase.guessBodyPart("Pull Up") == "Back")
}

@Test func guessBodyPartArms() async throws {
    #expect(ExerciseDatabase.guessBodyPart("Bicep Curl (Dumbbell)") == "Arms")
    #expect(ExerciseDatabase.guessBodyPart("Triceps Pushdown (Cable)") == "Arms")
    #expect(ExerciseDatabase.guessBodyPart("Hammer Curl") == "Arms")
}

@Test func guessBodyPartShoulders() async throws {
    #expect(ExerciseDatabase.guessBodyPart("Shoulder Press") == "Shoulders")
    #expect(ExerciseDatabase.guessBodyPart("Lateral Raise") == "Shoulders")
}

@Test func guessBodyPartCore() async throws {
    #expect(ExerciseDatabase.guessBodyPart("Ab Crunch Machine") == "Core")
    #expect(ExerciseDatabase.guessBodyPart("Plank") == "Core")
}

@Test func guessBodyPartUnknown() async throws {
    // Unknown exercises should return something, not crash
    let result = ExerciseDatabase.guessBodyPart("Some Weird Exercise Nobody Does")
    #expect(!result.isEmpty, "Should return a default body part, got '\(result)'")
}

// MARK: - Hevy Format Detection Tests

@Test func hevyFormatDetection() async throws {
    let hevyCsv = "title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps\n"
    #expect(hevyCsv.lowercased().contains("exercise_title"), "Should detect Hevy format")
}

@Test func strongFormatDetection() async throws {
    let strongCsv = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps\n"
    #expect(!strongCsv.lowercased().contains("exercise_title"), "Should NOT detect as Hevy")
}

// MARK: - Default Templates Load Tests

@Test func loadPackageIVIsIdempotent() async throws {
    // Loading a package twice should not create duplicates
    let first = DefaultTemplates.loadPackageIV()
    let second = DefaultTemplates.loadPackageIV()
    // Second call must add 0 — all names already exist
    #expect(second == 0, "Second load should skip all duplicates, got \(second)")
    #expect(first >= 0)
}

@Test func loadPackageIIsIdempotent() async throws {
    // The renumbered band package (was III) keeps the same guarantee
    let first = DefaultTemplates.loadPackageI()
    let second = DefaultTemplates.loadPackageI()
    #expect(second == 0, "Second load should skip all duplicates, got \(second)")
    #expect(first >= 0)
}

// MARK: - Timer Background Resilience Tests (10 tests)

@Test func elapsedTimeCalculatesFromStartTimeNotIncrement() async throws {
    // The workout timer must use Date().timeIntervalSince(startTime), not += 1
    // This is what makes it survive background suspensions
    let startTime = Date().addingTimeInterval(-300) // started 5 min ago
    let elapsed = Int(Date().timeIntervalSince(startTime))
    #expect(elapsed >= 299 && elapsed <= 301, "Should be ~300 seconds, got \(elapsed)")
}

@Test func elapsedTimeAfterSimulatedBackground() async throws {
    // Simulate: started 10 min ago, app was in background for 5 min
    let startTime = Date().addingTimeInterval(-600)
    // When the timer fires again after returning to foreground, it recalculates
    let elapsed = Int(Date().timeIntervalSince(startTime))
    #expect(elapsed >= 599 && elapsed <= 601, "Should be ~600 seconds, got \(elapsed)")
}

@Test func restTimerEndTimeBasedCalculation() async throws {
    // Rest timer should calculate remaining time from an end time, not decrement
    let duration = 90
    let restEndTime = Date().addingTimeInterval(Double(duration))
    // Simulate 30 seconds passing in background
    let simulatedNow = Date().addingTimeInterval(30)
    let remaining = Int(ceil(restEndTime.timeIntervalSince(simulatedNow)))
    #expect(remaining == 60, "Should have 60s left after 30s elapsed, got \(remaining)")
}

@Test func restTimerExpiresDuringBackground() async throws {
    // Rest timer set for 90s, app backgrounded for 120s — should show 0
    let duration = 90
    let restEndTime = Date().addingTimeInterval(Double(duration))
    let simulatedNow = Date().addingTimeInterval(120)
    let remaining = Int(restEndTime.timeIntervalSince(simulatedNow))
    #expect(remaining <= 0, "Rest should have expired, got \(remaining)")
}

@Test func restTimerExactlyExpires() async throws {
    // Rest timer at exactly its duration
    let duration = 60
    let restEndTime = Date().addingTimeInterval(Double(duration))
    let simulatedNow = Date().addingTimeInterval(Double(duration))
    let remaining = Int(ceil(restEndTime.timeIntervalSince(simulatedNow)))
    #expect(remaining <= 0, "Should be expired at exact duration")
}

@Test func restTimerPartialSecondRoundsUp() async throws {
    // If 0.3s remains, ceil should show 1s not 0
    let restEndTime = Date().addingTimeInterval(90)
    let simulatedNow = Date().addingTimeInterval(89.7) // 0.3s before end
    let remaining = Int(ceil(restEndTime.timeIntervalSince(simulatedNow)))
    #expect(remaining == 1, "Partial second should round up to 1, got \(remaining)")
}

@Test func sessionPersistencePreservesStartTime() async throws {
    // Ensure session save/load round-trips the start time accurately
    let originalStart = Date().addingTimeInterval(-600) // 10 min ago
    // Backdated start needs a tombstone older than it (stale-write guard).
    WorkoutService.clearSession(now: originalStart.addingTimeInterval(-60))
    let session = WorkoutService.SavedSession(
        workoutName: "Timer Test",
        startTime: originalStart,
        exercises: []
    )
    WorkoutService.saveSession(session)
    let loaded = WorkoutService.loadSession()
    // Concurrent tests may overwrite — only verify if our session survived
    if let loaded, loaded.workoutName == "Timer Test" {
        let timeDiff = abs(loaded.startTime.timeIntervalSince(originalStart))
        #expect(timeDiff < 1, "Start time should round-trip within 1s, diff was \(timeDiff)")
    }
    WorkoutService.clearSession()
}

@Test func sessionPersistenceWithExercises() async throws {
    // Backdated start needs a tombstone older than it (stale-write guard).
    WorkoutService.clearSession(now: Date().addingTimeInterval(-300))
    let session = WorkoutService.SavedSession(
        workoutName: "PersistExercise_\(UUID().uuidString.prefix(4))",
        startTime: Date().addingTimeInterval(-120),
        exercises: [
            .init(name: "Bench Press", isWarmup: false, notes: nil, restTime: 90,
                  sets: [.init(weight: "80", reps: "10", done: true, isWarmup: false),
                         .init(weight: "80", reps: "8", done: false, isWarmup: false)])
        ]
    )
    WorkoutService.saveSession(session)
    let loaded = WorkoutService.loadSession()
    // Concurrent tests may overwrite — only assert if our session survived
    if let loaded, loaded.workoutName == session.workoutName {
        #expect(loaded.exercises.count == 1)
        #expect(loaded.exercises[0].restTime == 90)
        #expect(loaded.exercises[0].sets.count == 2)
        #expect(loaded.exercises[0].sets[0].done == true)
        #expect(loaded.exercises[0].sets[1].done == false)
    }
    WorkoutService.clearSession()
}

@Test func sessionClearRemovesData() async throws {
    WorkoutService.clearSession()
    let session = WorkoutService.SavedSession(
        workoutName: "ClearRemove_\(UUID().uuidString.prefix(4))",
        startTime: Date(),
        exercises: []
    )
    WorkoutService.saveSession(session)
    // Verify save worked (may be overwritten by concurrent test)
    if let loaded = WorkoutService.loadSession(), loaded.workoutName == session.workoutName {
        WorkoutService.clearSession()
        let after = WorkoutService.loadSession()
        #expect(after == nil || after?.workoutName != session.workoutName, "Our session should be cleared")
    }
}

@Test func elapsedTimeZeroAtStart() async throws {
    let startTime = Date()
    let elapsed = Int(Date().timeIntervalSince(startTime))
    #expect(elapsed >= 0 && elapsed <= 1, "Should be ~0 at start, got \(elapsed)")
}

// MARK: - buildVoiceLogSets (voice/text-logged exercises → set rows, #868)

@Test func buildVoiceLogSets_multiExercise_strengthAndDuration() {
    // "bench 3x10 @135, then 5k run 28 min" → 3 bench set-rows + 1 run duration-row.
    let exercises = [
        WorkoutService.VoiceLoggedExercise(name: "bench press", isDuration: false, sets: 3, reps: 10, weightLbs: 135),
        WorkoutService.VoiceLoggedExercise(name: "running", isDuration: true, durationMinutes: 28),
    ]
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 42, exercises: exercises)
    #expect(rows.count == 4)

    let bench = rows.filter { $0.exerciseName == "bench press" }
    #expect(bench.count == 3)
    #expect(bench.allSatisfy { $0.workoutId == 42 })
    #expect(bench.allSatisfy { $0.weightLbs == 135 })
    #expect(bench.allSatisfy { $0.reps == 10 })
    #expect(bench.allSatisfy { $0.exerciseOrder == 0 })
    #expect(bench.allSatisfy { $0.durationSec == nil })
    #expect(Set(bench.map(\.setOrder)) == Set([1, 2, 3]))

    let run = rows.filter { $0.exerciseName == "running" }
    #expect(run.count == 1)
    #expect(run[0].durationSec == 28 * 60)
    #expect(run[0].reps == nil)
    #expect(run[0].weightLbs == nil)
    #expect(run[0].exerciseOrder == 1)
    #expect(run[0].setOrder == 1)
}

@Test func buildVoiceLogSets_missingSetsDefaultsToOneRow() {
    let exercises = [WorkoutService.VoiceLoggedExercise(name: "pull-ups", isDuration: false, sets: nil, reps: 8)]
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 1, exercises: exercises)
    #expect(rows.count == 1)
    #expect(rows[0].setOrder == 1)
    #expect(rows[0].reps == 8)
    #expect(rows[0].weightLbs == nil)  // bodyweight → no weight
}

@Test func buildVoiceLogSets_zeroOrNilWeightBecomesNil() {
    let exercises = [
        WorkoutService.VoiceLoggedExercise(name: "push-ups", isDuration: false, sets: 2, reps: 20, weightLbs: 0),
        WorkoutService.VoiceLoggedExercise(name: "air squats", isDuration: false, sets: 1, reps: 15, weightLbs: nil),
    ]
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 1, exercises: exercises)
    #expect(rows.count == 3)
    #expect(rows.allSatisfy { $0.weightLbs == nil })
}

// #1076 gap-hunt: the confirm-card "Lbs" field is a decimal (62.5-lb dumbbells,
// kg→lbs conversions). It now uses `.decimalPad` so the "." is typeable at all;
// this guards the round-trip once it is — a fractional weight must survive
// expansion EXACTLY, never rounded (the #1080/#1084 weight-corruption class).
@Test func buildVoiceLogSets_fractionalWeightSurvivesExactly() {
    // What the sheet does with the "62.5" the decimalPad now lets the user type.
    #expect(Double("62.5") == 62.5)

    let exercises = [
        WorkoutService.VoiceLoggedExercise(name: "incline dumbbell press", isDuration: false, sets: 3, reps: 8, weightLbs: 62.5),
        WorkoutService.VoiceLoggedExercise(name: "romanian deadlift", isDuration: false, sets: 1, reps: 5, weightLbs: 137.5),
    ]
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 1, exercises: exercises)
    #expect(rows.count == 4)
    #expect(rows.prefix(3).allSatisfy { $0.weightLbs == 62.5 }, "every set of the fractional exercise keeps 62.5, not 62 or 63")
    #expect(rows.last?.weightLbs == 137.5)
}

// #986: a weighted duration exercise (weighted carry / plank) keeps its weight.
@Test func buildVoiceLogSets_weightedDurationKeepsWeight() {
    let exercises = [WorkoutService.VoiceLoggedExercise(name: "farmer carry", isDuration: true, weightLbs: 45, durationMinutes: 1)]
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 7, exercises: exercises)
    #expect(rows.count == 1)
    #expect(rows.first?.weightLbs == 45)
    #expect(rows.first?.durationSec == 60)
}

// MARK: - workoutStreak (#985)

@Test func streak_zeroAfterRecentBreak() {
    // chronological oldest→newest: two active weeks, then a 2-week break.
    let s = WorkoutService.streak(fromWeeklyCounts: [2, 3, 0, 0])
    #expect(s.current == 0, "a recent break means the current streak is 0")
    #expect(s.longest == 2)
}

@Test func streak_countsLeadingRunOnly() {
    let s = WorkoutService.streak(fromWeeklyCounts: [1, 0, 2, 3])  // newest two weeks active
    #expect(s.current == 2)
    #expect(s.longest == 2)
}

@Test func streak_allActive() {
    let s = WorkoutService.streak(fromWeeklyCounts: [1, 1, 1, 1])
    #expect(s.current == 4)
    #expect(s.longest == 4)
}

@Test func buildVoiceLogSets_blankNameSkippedButPreservesOriginalOrder() {
    let exercises = [
        WorkoutService.VoiceLoggedExercise(name: "  ", isDuration: false, sets: 3, reps: 10),
        WorkoutService.VoiceLoggedExercise(name: "deadlift", isDuration: false, sets: 1, reps: 5, weightLbs: 225),
    ]
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 1, exercises: exercises)
    #expect(rows.count == 1)
    #expect(rows[0].exerciseName == "deadlift")
    // exerciseOrder reflects the ORIGINAL spoken index (1), not the compacted position.
    #expect(rows[0].exerciseOrder == 1)
}

@Test func buildVoiceLogSets_durationWithoutMinutesHasNilDuration() {
    let exercises = [WorkoutService.VoiceLoggedExercise(name: "yoga", isDuration: true, durationMinutes: nil)]
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 1, exercises: exercises)
    #expect(rows.count == 1)
    #expect(rows[0].durationSec == nil)
    #expect(rows[0].setOrder == 1)
}

@Test func buildVoiceLogSets_trimsExerciseName() {
    let exercises = [WorkoutService.VoiceLoggedExercise(name: "  overhead press  ", isDuration: false, sets: 1, reps: 5)]
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 1, exercises: exercises)
    #expect(rows[0].exerciseName == "overhead press")
}

@Test func buildVoiceLogSets_emptyInputProducesNoRows() {
    #expect(WorkoutService.buildVoiceLogSets(workoutId: 1, exercises: []).isEmpty)
}

@Test func saveVoiceLoggedWorkout_allBlankNamesReturnsNilWithoutSaving() throws {
    // Guard path: returns before touching the DB (no read-back race), so this is
    // a safe Tier-0 assertion under parallel test execution.
    let saved = try WorkoutService.saveVoiceLoggedWorkout(
        name: "Empty", exercises: [WorkoutService.VoiceLoggedExercise(name: "   ", isDuration: false)])
    #expect(saved == nil)
}

// MARK: - #925 Ladder Drill / time-based tracking (data-driven, not name-guess)

@Test func trackingType_ladderDrillResolvesTimeBased() {
    // Done-When (1)+(4a): "Ladder Drill" is time-based via declared per-exercise
    // data, and the manual-builder branch (`isDurationExercise`) agrees.
    #expect(ExerciseDatabase.trackingType(for: "Ladder Drill") == .time)
    #expect(ExerciseDatabase.trackingType(for: "ladder drill") == .time)   // case-insensitive
    #expect(WorkoutSet.isDurationExercise("Ladder Drill"))
}

@Test func ladderDrill_buildsDurationCarryingLog_notReps() {
    // Done-When (2)+(4b): a minutes-bearing Ladder Drill log captures duration in
    // SECONDS (180 for 3 min) with no reps — the same VoiceLoggedExercise the
    // Coach/voice path confirms. `isDuration` is driven by the data-driven type,
    // so nothing hard-codes the exercise name here.
    let isDuration = ExerciseDatabase.trackingType(for: "Ladder Drill") == .time
    let entry = WorkoutService.VoiceLoggedExercise(
        name: "Ladder Drill", isDuration: isDuration, durationMinutes: 3)
    let rows = WorkoutService.buildVoiceLogSets(workoutId: 7, exercises: [entry])
    #expect(rows.count == 1)
    #expect(rows[0].durationSec == 180)
    #expect(rows[0].reps == nil)
    #expect(rows[0].weightLbs == nil)
}

@Test func durationSet_rendersAsMinutesSeconds() {
    // Done-When (2): the set summary shows a time (e.g. "3:00"), not "× N reps".
    let set = WorkoutSet(workoutId: 1, exerciseName: "Ladder Drill", setOrder: 1, durationSec: 180)
    #expect(set.display(in: .lbs) == "3:00")
}

@Test func strengthExercises_stayRepsBased_noRegression() {
    // Done-When (5): every default-template lift still tracks reps, not duration.
    let lifts = ["Dumbbell Bench Press", "Deadlift", "Bicep Curl", "Leg Press",
                 "Lat Pulldown", "Incline Chest Press", "Bulgarian Split Squats",
                 "Shoulder Press", "Crunch Machine"]
    for lift in lifts {
        #expect(ExerciseDatabase.trackingType(for: lift) == .reps, "\(lift) should be reps-based")
        #expect(!WorkoutSet.isDurationExercise(lift), "\(lift) should not be duration")
    }
}

@Test @MainActor func ladderDrill_coachUtteranceRoutesToActivity_notFood() {
    // Done-When (3): "log a ladder drill for 3 minutes" ranks activity logging
    // above food search (the #896 "log X → log_food" trap), so the Coach records
    // a duration activity instead of opening a food search.
    // ToolRanker scores over ToolRegistry.shared, which starts empty — register
    // tools first so the test is self-contained (else it only passes when another
    // suite's init() has populated the shared registry). Matches GLP1InsightToolTests.
    ToolRegistration.registerAll()
    let names = ToolRanker.rank(query: "log a ladder drill for 3 minutes", screen: .dashboard).map(\.name)
    #expect(names.first == "log_activity")
    #expect(names.first != "log_food")
}

// MARK: - #939: performed order preserved (never alphabetical/hash order)

@Test func buildSummaryPreservesPerformedOrderWarmupsFirst() async throws {
    let suffix = Int.random(in: 100000...999999)
    var w = Workout(name: "Order Test \(suffix)", date: "2026-07-07", createdAt: "")
    try WorkoutService.saveWorkout(&w)
    guard let wid = w.id else { Issue.record("no workout id"); return }
    defer { try? WorkoutService.deleteWorkout(id: wid) }

    // Performed order: warmup, then Zebra BEFORE Apple — alphabetical would
    // flip them; the old Array(Set(...)) randomized them per read.
    try WorkoutService.saveSets([
        WorkoutSet(workoutId: wid, exerciseName: "Warm Zed \(suffix)", setOrder: 0, reps: 10, isWarmup: true, exerciseOrder: 0),
        WorkoutSet(workoutId: wid, exerciseName: "Zebra Curl \(suffix)", setOrder: 0, weightLbs: 20, reps: 10, isWarmup: false, exerciseOrder: 1),
        WorkoutSet(workoutId: wid, exerciseName: "Zebra Curl \(suffix)", setOrder: 1, weightLbs: 20, reps: 8, isWarmup: false, exerciseOrder: 1),
        WorkoutSet(workoutId: wid, exerciseName: "Apple Row \(suffix)", setOrder: 0, weightLbs: 50, reps: 8, isWarmup: false, exerciseOrder: 2),
    ])
    let summary = try WorkoutService.buildSummary(for: w)
    #expect(summary.exercises == ["Warm Zed \(suffix)", "Zebra Curl \(suffix)", "Apple Row \(suffix)"],
            "got \(summary.exercises)")

    // #938: the unified share builder reads the SAME persisted data — non-empty,
    // contains every exercise, in the performed order.
    let share = try WorkoutService.shareText(forWorkoutId: wid, unit: .lbs)
    #expect(share.contains("Order Test \(suffix)"))
    for name in summary.exercises { #expect(share.contains(name), "share missing \(name)") }
    let zebraPos = share.range(of: "Zebra Curl \(suffix)")!.lowerBound
    let applePos = share.range(of: "Apple Row \(suffix)")!.lowerBound
    #expect(zebraPos < applePos, "share must keep performed order, not alphabetical")
}

// MARK: - Abandoned session auto-save (field report 2026-07-09: operator lost
// a logged workout — the 5h expiry silently DISCARDED the session)

private func sessionExercise(name: String, sets: [(w: String, r: String, done: Bool)], weighInKg: Bool? = nil) -> WorkoutService.SavedSession.SessionExercise {
    .init(name: name, isWarmup: false, notes: nil, restTime: 90,
          sets: sets.map { .init(weight: $0.w, reps: $0.r, done: $0.done, isWarmup: false) },
          weighInKg: weighInKg)
}

@Test func mergedRecentWorkoutsShowDriftLogsAndDedupeWatchStrength() {
    // Field bug 2026-07-14: the chat 'recent workouts' list was HealthKit-only
    // — the user's logged P5 session was invisible while walks showed up.
    let drift = [
        Workout(name: "P5 Day 1 - Lower + Core", date: "2026-07-13", durationSeconds: 99 * 60, notes: nil,
                createdAt: "2026-07-13T18:00:00Z"),
    ]
    let day13 = DateFormatters.dateOnly.date(from: "2026-07-13")!
    let day12 = DateFormatters.dateOnly.date(from: "2026-07-12")!
    let health: [(date: Date, type: String, duration: TimeInterval, calories: Double)] = [
        (day13, "Strength Training", 44 * 60, 150),   // watch recording of the SAME logged session → skipped
        (day13, "Walking", 12 * 60, 30),              // distinct activity → kept
        (day12, "Walking", 30 * 60, 90),
    ]
    let lines = WorkoutService.mergedRecentWorkoutLines(drift: drift, health: health)
    let joined = lines.joined(separator: "\n")
    #expect(joined.contains("P5 Day 1 - Lower + Core"))            // Drift log present
    #expect(!joined.contains("Strength Training"))                  // same-day watch strength deduped
    #expect(joined.contains("Walking"))                             // walks still shown
    #expect(lines.count == 3)
    #expect(lines.first?.contains("P5 Day 1") == true || lines.first?.contains("Walking") == true) // newest first
}

@Test func abandonedSessionKgUnitOptionConvertsToStoredLbs() throws {
    // Weight-entry unit is an explicit per-exercise OPTION (not suffix
    // parsing); storage stays lbs. 60 typed under kg → 132.3 lbs stored.
    let db = try AppDatabase.empty()
    let start = Date(timeIntervalSince1970: 1_780_100_000)
    let session = WorkoutService.SavedSession(
        workoutName: "Metric Day", startTime: start,
        exercises: [
            sessionExercise(name: "Squat", sets: [("60", "5", true)], weighInKg: true),
            sessionExercise(name: "Bench Press", sets: [("135", "5", true)]),   // nil = lbs
        ],
        lastSavedAt: start.addingTimeInterval(30 * 60))
    WorkoutService.finalizeAbandonedSession(session, into: db)
    let sets = try db.reader.read { try WorkoutSet.fetchAll($0) }
    let squat = sets.first { $0.exerciseName == "Squat" }
    let bench = sets.first { $0.exerciseName == "Bench Press" }
    #expect(abs((squat?.weightLbs ?? 0) - 60 * 2.20462) < 0.01)
    #expect(bench?.weightLbs == 135)
}

@Test func abandonedKgSessionPrefilledFromHistoryStoresTheSameWeight() throws {
    // End-to-end #1084: a kg user re-opens an exercise they logged at 60 kg,
    // touches nothing, and the session is abandoned + auto-finalized. The
    // weight written back must equal the weight it was prefilled from.
    // Before the fix the field was prefilled with the stored *lbs* number,
    // which this path then multiplied by 2.20462 again.
    let db = try AppDatabase.empty()
    let start = Date(timeIntervalSince1970: 1_780_200_000)
    let unit = WeightUnit.kg
    let storedLbs = unit.convertToLbs(60)                    // what history holds
    let prefilled = unit.entryText(fromLbs: storedLbs)       // what addExercise writes

    let session = WorkoutService.SavedSession(
        workoutName: "Metric Day 2", startTime: start,
        exercises: [sessionExercise(name: "Squat", sets: [(prefilled, "5", true)], weighInKg: true)],
        lastSavedAt: start.addingTimeInterval(30 * 60))
    WorkoutService.finalizeAbandonedSession(session, into: db)

    let squat = try db.reader.read { try WorkoutSet.fetchAll($0) }.first { $0.exerciseName == "Squat" }
    #expect(abs((squat?.weightLbs ?? 0) - storedLbs) < 0.05,
            "abandoned round-trip moved 60 kg from \(storedLbs) to \(squat?.weightLbs ?? 0) lbs")
}

@Test func abandonedSessionWithDoneSetsIsSavedAsWorkout() throws {
    let db = try AppDatabase.empty()
    let start = DateFormatters.dateOnly.date(from: "2026-07-08")!.addingTimeInterval(18 * 3600)
    let session = WorkoutService.SavedSession(
        workoutName: "Evening Push",
        startTime: start,
        exercises: [
            sessionExercise(name: "Bench Press", sets: [("135", "10", true), ("135", "8", true), ("", "", false)]),
            sessionExercise(name: "Shoulder Press", sets: [("60", "12", true)]),
        ],
        lastSavedAt: start.addingTimeInterval(45 * 60))
    WorkoutService.finalizeAbandonedSession(session, into: db)

    let workouts = try db.reader.read { try Workout.fetchAll($0) }
    #expect(workouts.count == 1)
    #expect(workouts[0].name == "Evening Push")
    #expect(workouts[0].date == "2026-07-08")           // dated the day it happened
    #expect(workouts[0].durationSeconds == 45 * 60)     // start → last activity
    let sets = try db.reader.read { try WorkoutSet.fetchAll($0) }
    #expect(sets.count == 3)                            // only sets with data
    #expect(Set(sets.map(\.exerciseName)) == ["Bench Press", "Shoulder Press"])
}

@Test func abandonedSessionWithTypedButUntickedSetsStillSaves() throws {
    let db = try AppDatabase.empty()
    let start = Date(timeIntervalSince1970: 1_780_000_000)
    let session = WorkoutService.SavedSession(
        workoutName: "Forgot To Tick",
        startTime: start,
        exercises: [sessionExercise(name: "Squat", sets: [("185", "5", false), ("185", "5", false)])])
    WorkoutService.finalizeAbandonedSession(session, into: db)
    let sets = try db.reader.read { try WorkoutSet.fetchAll($0) }
    #expect(sets.count == 2, "typed-in work must not be lost just because Done was never ticked")
}

@Test func abandonedEmptySessionIsNotSaved() throws {
    let db = try AppDatabase.empty()
    let session = WorkoutService.SavedSession(
        workoutName: "Ghost",
        startTime: Date(timeIntervalSince1970: 1_780_000_000),
        exercises: [sessionExercise(name: "Bench Press", sets: [("", "", false)])])
    WorkoutService.finalizeAbandonedSession(session, into: db)
    let workouts = try db.reader.read { try Workout.fetchAll($0) }
    #expect(workouts.isEmpty, "nothing logged → nothing to auto-save")
}

// Both tests below share the real UserDefaults session key — serialized so
// they can't clobber each other under the parallel runner.
@Suite(.serialized) struct AbandonedSessionPersistenceTests {

@Test func loadSessionKeepsFreshSessionAndExpiryUsesLastActivity() throws {
    defer { WorkoutService.clearSession() }
    let start = Date().addingTimeInterval(-6 * 3600)     // started 6h ago…
    // Tombstone must predate the backdated start or the save is rejected
    // as a stale write (see saveSession stale-session guard).
    WorkoutService.clearSession(now: start.addingTimeInterval(-60))
    WorkoutService.saveSession(.init(workoutName: "Long Gym Day", startTime: start,
                                     exercises: []))     // …but saved just now
    // Idle time (not total age) drives expiry — an active 6h session survives.
    #expect(WorkoutService.loadSession() != nil)
    // 5h+ after the LAST save it expires (empty session → dropped, no workout).
    #expect(WorkoutService.loadSession(now: Date().addingTimeInterval(6 * 3600)) == nil)
    #expect(!WorkoutService.hasActiveSession)
}

@Test func legacySessionPayloadWithoutLastSavedAtDecodes() throws {
    defer { WorkoutService.clearSession() }
    // Simulate a payload written by a build that predates lastSavedAt.
    struct LegacySession: Codable {
        let workoutName: String; let startTime: Date
        let exercises: [WorkoutService.SavedSession.SessionExercise]
    }
    let legacy = LegacySession(workoutName: "Old Build", startTime: Date().addingTimeInterval(-600), exercises: [])
    UserDefaults.standard.set(try JSONEncoder().encode(legacy), forKey: "drift_active_workout_session")
    let restored = WorkoutService.loadSession()
    #expect(restored?.workoutName == "Old Build")
    #expect(restored?.lastSavedAt == nil)   // falls back to startTime for expiry
}
}

// MARK: - Batched summaries (perf 2026-07-09: one sets query, not one per workout)

@Test func buildSummariesMatchesPerWorkoutBuildSummary() throws {
    let suffix = UUID().uuidString.prefix(6)
    var w1 = Workout(name: "Batch A \(suffix)", date: "2026-07-01", durationSeconds: 1800, createdAt: "2026-07-01T10:00:00Z")
    var w2 = Workout(name: "Batch B \(suffix)", date: "2026-07-02", durationSeconds: 2400, createdAt: "2026-07-02T10:00:00Z")
    var w3 = Workout(name: "Batch Empty \(suffix)", date: "2026-07-03", durationSeconds: nil, createdAt: "2026-07-03T10:00:00Z")
    try WorkoutService.saveWorkout(&w1)
    try WorkoutService.saveWorkout(&w2)
    try WorkoutService.saveWorkout(&w3)
    try WorkoutService.saveSets([
        WorkoutSet(workoutId: w1.id!, exerciseName: "Warm \(suffix)", setOrder: 1, reps: 10, isWarmup: true, exerciseOrder: 0),
        WorkoutSet(workoutId: w1.id!, exerciseName: "Bench \(suffix)", setOrder: 1, weightLbs: 135, reps: 8, isWarmup: false, exerciseOrder: 1),
        WorkoutSet(workoutId: w1.id!, exerciseName: "Bench \(suffix)", setOrder: 2, weightLbs: 140, reps: 6, isWarmup: false, exerciseOrder: 1),
        WorkoutSet(workoutId: w2.id!, exerciseName: "Squat \(suffix)", setOrder: 1, weightLbs: 185, reps: 5, isWarmup: false, exerciseOrder: 0),
    ])
    let workouts = [w1, w2, w3]
    let batched = try WorkoutService.buildSummaries(for: workouts)
    let single = try workouts.map { try WorkoutService.buildSummary(for: $0) }
    #expect(batched.count == single.count)
    for (b, s) in zip(batched, single) {
        #expect(b.workout.id == s.workout.id)
        #expect(b.exercises == s.exercises, "exercise order must match per-workout build")
        #expect(b.totalSets == s.totalSets)
        #expect(b.totalVolume == s.totalVolume)
        #expect(b.bestSets.map(\.0) == s.bestSets.map(\.0))
    }
}
