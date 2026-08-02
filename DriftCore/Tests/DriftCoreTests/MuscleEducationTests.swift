import Foundation
import Testing
@testable import DriftCore

/// Tier-0 for the anatomy knowledge base (operator's Chapter One guide).
struct MuscleGuideTests {

    /// The guide's own thesis — every entry must be readable by someone who has
    /// never heard the Latin. A blank function line is a broken card.
    @Test func everyCoveredMuscleHasAPlainEnglishFunction() {
        for key in MuscleInfo.allCovered {
            let info = MuscleInfo.info(for: key)
            #expect(info != nil, "\(key) missing")
            #expect(info?.function.isEmpty == false, "\(key) has no plain-English function")
            #expect(info?.displayName.isEmpty == false, "\(key) has no display name")
        }
    }

    /// The four universal ideas, which make every later explanation land.
    @Test func theFourPrinciplesAreAllPresent() {
        #expect(MuscleGuide.principles.count == 4)
        #expect(Set(MuscleGuide.principles.map(\.id)) == ["pull", "anchors", "pairs", "heads"])
        for principle in MuscleGuide.principles {
            #expect(!principle.plain.isEmpty)
        }
    }

    /// The headline claim of the guide: a muscle only ever pulls.
    @Test func theFirstPrincipleIsThatAMuscleOnlyPulls() {
        let pull = MuscleGuide.principles.first { $0.id == "pull" }
        #expect(pull?.plain.lowercased().contains("never pushes") == true)
    }

    /// Muscles that split into heads must say so — "why isn't chest day just
    /// bench press" is the question the heads answer.
    @Test func theBigMusclesCarryTheirHeads() {
        for key in ["chest", "shoulders", "triceps", "biceps", "calves"] {
            let info = MuscleInfo.info(for: key)
            #expect(info?.heads.isEmpty == false, "\(key) should list its heads")
        }
    }

    /// Every guide muscle must be drawable, or its card renders a blank figure.
    @Test func everyCoveredMuscleMapsToADrawableRegion() {
        for key in MuscleInfo.allCovered {
            let slugs = BodyDiagram.librarySlugs(forDriftMuscle: key)
            #expect(!slugs.isEmpty, "\(key) has no diagram region — its card would be empty")
        }
    }
}

/// Tier-0 for WHEN the coach teaches — the "don't force it" half.
///
/// The operator's constraint (2026-08-02): "Don't force education but know when
/// you bring and tell them". Most of these tests assert SILENCE.
struct MuscleEducationTests {

    // MARK: - Recognising a muscle

    @Test func anExactMuscleNameBeatsAVagueOne() {
        #expect(MuscleEducation.muscleNamed(in: "my lats are sore") == "lats")
        #expect(MuscleEducation.muscleNamed(in: "my lower back hurts") == "lower back")
    }

    @Test func gymNicknamesResolve() {
        #expect(MuscleEducation.muscleNamed(in: "my delts are tight") == "shoulders")
        #expect(MuscleEducation.muscleNamed(in: "pecs feel good") == "chest")
        #expect(MuscleEducation.muscleNamed(in: "quad is sore") == "quadriceps")
    }

    @Test func noMuscleNamedIsTheCommonCase() {
        #expect(MuscleEducation.muscleNamed(in: "3 days a week") == nil)
        #expect(MuscleEducation.muscleNamed(in: "45 minutes, full gym") == nil)
    }

    // MARK: - Teaching on pain

    /// The moment where explaining the muscle is nearly always welcome: they're
    /// already thinking about that body part.
    @Test func painOpensALesson() {
        let lesson = MuscleEducation.lesson(forUserText: "my shoulder has been hurting")
        #expect(lesson?.muscle == "shoulders")
        #expect(lesson?.reason == .injury)
    }

    /// And the injury wording must commit to working AROUND it — a lesson that
    /// reads like a training plan for a painful joint is worse than silence.
    @Test func anInjuryLessonSaysWeWillTrainAroundIt() {
        let lesson = MuscleEducation.lesson(forUserText: "my back is sore")
        #expect(lesson?.detail.lowercased().contains("around it") == true)
    }

    // MARK: - Teaching on intent

    @Test func namingAMuscleToTrainOpensALesson() {
        let lesson = MuscleEducation.lesson(forUserText: "I want to train my lats")
        #expect(lesson?.muscle == "lats")
        #expect(lesson?.reason == .focus)
    }

    /// The picks are justified, which is the operator's actual ask — "that's why
    /// we are picking some exercises".
    @Test func aFocusLessonExplainsTheExercisePicks() {
        let lesson = MuscleEducation.lesson(forUserText: "I want to train my lats")
        #expect(lesson?.detail.contains("that's why the picks are") == true
                || lesson?.detail.contains("That's why the picks are") == true)
    }

    // MARK: - NOT teaching (the important half)

    /// A muscle mentioned in passing is not an invitation to lecture.
    @Test func aPassingMentionTeachesNothing() {
        #expect(MuscleEducation.lesson(forUserText: "my back was in the car all day") == nil)
        #expect(MuscleEducation.lesson(forUserText: "see you at the gym") == nil)
    }

    /// ONE lesson per muscle per conversation, however often it comes up. This
    /// is the anti-lecture guard.
    @Test func aMuscleIsNeverExplainedTwice() {
        let first = MuscleEducation.lesson(forUserText: "my lats are sore")
        #expect(first != nil)
        let again = MuscleEducation.lesson(forUserText: "lats still hurt",
                                           alreadyTaught: ["lats"])
        #expect(again == nil, "one muscle, one explanation")
    }

    @Test func anOrdinaryIntakeAnswerTeachesNothing() {
        for answer in ["3 days", "45 min", "Full gym", "Nothing hurts", "Barbell is fine"] {
            #expect(MuscleEducation.lesson(forUserText: answer) == nil,
                    "\(answer) must not trigger a lesson")
        }
    }

    // MARK: - Teaching on a drafted session

    @Test func aDraftedSessionExplainsItsLeadMuscle() {
        var intake = CoachIntake()
        intake.sessionMinutes = 45
        let session = CoachProgramBuilder.todaySession(from: intake, focus: "legs")
        let lesson = MuscleEducation.lesson(forSession: session)
        #expect(lesson?.reason == .session)
        #expect(lesson != nil, "a session should be able to explain what it trains")
    }

    /// Already taught during the interview → the session card stays quiet.
    @Test func theSessionCardSkipsAMuscleAlreadyExplained() {
        var intake = CoachIntake()
        intake.sessionMinutes = 45
        let session = CoachProgramBuilder.todaySession(from: intake, focus: "legs")
        guard let first = MuscleEducation.lesson(forSession: session) else { return }
        let second = MuscleEducation.lesson(forSession: session,
                                            alreadyTaught: [first.muscle])
        #expect(second?.muscle != first.muscle)
    }

    // MARK: - Lesson content

    @Test func aLessonKnowsWhatToLightUpAndWhichSideShowsIt() {
        let lesson = MuscleEducation.lesson(forUserText: "I want to train my lats")
        #expect(lesson?.slugs.isEmpty == false, "nothing to highlight = empty figure")
        #expect(lesson?.side == .back, "lats read on the back view")
    }

    @Test func headlineWordingDiffersByReason() {
        let injury = MuscleEducation.lesson(forUserText: "my lats hurt")?.headline
        let focus = MuscleEducation.lesson(forUserText: "I want to train my lats")?.headline
        #expect(injury != focus, "a muscle that hurts isn't introduced like one you'll train")
    }
}
