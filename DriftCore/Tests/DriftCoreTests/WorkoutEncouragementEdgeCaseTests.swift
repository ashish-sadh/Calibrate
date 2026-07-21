import Testing
@testable import DriftCore

/// Tier 0 — boundary behavior for the deterministic workout toast rotation.
struct WorkoutEncouragementEdgeCaseTests {

    @Test func negativeTicksMirrorTheirPositiveCounterparts() {
        let events: [WorkoutEncouragement.Event] = [
            .setDone,
            .beatLastTime,
            .exerciseComplete(remaining: 1),
            .exerciseComplete(remaining: 4),
            .workoutComplete,
        ]

        for event in events {
            for tick in [1, 2, 17] {
                #expect(
                    WorkoutEncouragement.line(for: event, tick: -tick)
                        == WorkoutEncouragement.line(for: event, tick: tick)
                )
            }
        }
    }

    @Test func rotationsWrapAtEachMessagePoolBoundary() {
        #expect(
            WorkoutEncouragement.line(for: .setDone, tick: 7)
                == WorkoutEncouragement.line(for: .setDone, tick: 0)
        )
        #expect(
            WorkoutEncouragement.line(for: .beatLastTime, tick: 3)
                == WorkoutEncouragement.line(for: .beatLastTime, tick: 0)
        )
        #expect(
            WorkoutEncouragement.line(for: .exerciseComplete(remaining: 1), tick: 2)
                == WorkoutEncouragement.line(for: .exerciseComplete(remaining: 1), tick: 0)
        )
        #expect(
            WorkoutEncouragement.line(for: .exerciseComplete(remaining: 4), tick: 3)
                == WorkoutEncouragement.line(for: .exerciseComplete(remaining: 4), tick: 0)
        )
        #expect(
            WorkoutEncouragement.line(for: .workoutComplete, tick: 3)
                == WorkoutEncouragement.line(for: .workoutComplete, tick: 0)
        )
    }

    @Test func everyNonPositiveRemainingCountUsesWorkoutCompletion() {
        for remaining in [0, -1, Int.min] {
            #expect(
                WorkoutEncouragement.line(for: .exerciseComplete(remaining: remaining), tick: 2)
                    == WorkoutEncouragement.line(for: .workoutComplete, tick: 2)
            )
        }
    }
}
