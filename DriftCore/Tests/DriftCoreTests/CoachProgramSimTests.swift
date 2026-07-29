import Foundation
import Testing
@testable import DriftCore

/// Simulation of what Coach Me actually hands people, printed so a human can
/// read the program rather than trust a green check. Every assert here came
/// from an operator complaint about a real generated program.
@Suite(.serialized) struct CoachProgramSimTests {

    static func dump(_ label: String, _ intake: CoachIntake) -> [WorkoutTemplate] {
        let program = CoachProgramBuilder.draft(from: intake)
        print("\n════ \(label) ════")
        print("intake: \(intake.summary)")
        for template in program {
            print("\n  \(template.name)")
            for exercise in template.exercises where !exercise.isWarmup {
                let part = ExerciseDatabase.match(name: exercise.name)?.bodyPart ?? "?"
                print("    \(exercise.name)  [\(part)]  \(exercise.sets)×\(exercise.notes ?? "")")
            }
        }
        return program
    }

    static func workingBodyParts(_ template: WorkoutTemplate) -> [String] {
        template.exercises
            .filter { !$0.isWarmup }
            .compactMap { ExerciseDatabase.match(name: $0.name)?.bodyPart.lowercased() }
    }

    /// THE BUG the operator reported: "sometimes it says full body and doesn't
    /// even look like full body."
    ///
    /// `selectExercises` fills depth-first — it exhausts every staple for the
    /// first body part before reaching the second. "Full Body A" is declared as
    /// legs+chest+back+core, but legs alone has 5 staples and a 45-minute
    /// session has 5 slots, so the user gets five leg exercises called
    /// "Full Body".
    @Test func fullBodyActuallyCoversTheWholeBody() {
        var intake = CoachIntake()
        intake.daysPerWeek = 2
        intake.sessionMinutes = 45
        intake.goal = "fit and mobile"
        intake.equipment = "Fully stocked gym"

        let program = Self.dump("2 days · 45 min · full gym", intake)

        for template in program where template.name.lowercased().contains("full body") {
            let parts = Set(Self.workingBodyParts(template))
            #expect(parts.count >= 3,
                    "\(template.name) claims full body but only trains \(parts.sorted())")
        }
    }

    /// A push day that is 5 chest exercises and no shoulders is the same bug
    /// wearing a different name.
    @Test func everyDayTrainsEveryMuscleItNames() {
        var intake = CoachIntake()
        intake.daysPerWeek = 3
        intake.sessionMinutes = 60
        intake.equipment = "Fully stocked gym"

        let program = Self.dump("3 days · 60 min · push/pull/legs", intake)
        let declared = CoachProgramBuilder.split(days: 3)

        for (template, day) in zip(program, declared) {
            let trained = Set(Self.workingBodyParts(template))
            // Every named muscle group should show up at least once. The DB
            // files both triceps and biceps under "Arms", so the split's finer
            // naming maps back to the coarser body part.
            for part in day.parts where part != "core" {
                let expected = ["triceps": "arms", "biceps": "arms"][part] ?? part
                #expect(trained.contains { $0.contains(expected) || expected.contains($0) },
                        "\(day.name) names '\(part)' but trained \(trained.sorted())")
            }
        }
    }

    /// Session length must actually change the program, or asking the question
    /// was theatre.
    @Test func sessionLengthChangesTheWorkload() {
        var short = CoachIntake()
        short.daysPerWeek = 3; short.sessionMinutes = 30
        var long = CoachIntake()
        long.daysPerWeek = 3; long.sessionMinutes = 75

        let shortCount = CoachProgramBuilder.draft(from: short)[0].exercises.filter { !$0.isWarmup }.count
        let longCount = CoachProgramBuilder.draft(from: long)[0].exercises.filter { !$0.isWarmup }.count
        #expect(longCount > shortCount, "30 min and 75 min produced the same session")
    }

    /// Injury handling — the operator wants to "talk about injury and modify a
    /// plan". A painful lower back must not be loaded.
    @Test func aPainfulBackIsNotLoaded() {
        var intake = CoachIntake()
        intake.daysPerWeek = 3
        intake.sessionMinutes = 45
        intake.problemAreas = ["lower back"]
        intake.painLevel = 6

        let program = Self.dump("3 days · sore lower back (6/10)", intake)
        let all = program.flatMap { $0.exercises }.filter { !$0.isWarmup }.map { $0.name.lowercased() }
        #expect(!all.contains("barbell deadlift"),
                "loaded a deadlift onto a 6/10 lower back")
        #expect(!all.isEmpty, "and it still produced a usable program rather than giving up")
    }

    /// Every curated staple and warmup must resolve to a REAL exercise. A name
    /// that stops resolving is invisible at runtime — the movement just quietly
    /// never appears in anyone's program. Four staples and both warmups were
    /// broken this way ("Barbell Bench Press", "Push-Ups", "Pull-Ups", "Seated
    /// Cable Row", "Cat-Cow", "Jumping Jacks"), which is how people ended up
    /// with Guillotine bench press and Rocky Pull-Ups.
    @Test func everyCuratedNameResolvesExactly() {
        for name in CoachProgramBuilder.curatedNames {
            let match = CoachProgramBuilder.staple(named: name)
            #expect(match?.name.lowercased() == name.lowercased(),
                    "'\(name)' resolved to '\(match?.name ?? "nil")' — curate a real DB name")
        }
    }

    /// The operator's ask: "generate a workout for today after asking
    /// questions." Today is ONE session, not a week of templates.
    @Test func todayIsOneSessionNotAProgram() {
        var intake = CoachIntake()
        intake.sessionMinutes = 45
        intake.equipment = "Fully stocked gym"

        let session = CoachProgramBuilder.todaySession(from: intake)
        print("\n════ TODAY · 45 min · no focus named ════")
        for exercise in session.exercises {
            print("    \(exercise.isWarmup ? "warmup · " : "")\(exercise.name)")
        }
        let parts = Set(Self.workingBodyParts(session))
        #expect(parts.count >= 3, "an unfocused session should cover the body, got \(parts.sorted())")
        #expect(session.exercises.contains { $0.isWarmup }, "still warms up")
    }

    /// A named focus is honoured — "legs today" must not return a full body.
    @Test func aNamedFocusIsRespected() {
        var intake = CoachIntake()
        intake.sessionMinutes = 45
        let session = CoachProgramBuilder.todaySession(from: intake, focus: "legs")
        let parts = Set(Self.workingBodyParts(session))
        #expect(parts == ["legs"], "asked for legs, trained \(parts.sorted())")
        #expect(session.name.lowercased().contains("legs"))
    }

    @Test func pushDayIsPushMusclesOnly() {
        var intake = CoachIntake()
        intake.sessionMinutes = 60
        let parts = Set(Self.workingBodyParts(
            CoachProgramBuilder.todaySession(from: intake, focus: "push")))
        #expect(!parts.contains("back"), "a push day trained back: \(parts.sorted())")
    }

    /// Freshness: what was trained yesterday shouldn't headline today.
    @Test func todayAvoidsWhatWasJustTrained() {
        var intake = CoachIntake()
        intake.sessionMinutes = 45
        let session = CoachProgramBuilder.todaySession(
            from: intake, recentBodyParts: ["legs", "chest", "core"])
        let parts = Set(Self.workingBodyParts(session))
        #expect(!parts.contains("legs"), "trained legs again the day after legs: \(parts.sorted())")
    }

    /// Machines-only must be honoured everywhere, not just the first day.
    @Test func machinesOnlyMeansNoBarbellAnywhere() {
        var intake = CoachIntake()
        intake.daysPerWeek = 4
        intake.sessionMinutes = 60
        intake.usesBarbell = false

        let program = Self.dump("4 days · machines only", intake)
        for template in program {
            for exercise in template.exercises where !exercise.isWarmup {
                #expect(!exercise.name.lowercased().contains("barbell"),
                        "\(template.name) has \(exercise.name) but the user said machines only")
            }
        }
    }

    /// The draft explains itself (operator 2026-07-29: "does the plan explain
    /// why it was picked?"). The rationale must carry the facts the plan was
    /// built from — days, minutes, equipment, goal — and name the split.
    @Test func rationaleCarriesTheIntakeFactsAndSplit() {
        var intake = CoachIntake()
        intake.daysPerWeek = 3
        intake.sessionMinutes = 45
        intake.equipment = "Dumbbells at home"
        intake.goal = "Build muscle"

        let rationale = CoachProgramBuilder.rationale(for: intake)
        #expect(rationale.contains("3 days"))
        #expect(rationale.contains("45 min"))
        #expect(rationale.contains("dumbbells at home"))
        #expect(rationale.contains("build muscle"))
        #expect(rationale.contains("Push / Pull / Legs"))
    }

    /// An empty intake still explains itself from the defaults — the card must
    /// never render a rationale with holes in it.
    @Test func rationaleSurvivesAnEmptyIntake() {
        let rationale = CoachProgramBuilder.rationale(for: CoachIntake())
        #expect(rationale.contains("3 days"))
        #expect(!rationale.contains("  "), "double space = a hole where a fact should be")
    }

    /// Muscle coverage on the card comes from the actual exercises, and every
    /// drafted day must have some — a day the card can't explain is a day the
    /// builder didn't understand.
    @Test func everyDraftedDayHasMuscleCoverage() {
        var intake = CoachIntake()
        intake.daysPerWeek = 3
        intake.sessionMinutes = 45

        for template in CoachProgramBuilder.draft(from: intake) {
            let coverage = CoachProgramBuilder.muscleCoverage(of: template)
            #expect(!coverage.isEmpty, "\(template.name) has no coverage line")
            #expect(coverage.count == Set(coverage).count, "\(template.name) coverage has duplicates")
        }
    }

    /// #1157: "just dumbbells at home" must never draft a movement that needs
    /// a gym — no cable, no machine, no barbell, on ANY day.
    @Test func dumbbellsOnlyDraftNeverNeedsAGym() {
        var intake = CoachIntake()
        intake.daysPerWeek = 3
        intake.sessionMinutes = 45
        intake.equipment = "just dumbbells at home"
        intake.askedInjuries = true

        let program = Self.dump("3 days · dumbbells at home", intake)
        #expect(!program.isEmpty)
        for template in program {
            let working = template.exercises.filter { !$0.isWarmup }
            #expect(!working.isEmpty, "\(template.name) drafted empty after the equipment filter")
            for exercise in working {
                let equip = ExerciseDatabase.match(name: exercise.name)?.equipment.lowercased() ?? "unknown"
                #expect(["body only", "dumbbell"].contains(equip),
                        "\(template.name): \(exercise.name) needs '\(equip)'")
            }
        }
    }

    /// The filter must not over-restrict: a full gym keeps the classic
    /// barbell/cable staples.
    @Test func fullGymKeepsTheBarbellStaples() {
        var intake = CoachIntake()
        intake.daysPerWeek = 3
        intake.sessionMinutes = 60
        intake.equipment = "Fully stocked gym"
        intake.askedInjuries = true

        let names = CoachProgramBuilder.draft(from: intake)
            .flatMap { $0.exercises.filter { !$0.isWarmup } }
            .map { $0.name.lowercased() }
        #expect(names.contains { name in
            ExerciseDatabase.match(name: name)?.equipment.lowercased() == "barbell"
        }, "a full gym lost its barbell work: \(names)")
    }

    /// Free text we don't recognize must not silently delete the pool —
    /// no restriction beats a wrong one.
    @Test func unrecognizedEquipmentTextDoesNotRestrict() {
        #expect(CoachProgramBuilder.allowedEquipment(for: {
            var intake = CoachIntake()
            intake.equipment = "my society's resistance setup"
            return intake
        }()) == nil)
        #expect(CoachProgramBuilder.allowedEquipment(for: CoachIntake()) == nil)
    }

    /// The chip vocabulary the coach itself suggests maps to sane pools.
    @Test func equipmentChipsMapToExpectedPools() {
        func pool(_ text: String) -> Set<String>? {
            var intake = CoachIntake()
            intake.equipment = text
            return CoachProgramBuilder.allowedEquipment(for: intake)
        }
        #expect(pool("Gym (full)") == nil)
        #expect(pool("Home (minimal)") == Set(["body only", "dumbbell", "bands"]))
        #expect(pool("Dumbbells only") == Set(["body only", "dumbbell"]))
        #expect(pool("Barbell setup")?.contains("barbell") == true)
        #expect(pool("bodyweight") == Set(["body only"]))
    }

    /// A Push day's coverage should read like a push day.
    @Test func pushDayCoverageMentionsChest() {
        var intake = CoachIntake()
        intake.daysPerWeek = 3
        intake.sessionMinutes = 45

        let program = CoachProgramBuilder.draft(from: intake)
        let push = program.first { $0.name == "Push" }
        #expect(push != nil)
        if let push {
            let coverage = CoachProgramBuilder.muscleCoverage(of: push).map { $0.lowercased() }
            #expect(coverage.contains { $0.contains("chest") || $0.contains("pectoral") },
                    "Push coverage was \(coverage)")
        }
    }
}
