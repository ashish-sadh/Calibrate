import Foundation

/// Parses AI responses for action commands and extracts structured data.
public enum AIActionParser {

    public struct WorkoutExercise: Codable, Equatable, Sendable {
        public let name: String
        public let sets: Int
        public let reps: Int
        public let weight: Double?

        public init(name: String, sets: Int, reps: Int, weight: Double?) {
            self.name = name
            self.sets = sets
            self.reps = reps
            self.weight = weight
        }
    }

    public enum Action {
        case logFood(name: String, amount: String?)
        case logWeight(value: Double, unit: String)
        case startWorkout(type: String?)
        case createWorkout(exercises: [WorkoutExercise])
        case showWeight
        case showNutrition
        case none
    }

    /// Extract action from AI response text. Returns the action and clean text (without the bracket command).
    /// Tries JSON tool-call format first, falls back to bracket action tags.
    public static func parse(_ response: String) -> (action: Action, cleanText: String) {
        if let toolCall = parseToolCallJSON(response) {
            let cleanText = stripJSON(from: response)
            let action = actionFromToolCall(toolCall)
            return (action, cleanText)
        }

        var text = response

        if let range = text.range(of: #"\[LOG_FOOD:\s*(.+?)\]"#, options: .regularExpression) {
            let match = String(text[range])
            let content = match.replacingOccurrences(of: "[LOG_FOOD:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            text.removeSubrange(range)
            let parts = extractFoodParts(content)
            return (.logFood(name: parts.name, amount: parts.amount), text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let range = text.range(of: #"\[LOG_WEIGHT:\s*(.+?)\]"#, options: .regularExpression) {
            let match = String(text[range])
            let content = match.replacingOccurrences(of: "[LOG_WEIGHT:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            text.removeSubrange(range)
            let parts = content.split(separator: " ")
            if let value = Double(String(parts.first ?? "")) {
                let unit = parts.count > 1 ? String(parts[1]) : "lbs"
                return (.logWeight(value: value, unit: unit), text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if let range = text.range(of: #"\[CREATE_WORKOUT:\s*(.+?)\]"#, options: .regularExpression) {
            let match = String(text[range])
            let content = match.replacingOccurrences(of: "[CREATE_WORKOUT:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            text.removeSubrange(range)
            let exercises = parseWorkoutExercises(content)
            if !exercises.isEmpty {
                return (.createWorkout(exercises: exercises), text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        if let range = text.range(of: #"\[START_WORKOUT:\s*(.+?)\]"#, options: .regularExpression) {
            let match = String(text[range])
            let content = match.replacingOccurrences(of: "[START_WORKOUT:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            text.removeSubrange(range)
            return (.startWorkout(type: content.isEmpty ? nil : content), text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let range = text.range(of: #"\[SHOW_WEIGHT\]"#, options: .regularExpression) {
            text.removeSubrange(range)
            return (.showWeight, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        if let range = text.range(of: #"\[SHOW_NUTRITION\]"#, options: .regularExpression) {
            text.removeSubrange(range)
            return (.showNutrition, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return (.none, text)
    }

    /// Parse "Push Ups 3x15, Bench Press 3x10@135" into WorkoutExercise array.
    /// Regex-only synchronous path — callers that want the FM-first path call
    /// `parseWorkoutExercisesAsync` instead. Kept as a stable entry point for
    /// the synchronous callers in `actionFromToolCall`.
    public static func parseWorkoutExercises(_ input: String) -> [WorkoutExercise] {
        input.split(separator: ",").compactMap { Self.parseSingleExerciseRegex($0) }
    }

    /// Free-text variant of the regex path: a segment carrying NO sets/reps/weight
    /// signal is DROPPED rather than defaulted to a 3×10 row.
    ///
    /// The two entry points serve opposite contracts. `parseWorkoutExercises`
    /// receives clean tool-call arguments — the model already decided each string
    /// names an exercise, so defaulting bare "Yoga" to 3×10 is right. The async
    /// path receives a raw utterance, where the same default fabricates lifts the
    /// user never did ("3x10 bench, then a 5k run" → a "then a 5k run" 3×10
    /// strength row) — the trust-breaking class of bug the cloud path exists to
    /// fix (#969) — and, because it never returns empty, it also makes the
    /// "that didn't sound like a workout" empty state unreachable.
    private static func parseWorkoutExercisesStrict(_ input: String) -> [WorkoutExercise] {
        input.split(separator: ",").compactMap { Self.parseSingleExerciseRegex($0, allowBareName: false) }
    }

    /// FM-first variant: when `Preferences.fmWorkoutExtractEnabled` and the
    /// platform supports FoundationModels (iOS 26+), the entire transcript
    /// goes through `FoundationModelsExerciseExtractor` in ONE call so that
    /// novel separators ("then", "followed by", multi-line) work without
    /// comma-splitting. On any failure (unavailable / empty / bounded / session
    /// error / flag-off) the whole input falls back to the comma-split regex
    /// path. Returns the same `WorkoutExercise` shape so existing callers
    /// don't need to know which path ran.
    public static func parseWorkoutExercisesAsync(_ input: String) async -> [WorkoutExercise] {
        guard Preferences.fmWorkoutExtractEnabled else { return parseWorkoutExercisesStrict(input) }
        do {
            let entries = try await FoundationModelsExerciseExtractor.extract(text: input)
            let mapped = entries.compactMap { workoutExercise(from: $0) }
            return mapped.isEmpty ? parseWorkoutExercisesStrict(input) : mapped
        } catch {
            return parseWorkoutExercisesStrict(input)
        }
    }

    /// Map one `FMExerciseEntry` to the existing strength-shaped
    /// `WorkoutExercise`; returns nil for non-strength categories so the
    /// caller doesn't synthesize empty sets/reps for cardio/mobility/sports.
    /// Extractor weights are canonically lbs; `displayUnit` converts them to
    /// the unit the caller will show/echo (rounded, note-text precision).
    public static func workoutExercise(from entry: FMExerciseEntry,
                                       displayUnit: WeightUnit = .lbs) -> WorkoutExercise? {
        guard entry.category == .strength else { return nil }
        return WorkoutExercise(
            name: entry.exerciseName,
            sets: entry.sets ?? 3,
            reps: entry.reps ?? 10,
            weight: entry.weight.map { displayUnit.convertFromLbs($0).rounded() }
        )
    }

    /// Synchronous regex parser for one segment — shared between the sync and
    /// async entry points so they always agree on the fallback behavior.
    /// Accepts both orderings: name-first ("Bench Press 3x10@135") and
    /// numbers-first ("3x10 bench at 135" — the phrasing the voice/text sheets
    /// prompt with), with `x`/`×`, optional spaces, and `@N`/`at N` weights.
    /// `allowBareName` false drops a segment that matched neither ordering, so a
    /// raw utterance can't fabricate sets/reps it never carried. See
    /// `parseWorkoutExercisesStrict`.
    private static func parseSingleExerciseRegex(_ part: Substring,
                                                 allowBareName: Bool = true) -> WorkoutExercise? {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let weightSuffix = #"(?:\s*@\s*(\d+\.?\d*)|\s+at\s+(\d+\.?\d*))?"#
        let nameFirst = #"(.+?)\s+(\d+)\s*[x×]\s*(\d+)"# + weightSuffix
        let numbersFirst = #"^(\d+)\s*[x×]\s*(\d+)\s+(.+?)"# + weightSuffix + #"\s*$"#

        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            Range(match.range(at: index), in: trimmed).map { String(trimmed[$0]).trimmingCharacters(in: .whitespaces) }
        }

        if let regex = try? NSRegularExpression(pattern: nameFirst),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            return WorkoutExercise(name: group(match, 1) ?? trimmed,
                                   sets: group(match, 2).flatMap(Int.init) ?? 3,
                                   reps: group(match, 3).flatMap(Int.init) ?? 10,
                                   weight: (group(match, 4) ?? group(match, 5)).flatMap(Double.init))
        }
        if let regex = try? NSRegularExpression(pattern: numbersFirst),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) {
            return WorkoutExercise(name: group(match, 3) ?? trimmed,
                                   sets: group(match, 1).flatMap(Int.init) ?? 3,
                                   reps: group(match, 2).flatMap(Int.init) ?? 10,
                                   weight: (group(match, 4) ?? group(match, 5)).flatMap(Double.init))
        }
        guard allowBareName else { return nil }
        return WorkoutExercise(name: trimmed, sets: 3, reps: 10, weight: nil)
    }

    private static func actionFromToolCall(_ call: ToolCall) -> Action {
        switch call.tool {
        case "log_food", "search_food":
            let name = call.params.string("name") ?? call.params.string("query") ?? ""
            let amount = call.params.string("amount")
            return name.isEmpty ? .none : .logFood(name: name, amount: amount)
        case "log_weight":
            guard let value = call.params.double("value") else { return .none }
            let unit = call.params.string("unit") ?? "lbs"
            return .logWeight(value: value, unit: unit)
        case "start_workout", "start_template":
            let name = call.params.string("name") ?? call.params.string("template")
            return .startWorkout(type: name)
        case "create_workout":
            if let desc = call.params.string("exercises") {
                let exercises = parseWorkoutExercises(desc)
                return exercises.isEmpty ? .none : .createWorkout(exercises: exercises)
            }
            return .none
        default:
            return .none
        }
    }

    private static func stripJSON(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start <= end else { return text }
        var clean = text
        clean.removeSubrange(start...end)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractFoodParts(_ input: String) -> (name: String, amount: String?) {
        let pattern = #"(\d+\.?\d*)\s*(g|ml|oz|cups?|tbsp|tsp|pieces?|servings?)$"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
           let amountRange = Range(match.range, in: input) {
            let amount = String(input[amountRange]).trimmingCharacters(in: .whitespaces)
            let name = String(input[input.startIndex..<amountRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            return (name: name, amount: amount)
        }
        return (name: input, amount: nil)
    }
}
