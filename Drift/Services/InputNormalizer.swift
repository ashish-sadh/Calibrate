import Foundation

/// Lightweight text preprocessing before AI pipeline.
/// Cleans voice artifacts, filler words, and whitespace so the LLM classifier
/// (or rule matchers) see clean input. No LLM calls — pure string transforms.
///
/// Design doc: #65 (Step 0 of new pipeline)
/// Sprint task: #78
enum InputNormalizer {

    // MARK: - Public API

    /// Normalize raw user input for the AI pipeline.
    /// Strips filler words, collapses whitespace, fixes voice artifacts.
    /// Returns cleaned text (never empty — falls back to original).
    static func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return input }

        text = removeMidSentenceCorrections(text)
        text = removeFillerWords(text)
        text = removePartialRestarts(text)
        text = collapseRepeatedWords(text)
        text = fixCommonContractions(text)
        text = normalizeWhitespace(text)
        text = trimLeadingConjunctions(text)

        // Never return empty — fall back to original
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? input.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }

    // MARK: - Mid-Sentence Corrections

    /// Voice users often correct themselves: "chicken no wait I mean rice" → "rice"
    /// Strip everything before the correction marker.
    private static let correctionMarkers = [
        "no wait i mean ", "no i mean ", "no i meant ",
        "actually no ", "actually i meant ", "actually i mean ",
        "wait no ", "no wait ", "i meant ", "sorry i mean ",
    ]

    static func removeMidSentenceCorrections(_ text: String) -> String {
        let lower = text.lowercased()
        // Find the last correction marker (user may correct multiple times)
        var bestIndex: String.Index? = nil
        var bestMarkerLen = 0
        for marker in correctionMarkers {
            if let range = lower.range(of: marker, options: .backwards) {
                if bestIndex == nil || range.lowerBound > bestIndex! {
                    bestIndex = range.lowerBound
                    bestMarkerLen = marker.count
                }
            }
        }
        guard let idx = bestIndex else { return text }
        let afterMarker = String(text[text.index(idx, offsetBy: bestMarkerLen)...])
            .trimmingCharacters(in: .whitespaces)
        return afterMarker.isEmpty ? text : afterMarker
    }

    // MARK: - Filler Words

    /// Single-word fillers removed via word-boundary splitting.
    private static let singleFillers: Set<String> = [
        "umm", "um", "uh", "uhh", "hmm", "hm",
        "like", "basically", "literally", "actually"
    ]

    /// Multi-word fillers removed via substring replacement.
    private static let multiFillers = [
        "you know", "i mean", "sort of", "kind of",
        "so yeah", "well yeah", "oh yeah",
        "let me see", "let me think"
    ]

    static func removeFillerWords(_ text: String) -> String {
        var result = text

        // Remove multi-word fillers first (case-insensitive)
        for filler in multiFillers {
            result = result.replacingOccurrences(of: filler, with: " ", options: .caseInsensitive)
        }

        // Remove single-word fillers (check lowercased, preserve original casing)
        let words = result.split(separator: " ", omittingEmptySubsequences: true)
        let filtered = words.filter { !singleFillers.contains($0.lowercased()) }

        if filtered.isEmpty { return text }
        return filtered.map(String.init).joined(separator: " ")
    }

    // MARK: - Partial Restarts

    /// Voice input often has false starts: "I had I had 2 eggs"
    /// or "log log rice". Detect and remove the restart.
    static func removePartialRestarts(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 4 else { return text }

        // Check for 1-3 word prefix repeated immediately after
        for prefixLen in 1...min(3, words.count / 2) {
            let prefix = words[0..<prefixLen].map { $0.lowercased() }
            let next = words[prefixLen..<min(prefixLen * 2, words.count)].map { $0.lowercased() }

            if prefix.count <= next.count && prefix == Array(next.prefix(prefix.count)) {
                // Remove the first occurrence (the false start)
                return words[prefixLen...].joined(separator: " ")
            }
        }
        return text
    }

    // MARK: - Repeated Words

    /// Collapse consecutive identical words: "the the rice" → "the rice"
    static func collapseRepeatedWords(_ text: String) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard words.count >= 2 else { return text }

        var result: [String] = [words[0]]
        for i in 1..<words.count {
            if words[i].lowercased() != words[i - 1].lowercased() {
                result.append(words[i])
            }
        }
        return result.joined(separator: " ")
    }

    // MARK: - Contractions

    /// Fix common missing apostrophes from voice input.
    private static let contractionFixes: [(String, String)] = [
        ("dont", "don't"),
        ("doesnt", "doesn't"),
        ("didnt", "didn't"),
        ("cant", "can't"),
        ("wont", "won't"),
        ("shouldnt", "shouldn't"),
        ("wouldnt", "wouldn't"),
        ("couldnt", "couldn't"),
        ("isnt", "isn't"),
        ("arent", "aren't"),
        ("wasnt", "wasn't"),
        ("werent", "weren't"),
        ("havent", "haven't"),
        ("hasnt", "hasn't"),
        ("im", "I'm"),
        ("ive", "I've"),
        ("id", "I'd"),
        ("ill", "I'll"),
        ("its", "it's"),
        ("thats", "that's"),
        ("whats", "what's"),
        ("hows", "how's"),
        ("lets", "let's"),
        ("youre", "you're"),
        ("theyre", "they're"),
        ("weve", "we've")
    ]

    static func fixCommonContractions(_ text: String) -> String {
        var words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        for i in 0..<words.count {
            let lower = words[i].lowercased()
            // Only fix if word doesn't already have an apostrophe
            if !words[i].contains("'"),
               let fix = contractionFixes.first(where: { $0.0 == lower }) {
                words[i] = fix.1
            }
        }
        return words.joined(separator: " ")
    }

    // MARK: - Whitespace

    /// Collapse multiple spaces, tabs, newlines into single space.
    static func normalizeWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Leading Conjunctions

    /// Strip leading "so", "and", "but", "well", "ok so" that voice input often starts with.
    private static let leadingConjunctions: [String] = [
        "ok so", "okay so", "alright so", "so",
        "and", "but", "well", "oh"
    ]

    static func trimLeadingConjunctions(_ text: String) -> String {
        let lower = text.lowercased()
        for conjunction in leadingConjunctions {
            if lower.hasPrefix(conjunction + " ") {
                let stripped = String(text.dropFirst(conjunction.count + 1))
                    .trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty { return stripped }
            }
        }
        return text
    }
}
