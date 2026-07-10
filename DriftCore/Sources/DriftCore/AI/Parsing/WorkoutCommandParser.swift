import Foundation

/// Intent for one utterance typed into the in-workout command strip.
public enum WorkoutCommand: Equatable, Sendable {
    /// Add an exercise ("add face pulls", "incline bench 3x10").
    case add(query: String, sets: Int?)
    /// Remove an exercise from the running session ("drop the leg curls").
    case remove(query: String)
    /// Show last-session history ("what did I bench last time", "last squat?").
    case history(query: String)
}

/// Deterministic grammar for the ActiveWorkout command strip. Short commands
/// between sets must never wait on a network round-trip — the cloud parser is
/// the caller's fallback for anything this can't shape, not the first hop.
public enum WorkoutCommandParser {

    public static func parse(_ raw: String) -> WorkoutCommand {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in ["remove ", "drop ", "delete ", "take out ", "skip "] where lower.hasPrefix(prefix) {
            return .remove(query: stripArticles(String(lower.dropFirst(prefix.count))))
        }

        if lower.hasSuffix("?") || lower.contains("last time") || lower.contains("history")
            || lower.hasPrefix("last ") || lower.hasPrefix("what did") || lower.hasPrefix("what was") {
            return .history(query: stripHistoryWords(lower))
        }

        var query = lower
        for prefix in ["add ", "put in ", "throw in ", "include "] where query.hasPrefix(prefix) {
            query = String(query.dropFirst(prefix.count))
            break
        }
        let (sets, name) = extractSets(from: stripArticles(query))
        return .add(query: name, sets: sets)
    }

    /// "incline bench 3x10" → (3, "incline bench"); "4 sets of curls" → (4, "curls").
    static func extractSets(from text: String) -> (sets: Int?, name: String) {
        // NxM shorthand anywhere in the string
        if let match = text.range(of: #"(\d+)\s*[x×]\s*\d+"#, options: .regularExpression) {
            let token = String(text[match])
            let sets = Int(token.prefix(while: \.isNumber))
            let name = text.replacingOccurrences(of: token, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,@-"))
            return (sets, name)
        }
        // "N sets (of)"
        if let match = text.range(of: #"(\d+)\s*sets?(\s+of)?"#, options: .regularExpression) {
            let token = String(text[match])
            let sets = Int(token.prefix(while: \.isNumber))
            let name = text.replacingOccurrences(of: token, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
            return (sets, name)
        }
        return (nil, text)
    }

    /// Reduce a history question to the exercise words:
    /// "what did i bench last time" → "bench".
    static func stripHistoryWords(_ text: String) -> String {
        let stop: Set<String> = ["what", "did", "i", "do", "my", "the", "was", "is",
                                 "last", "time", "week", "session", "history", "for",
                                 "show", "me", "on", "at", "lift", "use"]
        return text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stop.contains($0) }
            .joined(separator: " ")
    }

    static func stripArticles(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        for article in ["the ", "a ", "an ", "some "] where t.hasPrefix(article) {
            t = String(t.dropFirst(article.count))
            break
        }
        return t
    }
}
