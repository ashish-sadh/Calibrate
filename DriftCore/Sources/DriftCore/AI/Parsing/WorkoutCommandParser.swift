import Foundation

/// Intent for one utterance typed into the in-workout command strip.
public enum WorkoutCommand: Equatable, Sendable {
    /// Add an exercise ("add face pulls", "incline bench 3x10").
    case add(query: String, sets: Int?)
    /// Remove an exercise from the running session ("drop the leg curls").
    case remove(query: String)
    /// Show last-session history ("what did I bench last time", "last squat?").
    case history(query: String)
    /// "what's next" — the first exercise with unfinished sets.
    case next
    /// "form tips for deadlift", "how do I squat" — local cues from the DB.
    case formTip(query: String)
    /// Open coaching question ("should I go heavier?") — the cloud coach
    /// answers with the live session as context.
    case ask(question: String)
}

/// Deterministic grammar for the ActiveWorkout command strip. Short commands
/// between sets must never wait on a network round-trip — only `.ask` (open
/// questions the grammar can't shape locally) goes to the cloud coach.
public enum WorkoutCommandParser {

    public static func parse(_ raw: String) -> WorkoutCommand {
        let lower = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in ["remove ", "drop ", "delete ", "take out ", "skip "] where lower.hasPrefix(prefix) {
            return .remove(query: stripArticles(String(lower.dropFirst(prefix.count))))
        }

        let bare = lower.hasSuffix("?")
            ? String(lower.dropLast()).trimmingCharacters(in: .whitespaces) : lower
        let words = bare.split(whereSeparator: { !$0.isLetter }).map(String.init)

        // "next" / "what's next" / "what exercise next" — every word is
        // question filler around "next", so it can't be an exercise name.
        let nextFiller: Set<String> = ["what", "whats", "s", "is", "exercise", "exercises",
                                       "up", "next", "should", "i", "do", "now", "comes"]
        if words.contains("next"), words.allSatisfy({ nextFiller.contains($0) }) {
            return .next
        }

        // Form / technique questions — before history so a trailing "?"
        // doesn't hijack "how to correct my bench form?".
        let formMarkers = ["form", "tip", "technique", "cue", "how do i ", "how to "]
        if formMarkers.contains(where: { bare.contains($0) }) {
            return .formTip(query: stripFormWords(bare))
        }

        // History needs a history word — a bare "?" is an open question, not
        // a lookup. Exception: one/two-word shorthand ("last bench?",
        // "bench?") keeps the quick-lookup feel.
        if bare.contains("last") || bare.contains("history")
            || bare.hasPrefix("what did") || bare.hasPrefix("what was")
            || (lower.hasSuffix("?") && words.count <= 2) {
            return .history(query: stripHistoryWords(bare))
        }

        // Open question → the cloud coach ("should I go heavier on bench").
        let questionStarters: Set<String> = ["what", "how", "why", "should", "can", "could",
                                             "is", "are", "am", "do", "does", "when", "which", "will"]
        if lower.hasSuffix("?") || questionStarters.contains(words.first ?? "") {
            return .ask(question: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        var query = lower
        for prefix in ["add ", "put in ", "throw in ", "include "] where query.hasPrefix(prefix) {
            query = String(query.dropFirst(prefix.count))
            break
        }
        let (sets, name) = extractSets(from: stripArticles(query))
        return .add(query: name, sets: sets)
    }

    /// Reduce a form question to the exercise words:
    /// "how to correct my bench form" → "bench".
    static func stripFormWords(_ text: String) -> String {
        let stop: Set<String> = ["form", "tip", "tips", "technique", "cue", "cues", "for",
                                 "how", "hows", "do", "does", "i", "to", "on", "the", "my", "a", "an",
                                 "correct", "fix", "improve", "proper", "good", "some", "any",
                                 "what", "whats", "are", "is", "me", "give", "show", "of",
                                 "with", "check", "about", "doing", "perform",
                                 // leftover fragments after possessives/deixis so a bare
                                 // "how's my form" / "form check on this" → "" → current lift
                                 "s", "this", "it", "current", "here", "now", "please"]
        return text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { !stop.contains($0) }
            .joined(separator: " ")
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
