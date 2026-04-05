import Foundation

/// Parses AI responses for action commands and extracts structured data.
enum AIActionParser {

    enum Action {
        case logFood(name: String, amount: String?)  // [LOG_FOOD: chicken breast 200g]
        case logWeight(value: Double, unit: String)   // [LOG_WEIGHT: 165 lbs]
        case startWorkout(type: String?)              // [START_WORKOUT: legs]
        case showWeight                                // [SHOW_WEIGHT]
        case showNutrition                             // [SHOW_NUTRITION]
        case none
    }

    /// Extract action from AI response text. Returns the action and clean text (without the bracket command).
    static func parse(_ response: String) -> (action: Action, cleanText: String) {
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
