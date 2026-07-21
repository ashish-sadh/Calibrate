import Testing
@testable import DriftCore

@Suite struct RoutinePlanGeneratorGroundingBoundaryTests {
    @MainActor
    @Test func canonicalDuplicatesAreRemovedCaseInsensitively() {
        let day = RoutinePlanGenerator.PlannedDay(name: "Full Body", exercises: [
            .init(name: "Squat", sets: 3, reps: "8"),
            .init(name: "squat", sets: 4, reps: "10"),
            .init(name: "Plank", sets: 3, reps: "30 sec"),
        ])

        let grounded = RoutinePlanGenerator.grounded([day])

        #expect(grounded?.first?.exercises.map(\.name) == ["Squat", "Plank"])
    }

    @MainActor
    @Test func setsAndTextFieldsClampAtTheirExactLimits() {
        let dayName = "123456789012345678901234extra"
        let day = RoutinePlanGenerator.PlannedDay(name: dayName, exercises: [
            .init(name: "Squat", sets: -2, reps: "123456789012extra"),
            .init(name: "Plank", sets: 99, reps: "30 seconds long"),
        ])

        let grounded = RoutinePlanGenerator.grounded([day])

        #expect(grounded?.first?.name == "123456789012345678901234")
        #expect(grounded?.first?.exercises[0].sets == 1)
        #expect(grounded?.first?.exercises[0].reps == "123456789012")
        #expect(grounded?.first?.exercises[1].sets == 5)
        #expect(grounded?.first?.exercises[1].reps == "30 seconds l")
    }

    @MainActor
    @Test func duplicateOnlyDayIsDroppedAfterGrounding() {
        let day = RoutinePlanGenerator.PlannedDay(name: "Legs", exercises: [
            .init(name: "Squat", sets: 3, reps: "8"),
            .init(name: "SQUAT", sets: 3, reps: "10"),
        ])

        #expect(RoutinePlanGenerator.grounded([day]) == nil)
    }
}
