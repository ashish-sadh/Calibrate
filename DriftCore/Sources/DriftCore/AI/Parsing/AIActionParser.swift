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

    /// FM-first variant: when `Preferences.fmWorkoutExtractEnabled` and the
    /// platform supports FoundationModels (iOS 26+), the entire transcript
    /// goes through `FoundationModelsExerciseExtractor` in ONE call so that
    /// novel separators ("then", "followed by", multi-line) work without
    /// comma-splitting. On any failure (unavailable / empty / bounded / session
    /// error / flag-off) the whole input falls back to the comma-split regex
    /// path. Returns the same `WorkoutExercise` shape so existing callers
    /// don't need to know which path ran.
    public static func parseWorkoutExercisesAsync(_ input: String) async -> [WorkoutExercise] {
        guard Preferences.fmWorkoutExtractEnabled else { return parseWorkoutExercises(input) }
        do {
            let entries = try await FoundationModelsExerciseExtractor.extract(text: input)
            let mapped = entries.compactMap(fmExerciseToWorkout)
            return mapped.isEmpty ? parseWorkoutExercises(input) : mapped
        } catch {
            return parseWorkoutExercises(input)
        }
    }

    /// Map one `FMExerciseEntry` to the existing strength-shaped
    /// `WorkoutExercise`; returns nil for non-strength categories so the
    /// caller doesn't synthesize empty sets/reps for cardio/mobility/sports.
    private static func fmExerciseToWorkout(_ entry: FMExerciseEntry) -> WorkoutExercise? {
        guard entry.category == .strength else { return nil }
        return WorkoutExercise(
            name: entry.exerciseName,
            sets: entry.sets ?? 3,
            reps: entry.reps ?? 10,
            weight: entry.weight
        )
    }

    /// Synchronous regex parser for one segment — shared between the sync and
    /// async entry points so they always agree on the fallback behavior.
    private static func parseSingleExerciseRegex(_ part: Substring) -> WorkoutExercise? {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let pattern = #"(.+?)\s+(\d+)x(\d+)(?:@(\d+\.?\d*))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
            return WorkoutExercise(name: trimmed, sets: 3, reps: 10, weight: nil)
        }
        let name = Range(match.range(at: 1), in: trimmed).map { String(trimmed[$0]).trimmingCharacters(in: .whitespaces) } ?? trimmed
        let sets = Range(match.range(at: 2), in: trimmed).flatMap { Int(trimmed[$0]) } ?? 3
        let reps = Range(match.range(at: 3), in: trimmed).flatMap { Int(trimmed[$0]) } ?? 10
        let weight = Range(match.range(at: 4), in: trimmed).flatMap { Double(trimmed[$0]) }
        return WorkoutExercise(name: name, sets: sets, reps: reps, weight: weight)
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
              let end = text.lastIndex(of: "}") else { return text }
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
