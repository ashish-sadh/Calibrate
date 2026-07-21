@testable import DriftCore
import Testing

@Suite struct WorkoutCommandParserBoundaryTests {
    @Test func removalNormalizesOuterWhitespaceAndCase() {
        #expect(WorkoutCommandParser.parse("  \n TAKE OUT some Pull-Ups \t")
                == .remove(query: "pull-ups"))
    }

    @Test func alternateAddPrefixesStripLeadingArticles() {
        #expect(WorkoutCommandParser.parse("put in the cable fly")
                == .add(query: "cable fly", sets: nil))
        #expect(WorkoutCommandParser.parse("throw in some face pulls")
                == .add(query: "face pulls", sets: nil))
        #expect(WorkoutCommandParser.parse("include a goblet squat")
                == .add(query: "goblet squat", sets: nil))
    }

    @Test func setSyntaxAcceptsSpacedUppercaseXAndSingularSet() {
        #expect(WorkoutCommandParser.parse("Incline Bench 3 X 10")
                == .add(query: "incline bench", sets: 3))
        #expect(WorkoutCommandParser.parse("1 set of Romanian deadlifts")
                == .add(query: "romanian deadlifts", sets: 1))
    }

    @Test func historyQueryPreservesLoadNumbers() {
        #expect(WorkoutCommandParser.parse("what was my bench 225 last session?")
                == .history(query: "bench 225"))
    }

    @Test func formCueKeepsExerciseAngle() {
        #expect(WorkoutCommandParser.parse("Give me cues for 45-degree leg press")
                == .formTip(query: "45 degree leg press"))
    }

    @Test func openQuestionPreservesTrimmedOriginalText() {
        #expect(WorkoutCommandParser.parse("  Can I increase Bench weight? \n")
                == .ask(question: "Can I increase Bench weight?"))
    }
}
