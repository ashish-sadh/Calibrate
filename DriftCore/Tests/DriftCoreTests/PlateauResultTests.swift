import Testing
@testable import DriftCore

@Suite struct PlateauResultTests {
    @Test func summaryReportsNoPlateauForStableProgress() {
        let result = PlateauResult(
            exercise: "Barbell Squat",
            isOnPlateau: false,
            sessionsChecked: 5,
            suggestion: "",
            isCompound: true
        )

        #expect(result.summary == "No plateau detected for Barbell Squat.")
    }

    @Test func summaryIncludesSessionCountAndSuggestionForPlateau() {
        let result = PlateauResult(
            exercise: "Lateral Raise",
            isOnPlateau: true,
            sessionsChecked: 3,
            suggestion: "Try adding 1 rep to each set.",
            isCompound: false
        )

        #expect(
            result.summary
                == "Plateau on Lateral Raise (3 sessions at same weight/reps). Try adding 1 rep to each set."
        )
    }
}
