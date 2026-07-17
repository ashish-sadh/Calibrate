import Testing
import Foundation
@testable import Drift

/// Tier 1 — rest-timer anchor identity (field report 2026-07-16: "timer
/// randomly starts on different exercises"). The bar used to be anchored by
/// ARRAY INDICES; deleting/adding a row above the resting set shifted every
/// index and the running countdown jumped to whichever row inherited it.
/// These pin the ID-anchored replacement across each mutation that shifts
/// indices.
struct ActiveWorkoutRestTimerTests {

    private func makeExercise(_ name: String, sets: Int = 3) -> ActiveWorkoutView.ActiveExercise {
        .init(name: name, sets: (0..<sets).map { _ in .init(weight: "135", reps: "8") },
              previousSets: [])
    }

    @Test func anchorSurvivesDeletingAnEarlierExercise() {
        // Rest running on Squat set 2; user removes Bench (above it).
        var exercises = [makeExercise("Bench Press"), makeExercise("Squat")]
        let anchorEx = exercises[1].id
        let anchorSet = exercises[1].sets[1].id

        exercises.remove(at: 0)   // index of Squat shifts 1 → 0

        // ID anchor still resolves to the same, correct row…
        #expect(ActiveWorkoutView.restAnchorAlive(exercises: exercises,
                                                  exerciseID: anchorEx, setID: anchorSet))
        // …whereas the old integer anchor (exerciseIndex 1) now points at
        // nothing / the wrong row — the reported bug.
        #expect(exercises.count == 1 && exercises[0].id == anchorEx)
    }

    @Test func anchorSurvivesAddingAndAutoAddedSets() {
        // Adding an exercise (chat strip) and the auto-added next set must
        // not move the bar.
        var exercises = [makeExercise("Squat")]
        let anchorEx = exercises[0].id
        let anchorSet = exercises[0].sets[0].id

        exercises.insert(makeExercise("Face Pull"), at: 0)   // chat "add face pulls"
        exercises[1].sets.append(.init(weight: "135", reps: "8"))  // auto-add

        #expect(ActiveWorkoutView.restAnchorAlive(exercises: exercises,
                                                  exerciseID: anchorEx, setID: anchorSet))
    }

    @Test func anchorDiesWithItsSet() {
        var exercises = [makeExercise("Squat")]
        let anchorEx = exercises[0].id
        let anchorSet = exercises[0].sets[1].id

        exercises[0].sets.removeAll { $0.id == anchorSet }

        #expect(!ActiveWorkoutView.restAnchorAlive(exercises: exercises,
                                                   exerciseID: anchorEx, setID: anchorSet),
                "a countdown for a deleted set must be stopped, not left running invisibly")
        // Deleting a DIFFERENT set leaves the anchor alive.
        var ex2 = [makeExercise("Bench Press")]
        let aEx = ex2[0].id, aSet = ex2[0].sets[0].id
        let victim = ex2[0].sets[2].id
        ex2[0].sets.removeAll { $0.id == victim }
        #expect(ActiveWorkoutView.restAnchorAlive(exercises: ex2, exerciseID: aEx, setID: aSet))
    }

    @Test func anchorDiesWithItsExercise() {
        var exercises = [makeExercise("Bench Press"), makeExercise("Squat")]
        let anchorEx = exercises[1].id
        let anchorSet = exercises[1].sets[0].id

        exercises.removeAll { $0.id == anchorEx }   // card menu / chat "drop squat"

        #expect(!ActiveWorkoutView.restAnchorAlive(exercises: exercises,
                                                   exerciseID: anchorEx, setID: anchorSet))
    }

    @Test func nilAnchorIsNeverAlive() {
        let exercises = [makeExercise("Squat")]
        #expect(!ActiveWorkoutView.restAnchorAlive(exercises: exercises, exerciseID: nil, setID: nil))
        #expect(!ActiveWorkoutView.restAnchorAlive(exercises: [], exerciseID: UUID(), setID: UUID()))
    }
}
