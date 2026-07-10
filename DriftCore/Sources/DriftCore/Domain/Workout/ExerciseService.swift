import Foundation
import DriftCore

/// Unified exercise/workout service — used by both UI views and AI tool calls.
/// Wraps WorkoutService + ExerciseDatabase + adds smart builder and progressive overload.
@MainActor
public enum ExerciseService {

    /// Reasoning for the last smart session built. Read after calling buildSmartSession().
    public static var lastSessionReasoning: String?

    // MARK: - Template Start

    /// Find a template by name (fuzzy match). Returns nil if no match.
    public static func startTemplate(name: String) -> WorkoutTemplate? {
        guard let templates = try? WorkoutService.fetchTemplates() else { return nil }
        let lower = name.lowercased()
        return templates.first { $0.name.lowercased().contains(lower) }
    }

    // MARK: - Smart Session Builder

    /// Build a smart workout session: max 5 exercises, popular first, with reasoning notes.
    /// If user has history, prioritize their exercises. Otherwise use popular defaults.
    public static func buildSmartSession(muscleGroup: String? = nil) -> WorkoutTemplate? {
        var exercises: [WorkoutTemplate.TemplateExercise] = []
        let userExerciseSet = Set((try? WorkoutService.recentExerciseNames(limit: 50)) ?? [])

        // Determine muscle group + build reasoning
        let targetPart: String
        var reasonLines: [String] = []

        if let group = muscleGroup {
            targetPart = group
            reasonLines.append("Targeting \(group.capitalized) (your request)")
        } else {
            let recentParts = recentBodyParts()
            let allParts = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"]
            let neglected = allParts.filter { !recentParts.contains($0) }
            targetPart = neglected.first ?? "Chest"
            let days = daysSinceLastTrained(targetPart)
            if days < 99 {
                reasonLines.append("Targeting \(targetPart) — \(days) days since last trained")
            } else {
                reasonLines.append("Targeting \(targetPart) — not trained recently")
            }
            if !neglected.isEmpty {
                reasonLines.append("Neglected groups: \(neglected.joined(separator: ", "))")
            }
        }

        // Gather candidates: user history first, then DB. When the profile
        // restricts equipment (home training), drop exercises the user can't
        // actually do — unknown names (customs) get the benefit of the doubt.
        // "body only" keeps the set non-empty for a no-equipment home user —
        // an empty set would read as "no restriction" to isDoable.
        let profile = TrainingProfile.load()
        let available: Set<String> = profile?.restrictsEquipment == true
            ? Set((profile?.equipment ?? []) + ["body only"]) : []
        func doable(_ name: String) -> Bool {
            guard !available.isEmpty else { return true }
            guard let info = ExerciseDatabase.info(for: name) else { return true }
            return ExerciseDatabase.isDoable(info, with: available)
        }
        let groupLower = targetPart.lowercased()
        let fromHistory = userExerciseSet.filter {
            ExerciseDatabase.bodyPart(for: $0).lowercased().contains(groupLower) && doable($0)
        }
        let fromDB = ExerciseDatabase.search(query: targetPart).filter { ExerciseDatabase.isDoable($0, with: available) }.map(\.name)
        let candidates = Array(Set(Array(fromHistory) + fromDB))
        if !available.isEmpty {
            reasonLines.append("Filtered to your equipment: \(available.sorted().joined(separator: ", "))")
        }

        let picked = Array(candidates.prefix(5))
        if picked.isEmpty { return nil }

        // Build exercises with reasoning notes + form tips
        for name in picked {
            let lastWeight = (try? WorkoutService.lastWeight(for: name)).flatMap { $0 }
            let fromUser = userExerciseSet.contains(name)

            // Base: sets/weight info
            var parts: [String] = []
            if let w = lastWeight {
                parts.append("3x10 @ \(Int(w)) lbs")
            } else if fromUser {
                parts.append("3x10")
            } else {
                parts.append("3x10 — start light")
            }

            // Form tip
            if let tip = formTip(for: name) {
                parts.append("Tip: \(tip)")
            }

            exercises.append(WorkoutTemplate.TemplateExercise(name: name, sets: 3, notes: parts.joined(separator: " | ")))
        }

        // Summarize exercise sources in reasoning
        let fromHistoryCount = picked.filter { userExerciseSet.contains($0) }.count
        let fromDBCount = picked.count - fromHistoryCount
        if fromHistoryCount > 0 { reasonLines.append("\(fromHistoryCount) exercises from your history") }
        if fromDBCount > 0 { reasonLines.append("\(fromDBCount) new exercises suggested") }
        lastSessionReasoning = reasonLines.joined(separator: "\n")

        guard let json = try? JSONEncoder().encode(exercises),
              let jsonStr = String(data: json, encoding: .utf8) else { return nil }

        return WorkoutTemplate(
            name: "Coached Workout",
            exercisesJson: jsonStr,
            createdAt: DateFormatters.iso8601.string(from: Date())
        )
    }

    // MARK: - Workout Suggestion

    /// Suggest what to train based on recent history.
    public static func suggestWorkout() -> String {
        let parts = recentBodyParts()
        let allParts = ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"]
        let neglected = allParts.filter { !parts.contains($0) }

        var lines: [String] = []
        if neglected.isEmpty {
            lines.append("You've trained all major muscle groups recently.")
        } else {
            lines.append("Haven't trained: \(neglected.joined(separator: ", "))")
        }

        // Check templates
        if let templates = try? WorkoutService.fetchTemplates(), !templates.isEmpty {
            let names = templates.prefix(3).map(\.name).joined(separator: ", ")
            lines.append("Templates: \(names)")
        }

        let count = (try? WorkoutService.fetchWorkouts(limit: 7))?.filter {
            guard let d = DateFormatters.dateOnly.date(from: $0.date) else { return false }
            return Calendar.current.isDate(d, equalTo: Date(), toGranularity: .weekOfYear)
        }.count ?? 0
        lines.append("This week: \(count) workouts")

        return lines.joined(separator: "\n")
    }

    // MARK: - Progressive Overload

    /// Check if user is in progressive overload for an exercise.
    /// Compares estimated 1RM across last 4 sessions.
    public static func getProgressiveOverload(exercise: String) -> ProgressiveOverloadInfo? {
        let sets = (try? WorkoutService.fetchExerciseHistory(name: exercise)) ?? []
        let workingSets = sets.filter { !$0.isWarmup && $0.weightLbs != nil && $0.reps != nil }
        guard workingSets.count >= 4 else {
            return ProgressiveOverloadInfo(exercise: exercise, status: .insufficientData, sessions: [], trend: "Not enough data (need 4+ sessions)")
        }

        // Group by workout (use exerciseOrder changes as session boundary proxy)
        // Simpler: take the best 1RM from each batch of sets
        var sessionBest: [Double] = []
        var currentBatch: [Double] = []
        var lastWorkoutId = workingSets.first?.workoutId ?? 0

        for s in workingSets {
            if s.workoutId != lastWorkoutId {
                if let best = currentBatch.max() { sessionBest.append(best) }
                currentBatch = []
                lastWorkoutId = s.workoutId
            }
            if let rm = s.estimated1RM { currentBatch.append(rm) }
        }
        if let best = currentBatch.max() { sessionBest.append(best) }

        guard sessionBest.count >= 2 else {
            return ProgressiveOverloadInfo(exercise: exercise, status: .insufficientData, sessions: sessionBest, trend: "Not enough sessions")
        }

        // Compare last 4 sessions
        let recent = Array(sessionBest.prefix(4))
        let first = recent.last!  // oldest
        let last = recent.first!  // newest (history is newest-first)
        let change = last - first

        let status: OverloadStatus
        let trend: String
        if change > 5 {
            status = .improving
            let wu = Preferences.weightUnit
            trend = "Improving: +\(Int(wu.convertFromLbs(change))) \(wu.displayName) estimated 1RM over \(recent.count) sessions"
        } else if change < -5 {
            status = .declining
            let wu = Preferences.weightUnit
            trend = "Declining: \(Int(wu.convertFromLbs(change))) \(wu.displayName) estimated 1RM over \(recent.count) sessions"
        } else {
            status = .stalling
            trend = "Stalling: 1RM roughly the same for \(recent.count) sessions. Try adding weight or reps."
        }

        return ProgressiveOverloadInfo(exercise: exercise, status: status, sessions: recent, trend: trend)
    }

    // MARK: - Exercise Lookup

    /// Resolve a short/informal exercise name to its canonical DB name.
    /// Prefers exercises the user has actually done over generic matches.
    public static func resolveExerciseName(_ query: String) -> String? {
        let results = ExerciseDatabase.search(query: query)
        guard !results.isEmpty else { return nil }
        // Prefer exercises the user has history with
        let userExercises = Set((try? WorkoutService.recentExerciseNames(limit: 200)) ?? [])
        if let used = results.first(where: { userExercises.contains($0.name) }) { return used.name }
        return results.first?.name
    }

    /// Exercises for a muscle group, sorted by user history (popular first).
    static func exercisesByMuscle(group: String) -> [ExerciseDatabase.ExerciseInfo] {
        let userExercises = Set((try? WorkoutService.recentExerciseNames(limit: 100)) ?? [])
        let results = ExerciseDatabase.search(query: group)
        // User's exercises first
        return results.sorted { a, b in
            let aUsed = userExercises.contains(a.name)
            let bUsed = userExercises.contains(b.name)
            if aUsed && !bUsed { return true }
            if !aUsed && bUsed { return false }
            return a.name < b.name
        }
    }

    /// Most popular exercises from user's history.
    static func popularExercises(limit: Int = 10) -> [String] {
        (try? WorkoutService.recentExerciseNames(limit: limit)) ?? []
    }

    // MARK: - Workout Split Builder

    /// Known split types with their day→body-part mappings.
    public static let splitDefinitions: [String: [(name: String, parts: [String])]] = [
        "ppl": [
            (name: "Push", parts: ["Chest", "Shoulders", "Arms"]),
            (name: "Pull", parts: ["Back", "Arms"]),
            (name: "Legs", parts: ["Legs", "Core"]),
        ],
        "upper/lower": [
            (name: "Upper", parts: ["Chest", "Back", "Shoulders", "Arms"]),
            (name: "Lower", parts: ["Legs", "Core"]),
        ],
        "full body": [
            (name: "Full Body", parts: ["Chest", "Back", "Legs", "Shoulders", "Core"]),
        ],
        "bro split": [
            (name: "Chest", parts: ["Chest"]),
            (name: "Back", parts: ["Back"]),
            (name: "Shoulders", parts: ["Shoulders"]),
            (name: "Legs", parts: ["Legs"]),
            (name: "Arms", parts: ["Arms"]),
        ],
    ]

    /// Resolve a user phrase to a known split type key.
    public static func resolveSplitType(_ input: String) -> String? {
        let lower = input.lowercased()
        if lower.contains("ppl") || lower.contains("push pull leg") { return "ppl" }
        if lower.contains("upper") && lower.contains("lower") { return "upper/lower" }
        if lower.contains("full body") || lower.contains("fullbody") { return "full body" }
        if lower.contains("bro") { return "bro split" }
        return nil
    }

    /// Suggest exercises for a given day of a split.
    /// Returns 4-6 exercises: user history prioritized, then DB exercises for the target body parts.
    public static func suggestForSplitDay(splitType: String, dayIndex: Int,
                                          availableEquipment: Set<String>? = nil) -> [ExerciseDatabase.ExerciseInfo] {
        guard let days = splitDefinitions[splitType], dayIndex < days.count else { return [] }
        let dayParts = days[dayIndex].parts
        let userExercises = Set((try? WorkoutService.recentExerciseNames(limit: 100)) ?? [])
        // Equipment-aware, same rule as buildSmartSession: home profile →
        // only exercises the user can actually do ("body only" always in).
        // Callers with their own profile in hand (RoutinePlanGenerator) pass
        // the set explicitly; default derives from the stored profile.
        let available: Set<String>
        if let availableEquipment {
            available = availableEquipment
        } else {
            let profile = TrainingProfile.load()
            available = profile?.restrictsEquipment == true
                ? Set((profile?.equipment ?? []) + ["body only"]) : []
        }

        // Gather candidates from each body part
        var candidates: [ExerciseDatabase.ExerciseInfo] = []
        for part in dayParts {
            let partExercises = ExerciseDatabase.byBodyPart(part)
                .filter { ExerciseDatabase.isDoable($0, with: available) }
            // User's exercises first, then others
            let sorted = partExercises.sorted { a, b in
                let aUsed = userExercises.contains(a.name)
                let bUsed = userExercises.contains(b.name)
                if aUsed && !bUsed { return true }
                if !aUsed && bUsed { return false }
                return a.name < b.name
            }
            candidates.append(contentsOf: sorted.prefix(4))
        }

        // Deduplicate and limit to 6
        var seen: Set<String> = []
        return candidates.filter { seen.insert($0.name).inserted }.prefix(6).map { $0 }
    }

    /// Build a WorkoutTemplate from a list of exercise names.
    public static func buildSplitTemplate(name: String, exerciseNames: [String]) -> WorkoutTemplate? {
        let exercises = exerciseNames.map { exerciseName in
            let lastWeight = (try? WorkoutService.lastWeight(for: exerciseName)).flatMap { $0 }
            var notes: String? = nil
            if let w = lastWeight {
                notes = "3x8-12 @ \(Int(w)) lbs"
            }
            if let tip = formTip(for: exerciseName) {
                notes = (notes ?? "3x8-12") + " | \(tip)"
            }
            return WorkoutTemplate.TemplateExercise(name: exerciseName, sets: 3, notes: notes)
        }
        guard let json = try? JSONEncoder().encode(exercises),
              let jsonStr = String(data: json, encoding: .utf8) else { return nil }
        return WorkoutTemplate(
            name: name,
            exercisesJson: jsonStr,
            createdAt: DateFormatters.iso8601.string(from: Date())
        )
    }

    // MARK: - Helpers

    /// Days since a muscle group was last trained. Returns 99 if never.
    private static func daysSinceLastTrained(_ part: String) -> Int {
        guard let workouts = try? WorkoutService.fetchWorkouts(limit: 20) else { return 99 }
        for w in workouts {
            guard let wId = w.id,
                  let d = DateFormatters.dateOnly.date(from: w.date),
                  let sets = try? WorkoutService.fetchSets(forWorkout: wId) else { continue }
            let parts = Set(sets.map { ExerciseDatabase.bodyPart(for: $0.exerciseName) })
            if parts.contains(part) {
                return Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 99
            }
        }
        return 99
    }

    /// One-line form tip for common exercises. Matched by keyword in exercise name.
    public static func formTip(for exercise: String) -> String? {
        let e = exercise.lowercased()
        // Chest — incline/decline BEFORE the generic bench-press rule, or
        // they'd get the flat-bench cue (2026-07-09 accuracy audit).
        if e.contains("incline") && e.contains("press") { return "30-45 degree angle, control the negative" }
        if e.contains("decline") && e.contains("press") { return "Slight decline, elbows ~45\u{00B0}, bar to lower chest" }
        if e.contains("bench press") && !e.contains("close") { return "Drive feet into floor, retract shoulder blades" }
        if e.contains("fly") || e.contains("flye") { return "Slight bend in elbows, squeeze at the top" }
        if e.contains("push up") || e.contains("pushup") { return "Core tight, elbows 45 degrees from body" }
        if e.contains("dip") { return "Lean forward for chest, upright for triceps" }
        // Back — equipment-specific deadlifts before the barbell cue ("bar
        // close to shins" is wrong for trap bar / dumbbells / sumo).
        if e.contains("trap bar") || e.contains("hex bar") { return "Stand mid-frame, neutral grip at sides, drive through mid-foot" }
        if e.contains("sumo") && e.contains("deadlift") { return "Wide stance, toes out, knees track over toes, hips low" }
        if (e.contains("dumbbell") || e.contains("kettlebell") || e.contains("cable")) && e.contains("deadlift") && !e.contains("romanian") && !e.contains("stiff") {
            return "Hips back, flat back, keep the weights close to your legs"
        }
        if e.contains("deadlift") && !e.contains("romanian") { return "Brace core, push floor away, bar close to shins" }
        if e.contains("romanian") || e.contains("rdl") { return "Hinge at hips, slight knee bend, feel the hamstring stretch" }
        if e.contains("barbell row") || e.contains("bent over row") { return "Pull to lower chest, squeeze shoulder blades" }
        if e.contains("pull up") || e.contains("pullup") || e.contains("chin up") { return "Full hang at bottom, drive elbows down" }
        if e.contains("lat pulldown") { return "Pull to upper chest, lean back slightly" }
        if e.contains("cable row") || e.contains("seated row") { return "Pull to belly, chest up, squeeze back" }
        // Legs
        if e.contains("squat") && !e.contains("split") { return "Brace core, knees track over toes, depth to parallel" }
        if e.contains("leg press") { return "Full range of motion, don't lock knees at top" }
        if e.contains("lunge") || e.contains("split squat") { return "Front knee over ankle, torso upright" }
        if e.contains("leg curl") { return "Control the negative, full contraction at top" }
        if e.contains("leg extension") { return "Pause at top, control the descent" }
        if e.contains("calf raise") || e.contains("calf") { return "Full stretch at bottom, hold peak contraction" }
        if e.contains("hip thrust") { return "Drive through heels, squeeze glutes at top" }
        // Shoulders
        if e.contains("overhead press") || e.contains("shoulder press") || e.contains("military press") { return "Brace core, press straight up, don't flare elbows" }
        if e.contains("lateral raise") { return "Slight forward lean, lead with elbows, control weight" }
        if e.contains("face pull") { return "Pull to forehead, external rotate at end" }
        if e.contains("front raise") { return "Slight bend in elbows, stop at shoulder height" }
        if e.contains("shrug") { return "Straight up, hold at top, no rolling" }
        // Arms
        if e.contains("bicep curl") || e.contains("barbell curl") { return "Pin elbows to sides, full extension at bottom" }
        if e.contains("hammer curl") { return "Neutral grip, control both directions" }
        if e.contains("tricep") && e.contains("push") { return "Lock upper arms, full extension at bottom" }
        if e.contains("skull crusher") || e.contains("lying tricep") { return "Elbows pointed up, lower to forehead" }
        if e.contains("close grip") { return "Hands shoulder-width, elbows tucked" }
        // Core
        if e.contains("plank") { return "Flat back, engage glutes, breathe steady" }
        if e.contains("crunch") || e.contains("sit up") { return "Exhale on the way up, don't pull neck" }
        if e.contains("leg raise") && !e.contains("calf") { return "Press lower back into floor, slow descent" }
        if e.contains("cable woodchop") || e.contains("wood chop") { return "Rotate from hips, arms stay extended" }
        if e.contains("ab wheel") || e.contains("rollout") { return "Brace hard, don't let hips sag" }
        return nil
    }

    /// Formatted exercise instructions from the DB: structured cues when available, form tip fallback, muscles, equipment.
    public static func exerciseInstructions(_ exercise: ExerciseDatabase.ExerciseInfo) -> String {
        var lines: [String] = []
        lines.append("**\(exercise.name)** (\(exercise.category), \(exercise.level))")

        if let cues = exercise.instructions, !cues.isEmpty {
            lines.append(contentsOf: cues)
        } else if let tip = formTip(for: exercise.name) {
            lines.append("Form: \(tip)")
        }

        let primary = exercise.primaryMuscles.joined(separator: ", ")
        if !primary.isEmpty { lines.append("Primary muscles: \(primary)") }

        let secondary = exercise.secondaryMuscles.joined(separator: ", ")
        if !secondary.isEmpty { lines.append("Secondary: \(secondary)") }

        if !exercise.equipment.isEmpty && exercise.equipment != "other" {
            lines.append("Equipment: \(exercise.equipment)")
        }

        return lines.joined(separator: "\n")
    }

    /// Body parts trained in the last 7 days.
    private static func recentBodyParts() -> Set<String> {
        guard let workouts = try? WorkoutService.fetchWorkouts(limit: 7) else { return [] }
        var parts: Set<String> = []
        for w in workouts.prefix(5) {
            guard let wId = w.id,
                  let d = DateFormatters.dateOnly.date(from: w.date),
                  Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 99 < 7,
                  let sets = try? WorkoutService.fetchSets(forWorkout: wId) else { continue }
            for name in Set(sets.map(\.exerciseName)) {
                parts.insert(ExerciseDatabase.bodyPart(for: name))
            }
        }
        return parts
    }
}

// MARK: - Data Types

public enum OverloadStatus: String, Sendable {
    case improving, stalling, declining, insufficientData
}

public struct ProgressiveOverloadInfo: Sendable {
    public let exercise: String
    public let status: OverloadStatus
    public let sessions: [Double]
    public let trend: String
}
