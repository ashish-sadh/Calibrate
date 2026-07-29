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
        "chest":      ["Bench Press", "Pushups", "Dumbbell Bench Press", "Incline Dumbbell Press"],
        "back":       ["Pullups", "Barbell Deadlift", "Bent Over Barbell Row", "Lat Pulldown", "Seated Cable Rows"],
        "legs":       ["Barbell Squat", "Romanian Deadlift", "Leg Press", "Walking Lunge", "Leg Curl"],
        "shoulders":  ["Overhead Press", "Dumbbell Lateral Raise", "Face Pull"],
        "arms":       ["Barbell Curl", "Triceps Pushdown", "Dumbbell Curl"],
        // Push and pull days pull from different halves of the arm. Filing both
        // under "arms" is why a push day came back with Barbell Curl on it.
        "triceps":    ["Triceps Pushdown", "Dips - Triceps Version", "Bench Dips"],
        "biceps":     ["Barbell Curl", "Dumbbell Curl", "Alternate Hammer Curl"],
        "core":       ["Plank", "Hanging Leg Raise", "Cable Crunch"],
    ]

    /// Movements that need a barbell — dropped when the user said machines only.
    static let barbellMovements: Set<String> = [
        "bench press", "barbell squat", "barbell deadlift",
        "bent over barbell row", "overhead press", "romanian deadlift", "barbell curl",
    ]

    /// Every curated name above, for the guard test. A staple that stops
    /// resolving is invisible at runtime — the exercise just quietly never
    /// appears in anyone's program — so it gets asserted rather than trusted.
    static var curatedNames: [String] {
        staples.values.flatMap { $0 }
            + ["Cat Stretch", "World's Greatest Stretch", "Glute Bridge", "Band Pull Apart",
               "Mountain Climbers", "Arm Circles", "Bodyweight Squat"]
    }

    /// A warmup that costs five minutes and prevents the injury that costs six
    /// weeks. Mobility-flavoured when the user asked for mobility or reported
    /// pain, generic otherwise.
    public static func warmup(for intake: CoachIntake) -> [WorkoutTemplate.TemplateExercise] {
        let wantsMobility = intake.requests.contains { $0.lowercased().contains("mobility") }
            || intake.painLevel != nil
        let names = wantsMobility
            ? ["Cat Stretch", "World's Greatest Stretch", "Glute Bridge", "Band Pull Apart"]
            : ["Mountain Climbers", "Arm Circles", "Bodyweight Squat", "Glute Bridge"]

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
        var usedNames = Set<String>()

        /// Candidates for one body part, best first: what the user already does,
        /// then the staples, then simple beginner entries.
        func queue(for part: String) -> [ExerciseDatabase.ExerciseInfo] {
            var out: [ExerciseDatabase.ExerciseInfo] = []
            var seen = Set<String>()

            func add(_ info: ExerciseDatabase.ExerciseInfo?) {
                guard let info, allows(info, intake: intake),
                      seen.insert(info.name.lowercased()).inserted else { return }
                out.append(info)
            }

            for name in intake.familiarExercises {
                guard let match = ExerciseDatabase.match(name: name),
                      match.bodyPart.lowercased().contains(part) else { continue }
                add(match)
            }
            for name in staples[part] ?? [] { add(staple(named: name)) }
            for info in ExerciseDatabase.all
                where info.bodyPart.lowercased().contains(part)
                    && info.level.lowercased() == "beginner" {
                add(info)
            }
            return out
        }

        // Round-robin across the day's muscle groups rather than draining one
        // before starting the next. Depth-first is why "Full Body" used to come
        // back as five leg exercises: legs alone has five staples and a 45-min
        // session has five slots, so nothing else ever got picked.
        var queues = bodyParts.map { (part: $0, items: queue(for: $0)) }
        var cursors = [Int](repeating: 0, count: queues.count)
        var chosen: [ExerciseDatabase.ExerciseInfo] = []

        while chosen.count < slots {
            var tookOne = false
            for index in queues.indices where chosen.count < slots {
                while cursors[index] < queues[index].items.count {
                    let candidate = queues[index].items[cursors[index]]
                    cursors[index] += 1
                    if usedNames.insert(candidate.name.lowercased()).inserted {
                        chosen.append(candidate)
                        tookOne = true
                        break
                    }
                }
            }
            // Every queue is exhausted — stop rather than spin forever.
            if !tookOne { break }
        }

        // Heavy compounds first, accessories after. Round-robin picks a good
        // SET of lifts but leaves them in rotation order, which is how a pull
        // day ended up curling before it rowed. Order is stable within each
        // group so the rotation's variety survives the sort.
        let ordered = chosen.enumerated()
            .sorted { a, b in
                let (ca, cb) = (isCompoundish(a.element), isCompoundish(b.element))
                return ca == cb ? a.offset < b.offset : ca && !cb
            }
            .map(\.element)

        return ordered.map { info in
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

    /// Resolve a staple to the PLAINEST movement that matches.
    ///
    /// `ExerciseDatabase.match` falls back to fuzzy token matching, which is
    /// right for parsing what a user typed and wrong here: asking for "Barbell
    /// Bench Press" returned *Barbell Guillotine Bench Press*, and "Pullups"
    /// returned *Weighted Pull Ups*. Both contain every query token, both are
    /// variations nobody asked for, and one of them is a movement you should
    /// not hand a beginner. When several entries match, the one with the fewest
    /// extra words is the one a coach means.
    static func staple(named name: String) -> ExerciseDatabase.ExerciseInfo? {
        let query = name.lowercased()
        let wanted = Set(query.split { !$0.isLetter }.map(String.init).filter { $0.count >= 2 })
        guard !wanted.isEmpty else { return ExerciseDatabase.match(name: name) }

        let candidates = ExerciseDatabase.all.filter { info in
            let words = Set(info.name.lowercased().split { !$0.isLetter }.map(String.init))
            return wanted.isSubset(of: words)
        }
        // Fewest words wins; ties broken alphabetically so the pick is stable
        // across runs rather than depending on file order.
        if let plainest = candidates.min(by: { a, b in
            let (aw, bw) = (a.name.split(separator: " ").count, b.name.split(separator: " ").count)
            return aw == bw ? a.name < b.name : aw < bw
        }) { return plainest }

        return ExerciseDatabase.match(name: name)
    }

    /// Honour "machines only" and steer away from a painful area — a program
    /// that loads a sore back is worse than no program.
    static func allows(_ info: ExerciseDatabase.ExerciseInfo, intake: CoachIntake) -> Bool {
        if intake.usesBarbell == false, barbellMovements.contains(info.name.lowercased()) {
            return false
        }
        // Only avoid loading a problem area when it actually hurts. A noted-but
        // painless area still gets trained — avoidance is how weak links persist.
        guard let pain = intake.painLevel, pain >= 4 else { return true }

        let muscles = (info.primaryMuscles + [info.bodyPart]).map { $0.lowercased() }
        if intake.problemAreas.contains(where: { area in
            muscles.contains { $0.contains(area.lowercased()) }
        }) { return false }

        // Muscle tags are not enough for the spine. A Romanian deadlift is
        // filed under Legs and a back squat under Legs, so a "lower back"
        // complaint sailed straight past the check above and the coach happily
        // programmed the two worst movements for a sore back. These load the
        // spine whatever the DB calls them.
        if intake.problemAreas.contains(where: { isBackComplaint($0) }),
           spinalLoaders.contains(info.name.lowercased()) {
            return false
        }
        return true
    }

    /// Movements that compress or shear the spine under load, regardless of the
    /// body part they're filed under.
    static let spinalLoaders: Set<String> = [
        "barbell squat", "barbell deadlift", "romanian deadlift", "bent over barbell row",
        "overhead press", "good morning", "front barbell squat", "barbell full squat",
        "sumo deadlift", "stiff leg barbell deadlift", "t-bar row", "power clean",
    ]

    static func isBackComplaint(_ area: String) -> Bool {
        let a = area.lowercased()
        return a.contains("back") || a.contains("spine") || a.contains("disc")
            || a.contains("lumbar") || a.contains("sciatic")
    }

    /// Multi-joint lifts that earn the first slot and the long rest.
    ///
    /// This used to reuse `barbellMovements`, which conflated "needs a barbell"
    /// with "is a compound" — so Barbell Curl was ranked a compound and got
    /// sorted to the top of pull day ahead of rows and pull-ups. Isolation is
    /// isolation whatever it's loaded with.
    static let isolationLifts: Set<String> = [
        "barbell curl", "dumbbell curl", "alternate hammer curl",
        "triceps pushdown", "dumbbell lateral raise", "face pull", "leg curl",
        "cable crunch",
    ]

    static func isCompoundish(_ info: ExerciseDatabase.ExerciseInfo) -> Bool {
        if isolationLifts.contains(info.name.lowercased()) { return false }
        return info.primaryMuscles.count > 1 || barbellMovements.contains(info.name.lowercased())
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
            return [("Push", ["chest", "shoulders", "triceps"]),
                    ("Pull", ["back", "biceps"]),
                    ("Legs", ["legs", "core"])]
        case 4:
            return [("Upper A", ["chest", "back", "triceps"]),
                    ("Lower A", ["legs", "core"]),
                    ("Upper B", ["shoulders", "back", "biceps"]),
                    ("Lower B", ["legs", "core"])]
        default:
            return [("Push", ["chest", "shoulders", "triceps"]),
                    ("Pull", ["back", "biceps"]),
                    ("Legs", ["legs", "core"]),
                    ("Upper", ["chest", "back", "shoulders"]),
                    ("Full Body", ["legs", "back", "core"])]
        }
    }

    /// What the user is actually asking for. The old flow only ever produced a
    /// week of templates, so "give me something for today" got a filing-cabinet
    /// answer to a right-now question.
    public enum Ask: Sendable, Equatable {
        /// One session to do now.
        case today
        /// A reusable weekly split.
        case program
    }

    /// A single session for today, optionally aimed at a focus the user named
    /// ("legs", "upper", "push"). Free of the weekly split entirely — someone
    /// asking what to do this evening does not need a program first.
    ///
    /// `recentBodyParts` is what they trained in the last few days, so today
    /// avoids hammering the same muscles again. That is the difference between
    /// a coach and a random generator.
    public static func todaySession(from intake: CoachIntake,
                                    focus: String? = nil,
                                    recentBodyParts: [String] = []) -> WorkoutTemplate {
        let minutes = intake.sessionMinutes ?? 45
        let parts = focusParts(focus, intake: intake, recent: recentBodyParts)
        let working = selectExercises(for: parts, intake: intake, slots: slots(forMinutes: minutes))
        let all = warmup(for: intake) + working
        let json = (try? JSONEncoder().encode(all)).flatMap { String(data: $0, encoding: .utf8) }
        return WorkoutTemplate(
            name: sessionName(focus: focus, parts: parts),
            exercisesJson: json ?? "[]",
            createdAt: DateFormatters.iso8601.string(from: Date()))
    }

    /// Resolve "what should today hit". An explicit focus wins; otherwise train
    /// what hasn't been trained recently; otherwise full body, which is the
    /// right default for one-off sessions.
    static func focusParts(_ focus: String?, intake: CoachIntake, recent: [String]) -> [String] {
        let all = ["legs", "chest", "back", "shoulders", "arms", "core"]

        if let focus = focus?.lowercased(), !focus.isEmpty {
            switch focus {
            case let f where f.contains("push"):  return ["chest", "shoulders", "triceps"]
            case let f where f.contains("pull"):  return ["back", "biceps"]
            case let f where f.contains("upper"): return ["chest", "back", "shoulders", "arms"]
            case let f where f.contains("lower"): return ["legs", "core"]
            case let f where f.contains("full"):  return all
            default:
                let named = all.filter { focus.contains($0) }
                if !named.isEmpty { return named }
            }
        }

        // Nothing named: prefer muscles that are actually rested.
        let tired = Set(recent.map { $0.lowercased() })
        let fresh = all.filter { part in !tired.contains { $0.contains(part) } }
        return fresh.count >= 3 ? fresh : all
    }

    static func sessionName(focus: String?, parts: [String]) -> String {
        if let focus, !focus.trimmingCharacters(in: .whitespaces).isEmpty {
            return focus.prefix(1).uppercased() + focus.dropFirst() + " Day"
        }
        return parts.count >= 5 ? "Full Body" : parts.map { $0.capitalized }.joined(separator: " + ")
    }

    // MARK: - Explaining the draft

    /// One-line "why this plan". The old one-shot generator explained itself
    /// ("Targeting Chest — not trained recently"); the conversational draft
    /// lost that (operator 2026-07-29: "does the plan explain why it was
    /// picked?"). Deterministic from the intake — no LLM call, Tier-0 tested.
    public static func rationale(for intake: CoachIntake) -> String {
        let days = intake.daysPerWeek ?? 3
        let minutes = intake.sessionMinutes ?? 45
        let plan = split(days: days)

        var built = "Built for \(days) day\(days == 1 ? "" : "s") a week, ~\(minutes) min each"
        if let equipment = intake.equipment, !equipment.isEmpty {
            built += ", with \(equipment.lowercased())"
        }
        if let goal = intake.goal, !goal.isEmpty {
            built += " — aimed at \(goal.lowercased())"
        }

        // Truthful frequency claim, computed from the split itself.
        let counts = Dictionary(grouping: plan.flatMap(\.parts), by: { $0 }).mapValues(\.count)
        let frequency = (counts.values.max() ?? 1) > 1
            ? "the big groups come back more than once a week"
            : "each group gets a focused day"
        let names = plan.map(\.name).joined(separator: " / ")
        return "\(built). \(names): \(frequency)."
    }

    /// Ordered, deduped muscle coverage of a drafted day — computed from the
    /// exercises themselves rather than the split it came from, so a refined
    /// draft ("swap the deadlift") stays truthful.
    public static func muscleCoverage(of template: WorkoutTemplate) -> [String] {
        var seen: [String] = []
        for exercise in template.exercises where !exercise.isWarmup {
            guard let info = ExerciseDatabase.info(for: exercise.name) else { continue }
            let primary = info.primaryMuscles.isEmpty ? [info.bodyPart] : info.primaryMuscles
            for muscle in primary {
                let name = muscle.capitalized
                if !seen.contains(name) { seen.append(name) }
            }
        }
        return seen
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
