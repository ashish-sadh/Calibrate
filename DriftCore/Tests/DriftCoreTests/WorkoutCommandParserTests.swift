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

@Test func parse_nextVariants() {
    #expect(WorkoutCommandParser.parse("next") == .next)
    #expect(WorkoutCommandParser.parse("what's next?") == .next)
    #expect(WorkoutCommandParser.parse("what exercise next") == .next)
    #expect(WorkoutCommandParser.parse("what should i do next") == .next)
}

@Test func parse_formTipVariants() {
    #expect(WorkoutCommandParser.parse("form tips for deadlift") == .formTip(query: "deadlift"))
    #expect(WorkoutCommandParser.parse("how do i squat") == .formTip(query: "squat"))
    #expect(WorkoutCommandParser.parse("how to correct my bench form?") == .formTip(query: "bench"))
    #expect(WorkoutCommandParser.parse("technique for hanging leg raise") == .formTip(query: "hanging leg raise"))
}

@Test func parse_openQuestionsGoToTheCoach() {
    #expect(WorkoutCommandParser.parse("should i go heavier on bench?")
            == .ask(question: "should i go heavier on bench?"))
    #expect(WorkoutCommandParser.parse("am i resting too long")
            == .ask(question: "am i resting too long"))
}

@Test func parse_shortHistoryShorthandStillWorks() {
    // One/two-word "?" shorthand keeps the quick-lookup feel; long questions
    // with "?" go to the coach instead.
    #expect(WorkoutCommandParser.parse("bench?") == .history(query: "bench"))
    #expect(WorkoutCommandParser.parse("last squat?") == .history(query: "squat"))
}

// MARK: - Usual-workout replay (pure helpers)

@MainActor
@Test func mostRecentWorkout_matchesByNameNewestFirst() {
    let workouts = [
        Workout(name: "Push Day", date: "2026-07-09", createdAt: "2026-07-09"),
        Workout(name: "Pull Day", date: "2026-07-08", createdAt: "2026-07-08"),
        Workout(name: "Push Day", date: "2026-07-05", createdAt: "2026-07-05"),
    ]
    #expect(WorkoutService.mostRecentWorkout(matching: "push", in: workouts)?.date == "2026-07-09")
    #expect(WorkoutService.mostRecentWorkout(matching: "pull", in: workouts)?.name == "Pull Day")
    #expect(WorkoutService.mostRecentWorkout(matching: "", in: workouts)?.date == "2026-07-09")
    #expect(WorkoutService.mostRecentWorkout(matching: "yoga", in: workouts) == nil)
}

@MainActor
@Test func clonedSets_carryPlanDropRPEAndRetarget() {
    var source = WorkoutSet(workoutId: 7, exerciseName: "Bench Press", setOrder: 2,
                            weightLbs: 135, reps: 8, isWarmup: false,
                            durationSec: nil, exerciseOrder: 1)
    source.rpe = 9
    let cloned = WorkoutService.clonedSets(from: [source], to: 42)
    #expect(cloned.count == 1)
    let c = cloned[0]
    #expect(c.workoutId == 42)
    #expect(c.exerciseName == "Bench Press")
    #expect(c.setOrder == 2 && c.weightLbs == 135 && c.reps == 8 && c.exerciseOrder == 1)
    #expect(c.rpe == nil, "felt effort must not clone — it would fabricate data")
    #expect(c.id == nil, "clone is a fresh unsaved row")
}
