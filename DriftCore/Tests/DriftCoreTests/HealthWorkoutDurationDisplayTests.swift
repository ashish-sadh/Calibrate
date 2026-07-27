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

    // MARK: - decode(fromFacadeJSON:) — Android Health Connect facade JSON

    @Test func decodesFacadeJSONIntoSortedWorkouts() {
        let json = """
        [
            {"id":"11111111-1111-1111-1111-111111111111","type":"Walking","durationSec":1800.0,"calories":120.0,"startMillis":1000000},
            {"id":"22222222-2222-2222-2222-222222222222","type":"Strength Training","durationSec":2700.0,"calories":312.0,"startMillis":5000000}
        ]
        """
        let decoded = HealthWorkout.decode(fromFacadeJSON: json)
        #expect(decoded.count == 2)
        // Newest start first, matching HealthKit's `ascending: false` sort.
        #expect(decoded[0].type == "Strength Training")
        #expect(decoded[0].duration == 2700.0)
        #expect(decoded[0].calories == 312.0)
        #expect(decoded[0].date == Date(timeIntervalSince1970: 5000))
        #expect(decoded[1].type == "Walking")
    }

    @Test func decodeFallsBackToRandomUUIDForMalformedId() {
        let json = """
        [{"id":"not-a-uuid","type":"Running","durationSec":600.0,"calories":80.0,"startMillis":0}]
        """
        let decoded = HealthWorkout.decode(fromFacadeJSON: json)
        #expect(decoded.count == 1)
        #expect(decoded[0].type == "Running")
    }

    @Test func decodeSkipsRecordsMissingRequiredFields() {
        let json = """
        [{"id":"33333333-3333-3333-3333-333333333333","type":"Yoga"}]
        """
        #expect(HealthWorkout.decode(fromFacadeJSON: json).isEmpty)
    }

    @Test func decodeReturnsEmptyForMalformedJSON() {
        #expect(HealthWorkout.decode(fromFacadeJSON: "not json").isEmpty)
        #expect(HealthWorkout.decode(fromFacadeJSON: "[]").isEmpty)
    }
}
