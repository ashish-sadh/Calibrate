import XCTest
@testable import Drift

/// #1106 — Skip Fuse keeps `ExerciseVoiceLogSheet`'s @State alive across sheet
/// presentations (eager sheet builder), so `.onDisappear` must fully clear a
/// populated session via `reset()`. This guards that `reset()` stays complete
/// if a future field is added to the view model but forgotten here.
@MainActor
final class ExerciseVoiceLogViewModelTests: XCTestCase {

    func testResetClearsAPopulatedSession() {
        let vm = ExerciseVoiceLogViewModel()
        let first = ExerciseVoiceLogViewModel.ExerciseDraft(
            name: "Bench Press", isDuration: false, matched: true,
            sets: "3", reps: "10", weight: "135", durationMinutes: ""
        )
        let second = ExerciseVoiceLogViewModel.ExerciseDraft(
            name: "Squat", isDuration: false, matched: true,
            sets: "3", reps: "8", weight: "185", durationMinutes: ""
        )
        vm.exercises = [first, second]
        vm.transcript = "3x10 bench press at 135, then 3x8 squats at 185"
        vm.recentlyAddedIDs = [first.id]
        vm.transientMessage = "Couldn't find an exercise in that — try again."
        vm.phase = .confirming

        vm.reset()

        XCTAssertTrue(vm.exercises.isEmpty)
        XCTAssertEqual(vm.transcript, "")
        XCTAssertTrue(vm.recentlyAddedIDs.isEmpty)
        XCTAssertNil(vm.transientMessage)
        XCTAssertEqual(vm.phase, .input)
        XCTAssertEqual(vm.loggableCount, 0)
    }
}
