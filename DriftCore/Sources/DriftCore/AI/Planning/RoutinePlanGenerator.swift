import Foundation

/// Pure core of the Coach interview's routine generation: builds the cloud
/// prompt from the TrainingProfile + an equipment-filtered candidate pool,
/// decodes/grounds the model's JSON, and provides the deterministic offline
/// fallback. The iOS `NebiusRoutineGenerator` service owns the actual model
/// call; everything here is Tier-0 testable without a network.
@MainActor
public enum RoutinePlanGenerator {

    // MARK: - Plan types

    public struct PlannedExercise: Codable, Equatable, Sendable {
        public let name: String
        public let sets: Int
        /// Freeform rep prescription ("8-12", "5", "30 sec") — becomes the
        /// template note, never parsed.
        public let reps: String

        public init(name: String, sets: Int, reps: String) {
            self.name = name
            self.sets = sets
            self.reps = reps
        }
    }

    public struct PlannedDay: Codable, Equatable, Sendable {
        public let name: String
        public let exercises: [PlannedExercise]

        public init(name: String, exercises: [PlannedExercise]) {
            self.name = name
            self.exercises = exercises
        }
    }

    // MARK: - Candidate pool

    /// Equipment-filtered exercise names grouped by body part, user-history
    /// names first, capped per part so the prompt stays small. The model may
    /// ONLY pick from this pool — that's the anti-hallucination gate.
    public static func candidatePool(profile: TrainingProfile, perPart: Int = 12) -> [String: [String]] {
        let available: Set<String> = profile.restrictsEquipment
            ? Set(profile.equipment + ["body only"]) : []
        let history = Set((try? WorkoutService.recentExerciseNames(limit: 100)) ?? [])
        var pool: [String: [String]] = [:]
        for part in ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"] {
            let doable = ExerciseDatabase.byBodyPart(part)
                .filter { ExerciseDatabase.isDoable($0, with: available) }
            let sorted = doable.sorted { a, b in
                let (ha, hb) = (history.contains(a.name), history.contains(b.name))
                if ha != hb { return ha }
                return a.name < b.name
            }
            pool[part] = sorted.prefix(perPart).map(\.name)
        }
        return pool
    }

    // MARK: - Prompt

    public static func buildPrompt(profile: TrainingProfile, goalLine: String?,
                                   pool: [String: [String]]) -> String {
        let days = profile.daysPerWeek ?? 3
        let minutes = profile.sessionMinutes ?? 45
        var lines: [String] = []
        lines.append("Design a \(days)-day weekly strength routine, ~\(minutes) minutes per session.")
        if let experience = profile.experience { lines.append("Experience: \(experience.rawValue).") }
        if let goalLine, !goalLine.isEmpty { lines.append("Goal: \(goalLine).") }
        if let priority = profile.priority { lines.append("Prioritize: \(priority).") }
        if !profile.constraints.isEmpty {
            lines.append("HARD constraints — never program around these, work WITH them: \(profile.constraints.joined(separator: "; ")). Choose gentler alternatives for affected areas.")
        }
        lines.append("")
        lines.append("Pick exercises ONLY from this list (grouped by body part):")
        for part in ["Chest", "Back", "Legs", "Shoulders", "Arms", "Core"] {
            if let names = pool[part], !names.isEmpty {
                lines.append("\(part): \(names.joined(separator: " | "))")
            }
        }
        lines.append("")
        lines.append("""
        Return ONLY a JSON object — no prose, no markdown fences — exactly this shape:
        {"days":[{"name":"Push","exercises":[{"name":"Bench Press","sets":3,"reps":"8-12"}]}]}
        Rules: \(days) days; 4-6 exercises per day; every exercise name copied EXACTLY from the list; sets 2-5; reps a short string ("8-12", "5", "30 sec"); balanced week (no muscle group two days in a row); ONE coherent split scheme for the whole week (Push/Pull/Legs OR Upper/Lower OR Full Body A/B — never a mix); day names short.
        """)
        return lines.joined(separator: "\n")
    }

    // MARK: - Decode + grounding

    private struct Response: Codable {
        let days: [PlannedDay]
    }

    /// Decode the model's JSON. Pure; nil when nothing decodable or the shape
    /// is out of bounds (0 or >7 days).
    public nonisolated static func decode(_ raw: String) -> [PlannedDay]? {
        guard let json = extractJSONObject(raw),
              let data = json.data(using: .utf8),
              let resp = try? JSONDecoder().decode(Response.self, from: data),
              (1...7).contains(resp.days.count) else { return nil }
        return resp.days
    }

    /// Ground each planned exercise against the catalog: exact/`match`
    /// resolution, drop unknowns and duplicates, clamp sets. A day that ends
    /// with fewer than 2 real exercises is dropped. nil when nothing survives.
    public static func grounded(_ days: [PlannedDay]) -> [PlannedDay]? {
        var out: [PlannedDay] = []
        for day in days {
            var seen = Set<String>()
            var kept: [PlannedExercise] = []
            for ex in day.exercises {
                guard let info = ExerciseDatabase.info(for: ex.name) ?? ExerciseDatabase.match(name: ex.name),
                      seen.insert(info.name.lowercased()).inserted else { continue }
                kept.append(PlannedExercise(name: info.name,
                                            sets: min(max(ex.sets, 1), 5),
                                            reps: String(ex.reps.prefix(12))))
            }
            if kept.count >= 2 {
                out.append(PlannedDay(name: String(day.name.prefix(24)), exercises: kept))
            }
        }
        return out.isEmpty ? nil : out
    }

    // MARK: - Offline fallback

    /// Deterministic plan when the cloud is unreachable: split chosen by
    /// days/week, exercises from the (equipment-aware) split-day suggester.
    public static func fallbackPlan(profile: TrainingProfile) -> [PlannedDay] {
        let days = min(max(profile.daysPerWeek ?? 3, 1), 6)
        let splitType: String
        switch days {
        case 1: splitType = "full body"
        case 2, 4: splitType = "upper/lower"
        case 3, 6: splitType = "ppl"
        default: splitType = "bro split"
        }
        let def = ExerciseService.splitDefinitions[splitType] ?? []
        guard !def.isEmpty else { return [] }
        // Honor the GIVEN profile, not whatever is stored — the interview
        // calls this before/independent of persistence.
        let available: Set<String> = profile.restrictsEquipment
            ? Set(profile.equipment + ["body only"]) : []
        var out: [PlannedDay] = []
        for i in 0..<days {
            let dayIndex = i % def.count
            let round = i / def.count
            let suffix = round > 0 ? " \(["A", "B", "C"][min(round, 2)])" : ""
            let exercises = ExerciseService.suggestForSplitDay(
                splitType: splitType, dayIndex: dayIndex, availableEquipment: available)
                .prefix(5)
                .map { PlannedExercise(name: $0.name, sets: 3, reps: "8-12") }
            if !exercises.isEmpty {
                out.append(PlannedDay(name: def[dayIndex].name + suffix, exercises: Array(exercises)))
            }
        }
        return out
    }

    /// First brace-balanced `{...}` substring (same approach as
    /// `NebiusExerciseLogger` / `MealTextLogger`).
    nonisolated static func extractJSONObject(_ s: String) -> String? {
        guard let start = s.firstIndex(of: "{") else { return nil }
        var depth = 0
        var idx = start
        while idx < s.endIndex {
            switch s[idx] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(s[start...idx]) }
            default: break
            }
            idx = s.index(after: idx)
        }
        return nil
    }
}
