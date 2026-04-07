import Foundation

/// Parses AI responses for action commands and extracts structured data.
enum AIActionParser {

    struct WorkoutExercise {
        let name: String
        let sets: Int
        let reps: Int
        let weight: Double?
    }

    enum Action {
        case logFood(name: String, amount: String?)  // [LOG_FOOD: chicken breast 200g]
        case logWeight(value: Double, unit: String)   // [LOG_WEIGHT: 165 lbs]
        case startWorkout(type: String?)              // [START_WORKOUT: legs]
        case createWorkout(exercises: [WorkoutExercise]) // [CREATE_WORKOUT: Push Ups 3x15, Bench 3x10@135]
        case showWeight                                // [SHOW_WEIGHT]
        case showNutrition                             // [SHOW_NUTRITION]
        case none
    }

    /// Extract action from AI response text. Returns the action and clean text (without the bracket command).
    /// Tries JSON tool-call format first, falls back to bracket action tags.
    static func parse(_ response: String) -> (action: Action, cleanText: String) {
        // Try JSON tool-call format first: {"tool":"name","params":{...}}
        if let toolCall = parseToolCallJSON(response) {
            let cleanText = stripJSON(from: response)
            let action = actionFromToolCall(toolCall)
            return (action, cleanText)
        }

        var text = response

        // [LOG_FOOD: ...]
        if let range = text.range(of: #"\[LOG_FOOD:\s*(.+?)\]"#, options: .regularExpression) {
            let match = String(text[range])
            let content = match.replacingOccurrences(of: "[LOG_FOOD:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            text.removeSubrange(range)
            // Try to separate name from amount (e.g., "chicken breast 200g")
            let parts = extractFoodParts(content)
            return (.logFood(name: parts.name, amount: parts.amount), text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // [LOG_WEIGHT: 165 lbs]
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

        // [CREATE_WORKOUT: Push Ups 3x15, Bench Press 3x10@135]
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

        // [START_WORKOUT: ...]
        if let range = text.range(of: #"\[START_WORKOUT:\s*(.+?)\]"#, options: .regularExpression) {
            let match = String(text[range])
            let content = match.replacingOccurrences(of: "[START_WORKOUT:", with: "")
                .replacingOccurrences(of: "]", with: "")
                .trimmingCharacters(in: .whitespaces)
            text.removeSubrange(range)
            return (.startWorkout(type: content.isEmpty ? nil : content), text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // [SHOW_WEIGHT]
        if let range = text.range(of: #"\[SHOW_WEIGHT\]"#, options: .regularExpression) {
            text.removeSubrange(range)
            return (.showWeight, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        // [SHOW_NUTRITION]
        if let range = text.range(of: #"\[SHOW_NUTRITION\]"#, options: .regularExpression) {
            text.removeSubrange(range)
            return (.showNutrition, text.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return (.none, text)
    }

    /// Parse "Push Ups 3x15, Bench Press 3x10@135" into WorkoutExercise array.
    private static func parseWorkoutExercises(_ input: String) -> [WorkoutExercise] {
        input.split(separator: ",").compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            // Match: "Exercise Name 3x15" or "Exercise Name 3x10@135"
            let pattern = #"(.+?)\s+(\d+)x(\d+)(?:@(\d+\.?\d*))?"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)) else {
                // No sets/reps pattern — treat as exercise name only
                return trimmed.isEmpty ? nil : WorkoutExercise(name: trimmed, sets: 3, reps: 10, weight: nil)
            }
            let name = Range(match.range(at: 1), in: trimmed).map { String(trimmed[$0]).trimmingCharacters(in: .whitespaces) } ?? trimmed
            let sets = Range(match.range(at: 2), in: trimmed).flatMap { Int(trimmed[$0]) } ?? 3
            let reps = Range(match.range(at: 3), in: trimmed).flatMap { Int(trimmed[$0]) } ?? 10
            let weight = Range(match.range(at: 4), in: trimmed).flatMap { Double(trimmed[$0]) }
            return WorkoutExercise(name: name, sets: sets, reps: reps, weight: weight)
        }
    }

    /// Convert a parsed ToolCall into an Action enum.
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
            // JSON params might have exercises as a string description
            if let desc = call.params.string("exercises") {
                let exercises = parseWorkoutExercises(desc)
                return exercises.isEmpty ? .none : .createWorkout(exercises: exercises)
            }
            return .none
        default:
            return .none
        }
    }

    /// Strip JSON object from response text for clean display.
    private static func stripJSON(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return text }
        var clean = text
        clean.removeSubrange(start...end)
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Try to separate "chicken breast 200g" into name="chicken breast" amount="200g"
    private static func extractFoodParts(_ input: String) -> (name: String, amount: String?) {
        // Look for amount pattern at end: number + unit (g, ml, oz, cup, etc.)
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
