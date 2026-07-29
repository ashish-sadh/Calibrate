import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for the Coach Me intake + program draft. These lock the promises the
/// feature makes to a user: it asks in a sensible order, it remembers, it warms
/// you up, it uses lifts you recognise, and it doesn't load a painful joint.
struct CoachIntakeTests {

    // MARK: - Where are we in the conversation?

    @Test func firstQuestionIsSchedule() {
        #expect(CoachIntake().nextStep == .schedule)
    }

    @Test func answeringAdvancesToTheNextUnfilledSlot() {
        var intake = CoachIntake()
        intake.daysPerWeek = 2
        #expect(intake.nextStep == .goal)
        intake.goal = "fit and mobile"
        #expect(intake.nextStep == .duration)
        intake.sessionMinutes = 45
        #expect(intake.nextStep == .equipment)
    }

    /// The whole point of tracking position: a returning user must not be
    /// re-interrogated about what they already said.
    @Test func alreadyAnsweredSlotsAreNotAskedAgain() {
        var intake = CoachIntake()
        intake.daysPerWeek = 3
        intake.sessionMinutes = 60
        intake.goal = "get stronger"
        intake.equipment = "Full gym"
        intake.usesBarbell = true
        intake.familiarExercises = ["Squats"]
        #expect(intake.nextStep == .injuries)
    }

    /// "No injuries" and "haven't asked yet" are different states — a program
    /// written without knowing which is guessing.
    @Test func silenceOnInjuriesIsNotTheSameAsNone() {
        var intake = CoachIntake()
        #expect(!intake.isFilled(.injuries))
        intake.askedInjuries = true
        #expect(intake.isFilled(.injuries))
    }

    @Test func canDraftOnceTheEssentialsAreIn() {
        var intake = CoachIntake()
        #expect(!intake.canDraft)
        intake.daysPerWeek = 2
        intake.sessionMinutes = 45
        intake.equipment = "Full gym"
        #expect(intake.canDraft, "days + duration + equipment is enough to draft and then refine")
    }

    // MARK: - The real conversation

    /// The operator's actual intake, replayed. If this stops producing a
    /// sensible program, the feature has regressed.
    @Test func realIntakeProducesTwoFullBodyDaysWithWarmups() {
        var intake = CoachIntake()
        intake.daysPerWeek = 2
        intake.trainingDays = ["Saturday", "Sunday"]
        intake.goal = "being fit and mobile"
        intake.sessionMinutes = 45
        intake.equipment = "Fully stocked gym"
        intake.usesBarbell = true
        intake.familiarExercises = ["Squats", "Bench Press", "Pull Ups", "Push Ups"]
        intake.problemAreas = ["back"]
        intake.painLevel = 3
        intake.requests = ["mobility"]

        let program = CoachProgramBuilder.draft(from: intake)
        #expect(program.count == 2, "2 days/week → two sessions")
        #expect(program.allSatisfy { $0.name.contains("Full Body") },
                "two days is full-body twice, never a bro split")

        for template in program {
            let exercises = template.exercises
            #expect(exercises.contains { $0.isWarmup }, "every session opens with a warmup")
            #expect(exercises.contains { !$0.isWarmup }, "…and has working sets")
        }
    }

    @Test func mobilityRequestChangesTheWarmup() {
        var mobile = CoachIntake()
        mobile.requests = ["add mobility work"]
        let mobilityWarmup = CoachProgramBuilder.warmup(for: mobile).map(\.name)

        let plainWarmup = CoachProgramBuilder.warmup(for: CoachIntake()).map(\.name)
        #expect(mobilityWarmup != plainWarmup,
                "asking for mobility should change what you're warmed up with")
    }

    // MARK: - Selection rules

    @Test func machinesOnlyDropsBarbellLifts() {
        var intake = CoachIntake()
        intake.usesBarbell = false
        let picked = CoachProgramBuilder.selectExercises(
            for: ["chest"], intake: intake, slots: 5).map { $0.name.lowercased() }
        #expect(!picked.contains("barbell bench press"),
                "someone who said machines only must not be handed a barbell")
    }

    /// Real pain steers the program away; a merely-noted area still gets
    /// trained, because avoidance is how weak links persist.
    @Test func highPainAvoidsTheAreaButLowPainDoesNot() {
        var sore = CoachIntake()
        sore.problemAreas = ["back"]
        sore.painLevel = 7
        let avoided = CoachProgramBuilder.selectExercises(
            for: ["back"], intake: sore, slots: 5)

        var mild = CoachIntake()
        mild.problemAreas = ["back"]
        mild.painLevel = 2
        let trained = CoachProgramBuilder.selectExercises(
            for: ["back"], intake: mild, slots: 5)

        #expect(avoided.count < trained.count || avoided.isEmpty,
                "7/10 pain should shrink or empty the back selection")
        #expect(!trained.isEmpty, "2/10 is not a reason to skip training the area")
    }

    @Test func sessionLengthBoundsTheNumberOfLifts() {
        #expect(CoachProgramBuilder.slots(forMinutes: 30) == 3)
        #expect(CoachProgramBuilder.slots(forMinutes: 45) == 5)
        #expect(CoachProgramBuilder.slots(forMinutes: 60) == 6)
    }

    @Test func goalDrivesRepRangeRatherThanADefaultBlock() {
        guard let squat = ExerciseDatabase.match(name: "Barbell Squat") else { return }
        var strength = CoachIntake(); strength.goal = "get stronger"
        var fatLoss = CoachIntake(); fatLoss.goal = "lose fat"
        #expect(CoachProgramBuilder.repRange(for: squat, intake: strength)
                != CoachProgramBuilder.repRange(for: squat, intake: fatLoss))
    }

    // MARK: - Memory

    @Test func notesSurviveAndSummarise() {
        var notes = CoachNotes()
        notes.intake.daysPerWeek = 2
        notes.intake.goal = "fit and mobile"
        notes.intake.problemAreas = ["back"]
        notes.intake.painLevel = 3
        notes.record("Back sore after Saturday session", kind: .moment)

        let briefing = notes.briefing()
        #expect(briefing.contains("fit and mobile"))
        #expect(briefing.contains("back"))
        #expect(briefing.contains("Back sore after Saturday session"),
                "a human coach inheriting this client should see the moments too")
    }

    @Test func summaryReadsBackWhatWasHeard() {
        var intake = CoachIntake()
        intake.daysPerWeek = 2
        intake.trainingDays = ["Saturday", "Sunday"]
        intake.sessionMinutes = 45
        intake.goal = "fit and mobile"
        let summary = intake.summary
        #expect(summary.contains("2 days/week"))
        #expect(summary.contains("Saturday"))
        #expect(summary.contains("45 min"))
    }
}
