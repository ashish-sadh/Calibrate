import Foundation
@testable import DriftCore
import Testing

/// Tier 0 — cross-platform health-workout duration formatting.
/// Pure logic; no health-store or database dependency.
@Suite struct HealthWorkoutDurationDisplayTests {

    private func workout(duration: TimeInterval) -> HealthWorkout {
        HealthWorkout(
            id: UUID(),
            type: "Walking",
            duration: duration,
            calories: 100,
            date: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func durationsUnderOneHourUseMinutesOnly() {
        #expect(workout(duration: 30 * 60).durationDisplay == "30m")
        #expect(workout(duration: 59 * 60).durationDisplay == "59m")
    }

    @Test func hourDurationsIncludeRemainingMinutes() {
        #expect(workout(duration: 60 * 60).durationDisplay == "1h 0m")
        #expect(workout(duration: 2 * 60 * 60 + 17 * 60).durationDisplay == "2h 17m")
    }

    @Test func incompleteMinutesAreTruncated() {
        #expect(workout(duration: 59).durationDisplay == "0m")
        #expect(workout(duration: 60 * 60 - 0.1).durationDisplay == "59m")
    }
}
