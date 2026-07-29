import Foundation

/// Turns a `CoachIntake` into workout templates the user can accept or refine.
///
/// Two rules drive every choice here, both from the operator (2026-07-28):
///
/// 1. **Basic and popular first.** A program is only good if it gets done, and
///    people do lifts they recognise. Selection prefers what the user already
///    named, then the classic barbell/bodyweight movements, then beginner-level
///    entries — never an exotic variation when a staple covers the same muscle.
/// 2. **Warm up properly.** Every session opens with a warmup block. The old
///    `buildSmartSession` emitted working sets only, which is how people tweak
///    a back on set one.
public enum CoachProgramBuilder {

    /// The staples, in the order a coach would reach for them. Matched against
    /// the exercise DB by name, so anything here that isn't in `exercises.json`
    /// is simply skipped rather than inventing a movement.
    static let staples: [String: [String]] = [
        "chest":      ["Barbell Bench Press", "Push-Ups", "Dumbbell Bench Press", "Incline Dumbbell Press"],
        "back":       ["Pull-Ups", "Barbell Deadlift", "Bent Over Barbell Row", "Lat Pulldown", "Seated Cable Row"],
        "legs":       ["Barbell Squat", "Romanian Deadlift", "Leg Press", "Walking Lunge", "Leg Curl"],
        "shoulders":  ["Overhead Press", "Dumbbell Lateral Raise", "Face Pull"],
        "arms":       ["Barbell Curl", "Triceps Pushdown", "Dumbbell Curl"],
        "core":       ["Plank", "Hanging Leg Raise", "Cable Crunch"],
    ]

    /// Movements that need a barbell — dropped when the user said machines only.
    static let barbellMovements: Set<String> = [
        "barbell bench press", "barbell squat", "barbell deadlift",
        "bent over barbell row", "overhead press", "romanian deadlift", "barbell curl",
    ]

    /// A warmup that costs five minutes and prevents the injury that costs six
    /// weeks. Mobility-flavoured when the user asked for mobility or reported
    /// pain, generic otherwise.
    public static func warmup(for intake: CoachIntake) -> [WorkoutTemplate.TemplateExercise] {
        let wantsMobility = intake.requests.contains { $0.lowercased().contains("mobility") }
            || intake.painLevel != nil
        let names = wantsMobility
            ? ["Cat-Cow", "World's Greatest Stretch", "Glute Bridge", "Band Pull Apart"]
            : ["Jumping Jacks", "Arm Circles", "Bodyweight Squat", "Glute Bridge"]

        return names.compactMap { name in
            guard let match = ExerciseDatabase.match(name: name) else { return nil }
            return WorkoutTemplate.TemplateExercise(
                name: match.name, sets: 1, isWarmup: true, restSeconds: 30,
                notes: "Warmup · 30-45s")
        }
    }

    /// Pick working exercises for one session.
    ///
    /// `slots` is how many working lifts fit the session length — a 45-minute
    /// session is about 5 lifts once the warmup and rest are honest, not 8.
    public static func selectExercises(for bodyParts: [String],
                                       intake: CoachIntake,
                                       slots: Int) -> [WorkoutTemplate.TemplateExercise] {
        var chosen: [ExerciseDatabase.ExerciseInfo] = []
        var usedNames = Set<String>()

        // 1. What the user already does, if it hits today's muscles. Their own
        //    vocabulary beats ours.
        for name in intake.familiarExercises {
            guard chosen.count < slots,
                  let match = ExerciseDatabase.match(name: name),
                  bodyParts.contains(where: { match.bodyPart.lowercased().contains($0) }),
                  allows(match, intake: intake),
                  usedNames.insert(match.name.lowercased()).inserted else { continue }
            chosen.append(match)
        }

        // 2. Staples for the day's muscles, in coach order.
        for part in bodyParts {
            for name in staples[part] ?? [] {
                guard chosen.count < slots,
                      let match = ExerciseDatabase.match(name: name),
                      allows(match, intake: intake),
                      usedNames.insert(match.name.lowercased()).inserted else { continue }
                chosen.append(match)
            }
        }

        // 3. Still short — beginner-level entries for the target muscles, so we
        //    fall back to simple rather than obscure.
        if chosen.count < slots {
            let fallback = ExerciseDatabase.all
                .filter { info in
                    bodyParts.contains { info.bodyPart.lowercased().contains($0) }
                        && info.level.lowercased() == "beginner"
                        && allows(info, intake: intake)
                        && !usedNames.contains(info.name.lowercased())
                }
                .prefix(slots - chosen.count)
            for info in fallback {
                usedNames.insert(info.name.lowercased())
                chosen.append(info)
            }
        }

        return chosen.map { info in
            // TemplateExercise has no reps field — target reps fold into
            // `notes`, the same convention the workout-scan parser uses.
            WorkoutTemplate.TemplateExercise(
                name: info.name,
                sets: 3,
                isWarmup: false,
                restSeconds: isCompoundish(info) ? 120 : 75,
                notes: "\(repRange(for: info, intake: intake)) reps")
        }
    }

    /// Honour "machines only" and steer away from a painful area — a program
    /// that loads a sore back is worse than no program.
    static func allows(_ info: ExerciseDatabase.ExerciseInfo, intake: CoachIntake) -> Bool {
        if intake.usesBarbell == false, barbellMovements.contains(info.name.lowercased()) {
            return false
        }
        // Only avoid loading a problem area when it actually hurts. A noted-but
        // painless area still gets trained — avoidance is how weak links persist.
        if let pain = intake.painLevel, pain >= 4 {
            let muscles = (info.primaryMuscles + [info.bodyPart]).map { $0.lowercased() }
            if intake.problemAreas.contains(where: { area in
                muscles.contains { $0.contains(area.lowercased()) }
            }) { return false }
        }
        return true
    }

    static func isCompoundish(_ info: ExerciseDatabase.ExerciseInfo) -> Bool {
        info.primaryMuscles.count > 1 || barbellMovements.contains(info.name.lowercased())
    }

    /// Rep ranges follow the stated goal rather than a default hypertrophy
    /// block — "fit and mobile" is not 5×5.
    static func repRange(for info: ExerciseDatabase.ExerciseInfo, intake: CoachIntake) -> String {
        let goal = (intake.goal ?? "").lowercased()
        if goal.contains("strong") || goal.contains("strength") {
            return isCompoundish(info) ? "5" : "8-10"
        }
        if goal.contains("fat") || goal.contains("lose") || goal.contains("condition") {
            return "12-15"
        }
        return isCompoundish(info) ? "6-8" : "10-12"
    }

    /// Working-lift budget for a session. Warmup + rest eat more of the hour
    /// than people expect, so this stays deliberately conservative.
    public static func slots(forMinutes minutes: Int) -> Int {
        switch minutes {
        case ..<35: return 3
        case ..<50: return 5
        case ..<70: return 6
        default:    return 7
        }
    }

    /// The split for a given number of days. Two days is full-body twice —
    /// never a bro split, which leaves most muscles untrained all week.
    public static func split(days: Int) -> [(name: String, parts: [String])] {
        switch days {
        case 1:
            return [("Full Body", ["legs", "chest", "back", "shoulders", "core"])]
        case 2:
            return [("Full Body A", ["legs", "chest", "back", "core"]),
                    ("Full Body B", ["back", "shoulders", "legs", "arms"])]
        case 3:
            return [("Push", ["chest", "shoulders", "arms"]),
                    ("Pull", ["back", "arms"]),
                    ("Legs", ["legs", "core"])]
        case 4:
            return [("Upper A", ["chest", "back"]),
                    ("Lower A", ["legs", "core"]),
                    ("Upper B", ["shoulders", "back", "arms"]),
                    ("Lower B", ["legs", "core"])]
        default:
            return [("Push", ["chest", "shoulders", "arms"]),
                    ("Pull", ["back", "arms"]),
                    ("Legs", ["legs", "core"]),
                    ("Upper", ["chest", "back", "shoulders"]),
                    ("Full Body", ["legs", "back", "core"])]
        }
    }

    /// Draft the whole program. Returned unsaved so the conversation can refine
    /// it first — "here's a draft, want it harder / swap that lift" — which is
    /// what makes this coaching rather than generation.
    public static func draft(from intake: CoachIntake) -> [WorkoutTemplate] {
        let days = intake.daysPerWeek ?? 3
        let minutes = intake.sessionMinutes ?? 45
        let budget = slots(forMinutes: minutes)
        let warmupBlock = warmup(for: intake)

        return split(days: days).map { day in
            let working = selectExercises(for: day.parts, intake: intake, slots: budget)
            let all = warmupBlock + working
            let json = (try? JSONEncoder().encode(all)).flatMap { String(data: $0, encoding: .utf8) }
            return WorkoutTemplate(
                name: day.name,
                exercisesJson: json ?? "[]",
                createdAt: DateFormatters.iso8601.string(from: Date()))
        }
    }
}
