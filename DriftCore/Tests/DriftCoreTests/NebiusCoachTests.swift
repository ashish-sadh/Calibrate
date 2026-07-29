import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for the coach's decode + merge. The cloud CALL is Tier-3; what's
/// locked here is the part that decides whether the conversation advances
/// correctly and — more importantly — whether it can silently FORGET something
/// the user already told it.
struct NebiusCoachTests {

    @Test func decodesReplyAndSlots() {
        let raw = #"""
        {"reply":"How many days a week can you train?","slots":{"days_per_week":2,"training_days":["Saturday","Sunday"],"goal":"fit and mobile","session_minutes":45,"equipment":"Fully stocked gym","uses_barbell":true,"familiar_exercises":["Squats","Bench Press"],"problem_areas":["back"],"pain_level":3,"requests":["mobility"]},"note":null,"ready_to_draft":true}
        """#
        let turn = NebiusCoach.decode(raw)
        #expect(turn?.reply == "How many days a week can you train?")
        #expect(turn?.learned.daysPerWeek == 2)
        #expect(turn?.learned.trainingDays == ["Saturday", "Sunday"])
        #expect(turn?.learned.sessionMinutes == 45)
        #expect(turn?.learned.usesBarbell == true)
        #expect(turn?.learned.painLevel == 3)
        #expect(turn?.readyToDraft == true)
    }

    @Test func promptWrappedJSONStillDecodes() {
        let raw = """
        Sure!
        ```json
        {"reply":"Any injury-prone areas?","slots":{},"note":null,"ready_to_draft":false}
        ```
        """
        #expect(NebiusCoach.decode(raw)?.reply == "Any injury-prone areas?")
    }

    @Test func garbageAndEmptyReplyAreNil() {
        #expect(NebiusCoach.decode("I couldn't parse that") == nil)
        #expect(NebiusCoach.decode(#"{"reply":"","slots":{}}"#) == nil)
    }

    /// Models return numbers as Int, Double or String depending on the day; a
    /// strict decode would drop a perfectly good answer.
    @Test func numbersSurviveWhateverTypeTheModelPicks() {
        let raw = #"{"reply":"ok","slots":{"days_per_week":"3","session_minutes":45.0},"ready_to_draft":false}"#
        let turn = NebiusCoach.decode(raw)
        #expect(turn?.learned.daysPerWeek == 3)
        #expect(turn?.learned.sessionMinutes == 45)
    }

    /// A model returning 12/10 must not drive exercise selection.
    @Test func painIsClampedToTheScale() {
        let raw = #"{"reply":"ok","slots":{"pain_level":12},"ready_to_draft":false}"#
        #expect(NebiusCoach.decode(raw)?.learned.painLevel == 10)
    }

    @Test func aNoteBecomesAvailableForMemory() {
        let raw = #"{"reply":"Got it","slots":{},"note":"Travelling next week","ready_to_draft":false}"#
        #expect(NebiusCoach.decode(raw)?.note == "Travelling next week")
    }

    // MARK: - Merge (the forgetting bugs)

    /// The failure that would ruin the feature: a later turn that says nothing
    /// about days must NOT wipe the day count.
    @Test func silenceNeverErasesAnEarlierAnswer() {
        var known = CoachIntake()
        known.daysPerWeek = 2
        known.sessionMinutes = 45
        known.goal = "fit and mobile"

        known.merge(CoachIntake())   // model mentioned nothing this turn

        #expect(known.daysPerWeek == 2)
        #expect(known.sessionMinutes == 45)
        #expect(known.goal == "fit and mobile")
    }

    @Test func listsUnionRatherThanReplace() {
        var known = CoachIntake()
        known.familiarExercises = ["Squats"]
        var learned = CoachIntake()
        learned.familiarExercises = ["Bench Press", "squats"]   // case-insensitive dupe

        known.merge(learned)
        #expect(known.familiarExercises == ["Squats", "Bench Press"],
                "naming one more lift adds to the list; it doesn't narrow it")
    }

    /// Pain is the deliberate exception — "it's a 5 now" is the point of asking
    /// again, so a fresh rating replaces the old one.
    @Test func aNewPainRatingReplacesTheOldOne() {
        var known = CoachIntake()
        known.painLevel = 3
        var learned = CoachIntake()
        learned.painLevel = 6
        known.merge(learned)
        #expect(known.painLevel == 6)
    }

    @Test func namingAProblemAreaMarksInjuriesAsAsked() {
        var known = CoachIntake()
        #expect(!known.askedInjuries)
        var learned = CoachIntake()
        learned.problemAreas = ["back"]
        known.merge(learned)
        #expect(known.askedInjuries, "we heard an answer, so stop asking")
    }
}
