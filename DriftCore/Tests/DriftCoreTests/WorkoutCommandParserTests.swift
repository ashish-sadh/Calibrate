import Foundation
@testable import DriftCore
import Testing

// Tier-0 tests for the ActiveWorkout command-strip grammar.

@Test func parse_removeVariants() {
    #expect(WorkoutCommandParser.parse("drop the leg curls") == .remove(query: "leg curls"))
    #expect(WorkoutCommandParser.parse("remove bench press") == .remove(query: "bench press"))
    #expect(WorkoutCommandParser.parse("delete a squat") == .remove(query: "squat"))
}

@Test func parse_historyVariants() {
    #expect(WorkoutCommandParser.parse("what did I bench last time") == .history(query: "bench"))
    #expect(WorkoutCommandParser.parse("last squat?") == .history(query: "squat"))
    #expect(WorkoutCommandParser.parse("history for deadlift") == .history(query: "deadlift"))
}

@Test func parse_addWithSetsShorthand() {
    #expect(WorkoutCommandParser.parse("add incline bench 3x10")
            == .add(query: "incline bench", sets: 3))
    #expect(WorkoutCommandParser.parse("face pulls 4×12")
            == .add(query: "face pulls", sets: 4))
    #expect(WorkoutCommandParser.parse("add 4 sets of curls")
            == .add(query: "curls", sets: 4))
}

@Test func parse_bareNameIsAdd() {
    #expect(WorkoutCommandParser.parse("add face pulls") == .add(query: "face pulls", sets: nil))
    #expect(WorkoutCommandParser.parse("goblet squat") == .add(query: "goblet squat", sets: nil))
}

@Test func extractSets_leavesNameCleanWithoutNumbers() {
    let (sets, name) = WorkoutCommandParser.extractSets(from: "bench press")
    #expect(sets == nil)
    #expect(name == "bench press")
}
