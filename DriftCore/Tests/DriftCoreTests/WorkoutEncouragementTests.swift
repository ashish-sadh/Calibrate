import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for the mid-workout coach toast lines (pure rotation).

@Test func linesRotateDeterministicallyAndNeverRepeatBackToBack() {
    let a = WorkoutEncouragement.line(for: .setDone, tick: 1)
    let b = WorkoutEncouragement.line(for: .setDone, tick: 2)
    #expect(a != b, "consecutive ticks must vary the line")
    #expect(WorkoutEncouragement.line(for: .setDone, tick: 1) == a, "same tick = same line (deterministic)")
}

@Test func exerciseCompleteInterpolatesRemaining() {
    for tick in 0..<5 {
        let line = WorkoutEncouragement.line(for: .exerciseComplete(remaining: 3), tick: tick)
        #expect(line.contains("3"), "remaining count must appear: \(line)")
    }
    let lastOne = WorkoutEncouragement.line(for: .exerciseComplete(remaining: 1), tick: 0)
    #expect(!lastOne.contains("1 "), "singular phrasing, not '1 to go': \(lastOne)")
}

@Test func zeroRemainingFallsThroughToWorkoutComplete() {
    let line = WorkoutEncouragement.line(for: .exerciseComplete(remaining: 0), tick: 2)
    #expect(line == WorkoutEncouragement.line(for: .workoutComplete, tick: 2))
}

@Test func allLinesAreShortEnoughToGlance() {
    let events: [WorkoutEncouragement.Event] = [
        .setDone, .beatLastTime, .exerciseComplete(remaining: 4), .workoutComplete,
    ]
    for event in events {
        for tick in 0..<8 {
            let line = WorkoutEncouragement.line(for: event, tick: tick)
            #expect(!line.isEmpty)
            #expect(line.count <= 60, "toast must be glanceable: \(line)")
        }
    }
}
