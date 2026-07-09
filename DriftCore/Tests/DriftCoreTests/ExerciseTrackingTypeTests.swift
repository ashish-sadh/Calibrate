import Foundation
@testable import DriftCore
import Testing

/// 2026-07-09 exercise-DB cleanup: timer-vs-reps classification + dedup.
/// The old classifier did naive SUBSTRING matching and mis-timed ~15 rep
/// movements; catalog entries are now authoritative and the custom-name
/// fallback is whole-word.

// MARK: - Catalog authority: rep movements with time-word names stay reps

@Test @MainActor func catalogRepMovementsWithTimeWordsAreReps() {
    // Each of these was FORCED to .time by the old substring matcher.
    for name in ["Walking Lunge", "Barbell Walking Lunge", "Hang Clean",
                 "Hang Snatch", "Hanging Leg Raise", "Kettlebell Hang Clean",
                 "Sled Row", "Sled Reverse Flye", "Push Up to Side Plank",
                 "Isometric Wipers", "Monster Walk"] {
        #expect(ExerciseDatabase.trackingType(for: name) == .reps,
                "\(name) must be reps-tracked, not a timer")
    }
}

// MARK: - Catalog authority: genuine holds/carries/cardio are time

@Test @MainActor func catalogHoldsAndCardioAreTime() {
    for name in ["Plank", "L-Sit", "Farmer's Walk", "Rickshaw Carry",
                 "Battle Ropes", "Rowing Machine", "Running, Treadmill",
                 "Isometric Neck Exercise - Sides", "Sled Push"] {
        #expect(ExerciseDatabase.trackingType(for: name) == .time,
                "\(name) must be time-tracked")
    }
    #expect(WorkoutSet.isDurationExercise("Plank"))
    #expect(!WorkoutSet.isDurationExercise("Walking Lunge"))
}

// MARK: - Custom-name fallback: whole-word, no substring false positives

@Test func customClassifierIsWholeWord() {
    // Timed by an explicit whole word / phrase:
    #expect(ExerciseDatabase.classifyTrackingType("Side Plank") == .time)
    #expect(ExerciseDatabase.classifyTrackingType("Front Hold") == .time)
    #expect(ExerciseDatabase.classifyTrackingType("Suitcase Carry") == .time)
    #expect(ExerciseDatabase.classifyTrackingType("Wall Sit") == .time)
    #expect(ExerciseDatabase.classifyTrackingType("Dead Hang") == .time)
    // NOT timed — the old substring bug would have timed all of these:
    #expect(ExerciseDatabase.classifyTrackingType("Hang Clean") == .reps)
    #expect(ExerciseDatabase.classifyTrackingType("Walking Lunge") == .reps)
    #expect(ExerciseDatabase.classifyTrackingType("Sled Row") == .reps)
    #expect(ExerciseDatabase.classifyTrackingType("Planking Row") == .reps) // 'planking' ≠ 'plank' token
    #expect(ExerciseDatabase.classifyTrackingType("Bicep Curl") == .reps)
}

// MARK: - Dedup: merged names gone, canonical present

@Test @MainActor func mergedDuplicatesRemovedCanonicalKept() {
    for gone in ["Dumbbell Lunges", "Concentration Curls", "Hammer Curls",
                 "Leg Extensions", "Lying Leg Curls", "Standing Calf Raises",
                 "Bodyweight Walking Lunge", "Split Squats"] {
        #expect(ExerciseDatabase.info(for: gone) == nil ||
                ExerciseDatabase.info(for: gone)?.name != gone,
                "\(gone) should have been merged away")
    }
    for kept in ["Dumbbell Lunge", "Hammer Curl", "Leg Extension",
                 "Standing Calf Raise", "Walking Lunge", "Split Squat",
                 "Bulgarian Split Squat", "Bodyweight Bulgarian Split Squat"] {
        #expect(ExerciseDatabase.info(for: kept)?.name == kept,
                "\(kept) must remain in the catalog")
    }
}

// MARK: - Merged catalog entries carry an image (ported on merge / remapped)

@Test @MainActor func previouslyImagelessExercisesNowHaveImages() {
    for name in ["Bulgarian Split Squat", "Overhead Press", "Tricep Pushdown",
                 "Decline Bench Press", "Rowing Machine", "Battle Ropes"] {
        #expect(ExerciseDatabase.info(for: name)?.imageUrl != nil,
                "\(name) should have been remapped to a bundled pose")
    }
}

// MARK: - Rename map matches the JSON dedup (history migration parity)

@Test func renameMapCoversAllMerges() {
    #expect(Migrations.exerciseRenameMap["Dumbbell Lunges"] == "Dumbbell Lunge")
    #expect(Migrations.exerciseRenameMap["Bodyweight Walking Lunge"] == "Walking Lunge")
    #expect(Migrations.exerciseRenameMap.count == 8)
    // Every rename target must exist in the catalog.
    for target in Migrations.exerciseRenameMap.values {
        #expect(ExerciseDatabase.info(for: target)?.name == target,
                "rename target \(target) missing from catalog")
    }
}
