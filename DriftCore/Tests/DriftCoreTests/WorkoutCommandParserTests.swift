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

@Test func parse_bareFormQuestionResolvesToCurrentExercise() {
    // No exercise named mid-workout → empty query so ActiveWorkoutView can
    // infer the current lift, not bounce to "which exercise?".
    #expect(WorkoutCommandParser.parse("form tips") == .formTip(query: ""))
    #expect(WorkoutCommandParser.parse("form check") == .formTip(query: ""))
    #expect(WorkoutCommandParser.parse("how's my form?") == .formTip(query: ""))
    #expect(WorkoutCommandParser.parse("check my form") == .formTip(query: ""))
    #expect(WorkoutCommandParser.parse("form check on this") == .formTip(query: ""))
    #expect(WorkoutCommandParser.parse("any tips?") == .formTip(query: ""))
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

// MARK: - Swap / replace (operator 2026-08-02)
//
// "In a workout session when run by a template if you talk to the inline AI
// integrated with it to replace an exercise with something. It should work.
// The current inline chat is not very smart!"
//
// Before this, no swap grammar existed at all: "replace squats with leg press"
// fell through to `.add`, so the app went looking for an exercise LITERALLY
// named "replace squats with leg press", found nothing, and said so.

@Test func parse_replaceNamesBothExercises() {
    #expect(WorkoutCommandParser.parse("replace squats with leg press")
            == .replace(old: "squats", new: "leg press", sets: nil))
    #expect(WorkoutCommandParser.parse("swap the deadlift for rdls")
            == .replace(old: "deadlift", new: "rdls", sets: nil))
    #expect(WorkoutCommandParser.parse("substitute bench press with dumbbell press")
            == .replace(old: "bench press", new: "dumbbell press", sets: nil))
    #expect(WorkoutCommandParser.parse("change squats to leg press")
            == .replace(old: "squats", new: "leg press", sets: nil))
}

/// The case that matters most: they know what to stop doing, not what to do
/// instead. `new: nil` means "pick one that trains the same thing".
@Test func parse_replaceWithoutATargetAsksUsToChoose() {
    #expect(WorkoutCommandParser.parse("swap the squats")
            == .replace(old: "squats", new: nil, sets: nil))
    #expect(WorkoutCommandParser.parse("replace bench press")
            == .replace(old: "bench press", new: nil, sets: nil))
}

/// "something easier" is not an exercise name — searching the catalog for it
/// would fail and the swap would be refused.
@Test func parse_vagueTargetsMeanYouChoose() {
    #expect(WorkoutCommandParser.parse("swap squats for something easier")
            == .replace(old: "squats", new: nil, sets: nil))
    #expect(WorkoutCommandParser.parse("replace deadlift with something else")
            == .replace(old: "deadlift", new: nil, sets: nil))
}

/// "leg press instead of squats" reverses the order — reading it left-to-right
/// would swap out the exercise they asked FOR.
@Test func parse_insteadOfInvertsTheOrder() {
    #expect(WorkoutCommandParser.parse("swap leg press instead of squats")
            == .replace(old: "squats", new: "leg press", sets: nil))
}

@Test func parse_replaceCarriesSetCount() {
    #expect(WorkoutCommandParser.parse("replace squats with leg press 4x10")
            == .replace(old: "squats", new: "leg press", sets: 4))
}

/// "this" is resolved by the handler to the lift they're on.
@Test func parse_replaceThis() {
    #expect(WorkoutCommandParser.parse("replace this with hack squat")
            == .replace(old: "this", new: "hack squat", sets: nil))
}

/// A swap must NEVER be read as a removal — that silently drops the lift
/// instead of substituting one, which is the destructive misread of the two.
@Test func parse_swapIsNeverARemoval() {
    for phrase in ["swap out the squats", "switch out bench press", "sub out curls"] {
        let parsed = WorkoutCommandParser.parse(phrase)
        if case .remove = parsed { Issue.record("\(phrase) parsed as a REMOVAL") }
    }
}

/// And "skip" still removes — someone skipping a lift is dropping it, not
/// asking for a replacement.
@Test func parse_skipStillRemoves() {
    #expect(WorkoutCommandParser.parse("skip the lunges") == .remove(query: "lunges"))
}
