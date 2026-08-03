import Foundation

/// Intent for one utterance typed into the in-workout command strip.
public enum WorkoutCommand: Equatable, Sendable {
    /// Add an exercise ("add face pulls", "incline bench 3x10").
    case add(query: String, sets: Int?)
    /// Remove an exercise from the running session ("drop the leg curls").
    case remove(query: String)
    /// Swap one exercise for another ("replace squats with leg press").
    ///
    /// `new` is nil when they didn't name a substitute ("swap the squats",
    /// "replace this") — the handler picks one that trains the same thing.
    /// That's the case worth getting right: someone whose rack is taken knows
    /// what they want to stop doing, not what to do instead.
    case replace(old: String, new: String?, sets: Int?)
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

        // SWAP, before remove: "swap out the squats" starts with a swap verb,
        // and reading it as a removal would silently drop the lift instead of
        // substituting one — the destructive misread of the two.
        if let swap = parseReplace(lower) { return swap }

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

    /// Verbs that mean "give me a different exercise for this one".
    ///
    /// "skip" is deliberately absent — it lives in the remove list, and someone
    /// skipping a lift is dropping it, not asking for a replacement.
    private static let swapVerbs = ["replace ", "swap out ", "swap ", "substitute ",
                                    "sub out ", "sub ", "change ", "switch out ", "switch "]

    /// Separators between the old exercise and the new one. Order matters:
    /// " with " must be tried before " w " so "with" isn't clipped mid-word.
    private static let swapSeparators = [" with ", " for ", " to ", " instead of ", " into "]

    /// "replace squats with leg press" → .replace(old: "squats", new: "leg press").
    /// "swap the squats"               → .replace(old: "squats", new: nil).
    ///
    /// Returns nil when this isn't a swap at all, so the caller falls through
    /// to the rest of the grammar.
    static func parseReplace(_ lower: String) -> WorkoutCommand? {
        guard let verb = swapVerbs.first(where: { lower.hasPrefix($0) }) else { return nil }
        let rest = stripArticles(String(lower.dropFirst(verb.count)))
        guard !rest.isEmpty else { return nil }

        // "instead of" inverts the order: "leg press instead of squats".
        if let range = rest.range(of: " instead of ") {
            let new = stripArticles(String(rest[..<range.lowerBound]))
            let old = stripArticles(String(rest[range.upperBound...]))
            guard !old.isEmpty else { return nil }
            let (sets, name) = extractSets(from: new)
            return .replace(old: old, new: name.isEmpty ? nil : name, sets: sets)
        }

        for separator in swapSeparators {
            guard let range = rest.range(of: separator) else { continue }
            let old = stripArticles(String(rest[..<range.lowerBound]))
            let newRaw = stripArticles(String(rest[range.upperBound...]))
            guard !old.isEmpty else { return nil }
            // "swap squats for something easier" names no exercise — treat it
            // as "pick one for me" rather than searching for "something easier".
            let (sets, name) = extractSets(from: newRaw)
            let vague = name.isEmpty || vagueTargets.contains(name)
            return .replace(old: old, new: vague ? nil : name, sets: sets)
        }

        // No separator: "swap the squats" / "replace this".
        let (sets, name) = extractSets(from: rest)
        return .replace(old: name, new: nil, sets: sets)
    }

    /// Phrases that mean "you choose" rather than naming an exercise.
    private static let vagueTargets: Set<String> = [
        "something", "something else", "something easier", "something harder",
        "anything", "anything else", "another", "another one", "an alternative",
        "alternative", "a different one", "different one", "something lighter",
        "something similar", "the same thing", "whatever",
    ]

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
