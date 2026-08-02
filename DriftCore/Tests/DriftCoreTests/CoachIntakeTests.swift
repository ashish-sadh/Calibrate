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
        // 2026-07-29 (operator: "the coach should have asked about injury"):
        // logistics alone no longer draft — injuries must have been ASKED.
        #expect(!intake.canDraft, "no program before the injury question")
        intake.askedInjuries = true
        #expect(intake.canDraft, "logistics + the injury ask is enough to draft and then refine")
    }

    /// "Nothing hurts" fills no slot — the model reports the asking itself,
    /// and merge must carry that flag across turns.
    @Test func mergeCarriesAskedInjuriesFlag() {
        var known = CoachIntake()
        var learned = CoachIntake()
        learned.askedInjuries = true
        known.merge(learned)
        #expect(known.isFilled(.injuries))
    }

    /// Models drop new schema fields — the coach's own words are the fallback
    /// signal that injuries were asked about (question OR acknowledgment).
    @Test func coachTalkingAboutInjuriesCountsAsAsking() {
        var intake = CoachIntake()
        intake.noteInjuryTalk(inCoachReply: "Any areas that bother you or have a history of pain?")
        #expect(intake.isFilled(.injuries))

        var intake2 = CoachIntake()
        intake2.noteInjuryTalk(inCoachReply: "Good to hear nothing's bothering you.")
        #expect(intake2.isFilled(.injuries))

        var intake3 = CoachIntake()
        intake3.noteInjuryTalk(inCoachReply: "What equipment do you have access to?")
        #expect(!intake3.isFilled(.injuries), "equipment talk is not injury talk")
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

    // MARK: - One session now, vs a weekly program

    /// THE BUG (operator 2026-08-02): "I just want one exercise" was answered
    /// with "how many days a week can you train?", and the flow could only end
    /// in templates to file. Someone standing in the gym has no weekly schedule
    /// to give — knowing how long they have is enough.
    @Test func oneSessionNeedsOnlyHowLongTheyHave() {
        var intake = CoachIntake()
        intake.sessionMinutes = 45
        #expect(intake.canDraftToday)
        #expect(!intake.canDraft, "the weekly gate must still be the higher bar")
    }

    @Test func withoutADurationThereIsNothingToFill() {
        #expect(!CoachIntake().canDraftToday)
    }

    /// A today-session must NOT wait on the weekly slots — that wait is the
    /// interrogation being fixed.
    @Test func oneSessionDoesNotWaitForScheduleOrEquipmentOrInjuries() {
        var intake = CoachIntake()
        intake.sessionMinutes = 30
        #expect(intake.daysPerWeek == nil)
        #expect(intake.equipment == nil)
        #expect(!intake.isFilled(.injuries))
        #expect(intake.canDraftToday, "none of those may block one session")
    }
}

/// Tier-0 for reading WHICH thing the user asked for.
///
/// The model normally decides, but it returns null mid-interview and there is
/// no model offline — and the fallback was "weekly program", which is how a
/// one-exercise request became a filing cabinet.
struct CoachAskDetectionTests {

    @Test func askingForOneThingRightNowIsATodaySession() {
        for text in ["I just want one exercise", "what should I do today",
                     "I'm at the gym", "give me a workout", "just one session",
                     "quick workout before work"] {
            #expect(CoachProgramBuilder.Ask.detect(from: text) == .today,
                    "\(text) is a right-now ask")
        }
    }

    @Test func askingForSomethingRepeatableIsAProgram() {
        for text in ["make me a plan", "I want to train 3 days a week",
                     "build me a program", "give me a push pull legs split"] {
            #expect(CoachProgramBuilder.Ask.detect(from: text) == .program,
                    "\(text) is a weekly ask")
        }
    }

    /// One session TODAY still wins when a schedule word is also present —
    /// "one workout for today, I train 3 days a week" is a request for one
    /// workout, not an interview.
    @Test func aRightNowAskWinsOverAScheduleWord() {
        #expect(CoachProgramBuilder.Ask.detect(from: "one workout for today, I train 3 days a week")
                == .today)
    }

    /// Ambiguity returns nil rather than guessing: a wrong guess starts the
    /// wrong conversation, and asking once is cheap.
    @Test func anAmbiguousOpenerIsNotGuessed() {
        #expect(CoachProgramBuilder.Ask.detect(from: "I want to train my lats") == nil)
        #expect(CoachProgramBuilder.Ask.detect(from: "hey") == nil)
    }
}

/// The operator's ACTUAL transcript (screenshots, 2026-08-02), walked through
/// the decision functions turn by turn.
///
/// This is the bug report as a test. Every individual rule is covered above;
/// this asserts they compose into the right outcome for the conversation that
/// was actually had, which is the thing that was broken.
struct OperatorLatsTranscriptTests {

    @Test func theLatsConversationEndsInOneStartableSession() {
        var ask: CoachProgramBuilder.Ask?
        var intake = CoachIntake()
        var taught: Set<String> = []

        // Turn 1 — "I want to train my lats"
        // Ambiguous as an ASK (train could mean a program), so it must not be
        // guessed... but it IS a muscle they named, so the anatomy aside fires.
        ask = ask ?? CoachProgramBuilder.Ask.detect(from: "I want to train my lats")
        #expect(ask == nil, "naming a muscle is not yet a today-vs-program answer")
        let lesson = MuscleEducation.lesson(forUserText: "I want to train my lats",
                                            alreadyTaught: taught)
        #expect(lesson?.muscle == "lats")
        #expect(lesson?.reason == .focus)
        taught.insert(lesson!.muscle)

        // Turn 2 — "I just want one exercise". THE line that was answered with
        // "how many days a week can you train?".
        ask = ask ?? CoachProgramBuilder.Ask.detect(from: "I just want one exercise")
        #expect(ask == .today)

        // Turn 3 — "Gym". Turn 4 — "No pain".
        intake.equipment = "Full gym"
        intake.askedInjuries = true
        // Still no weekly schedule, and there must never be one asked for.
        #expect(intake.daysPerWeek == nil)

        // The coach knows how long they have (default 45 for a walk-in).
        intake.sessionMinutes = 45
        #expect(intake.canDraftToday, "this is enough to hand someone a session")

        // The draft is ONE session, and it's startable.
        let session = CoachProgramBuilder.todaySession(from: intake, focus: "lats")
        #expect(!session.exercises.isEmpty)
        #expect(session.name.lowercased().contains("lats"))

        // And it does NOT claim a weekly split.
        let why = CoachProgramBuilder.todayRationale(for: intake, focus: "lats")
        #expect(!why.contains("days a week"))

        // The lats were already explained in turn 1 — the session card must not
        // repeat itself.
        let again = MuscleEducation.lesson(forSession: session, alreadyTaught: taught)
        #expect(again?.muscle != "lats", "one muscle, one explanation")
    }
}

/// Tier-0 for what the single-session card SAYS.
struct TodayRationaleTests {

    private func intake(minutes: Int = 45) -> CoachIntake {
        var i = CoachIntake()
        i.sessionMinutes = minutes
        return i
    }

    /// The weekly rationale printed over one session claimed a split that
    /// doesn't exist ("Push / Pull / Legs: the big groups come back more than
    /// once a week"). Printing the wrong explanation is worse than none.
    @Test func todayNeverClaimsAWeeklySplit() {
        let why = CoachProgramBuilder.todayRationale(for: intake(), focus: "lats")
        #expect(!why.contains("days a week"))
        #expect(!why.contains("/"), "no split names on a single session")
        #expect(why.contains("45 min"))
    }

    @Test func aNamedFocusIsEchoedBack() {
        let why = CoachProgramBuilder.todayRationale(for: intake(), focus: "legs")
        #expect(why.lowercased().contains("legs"))
    }

    /// Only claim freshness when it actually drove the pick — a coach that
    /// says "rested" about a muscle you trained yesterday is not trustworthy.
    @Test func freshnessIsClaimedOnlyWhenItIsTrue() {
        let stale = CoachProgramBuilder.todayRationale(
            for: intake(), focus: "legs", recentBodyParts: ["legs"])
        #expect(!stale.contains("rested"), "legs were trained recently")
    }
}
