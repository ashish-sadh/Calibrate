import Foundation

/// Cross-domain pronoun resolution. Rewrites a query-style message that
/// refers to the last-touched entry ("how much protein in that") into an
/// explicit form ("how much protein in 150g chicken") so the downstream
/// intent classifier sees a concrete subject. Deterministic, no LLM. #241.
///
/// Only rewrites when:
///   1. The message looks like a **query** (not an action) — has "?", or
///      starts with a question word, or mentions a macro/metric.
///   2. The message contains a **bare pronoun** (`that`, `it`, `this`, `this
///      one`) that isn't already bound to an explicit subject.
///   3. A fresh `LastEntryContext` is available (within TTL).
///
/// Returns `nil` when no rewrite is needed or safe — callers fall through
/// to the existing pipeline. Never rewrites action verbs ("log that",
/// "delete it") — those go through `resolvePronouns()` in the food path.
enum PronounResolver {

    /// Pronouns that indicate a back-reference to the last entry. Ordered
    /// longest-first so "this one" beats "this".
    static let pronouns: [String] = ["this one", "that one", "that", "this", "it"]

    /// Action verbs that should NOT be rewritten here — food logging already
    /// has its own pronoun path in `AIChatView+MessageHandling.resolvePronouns`.
    /// Query verbs use this resolver instead.
    private static let actionPrefixes: [String] = [
        "log ", "add ", "track ", "remove ", "delete ", "edit ", "undo ",
        "update ", "change "
    ]

    /// Question cues that anchor an *information query* rather than an
    /// action — only such messages are candidates for rewriting.
    private static let queryCues: [String] = [
        "how much", "how many", "how's", "how is", "how was", "how did",
        "what's", "what is", "what was", "what are", "is it", "is that",
        "was that", "am i", "protein", "calories", "carbs", "fat", "fiber",
        "macros", "nutrition", "goal", "under", "over", "trend", "progress",
        "pr", "record"
    ]

    /// Rewrite a pronoun-bearing query in-place when a fresh `LastEntryContext`
    /// exists. Returns `nil` otherwise.
    static func resolve(message: String, context: ConversationState.LastEntryContext?) -> String? {
        guard let context else { return nil }
        let lower = message.lowercased()

        // Skip rewrite on action verbs — the food path has its own resolver
        // and we don't want to double-bind on "log that".
        if actionPrefixes.contains(where: { lower.hasPrefix($0) }) { return nil }

        // Must look like a query or a short reference question.
        guard looksLikeQuery(lower, message: message) else { return nil }

        // Must contain a pronoun with whitespace/punctuation on both sides.
        guard let replaced = replaceFirstPronoun(in: message, with: context.summary) else {
            return nil
        }
        return replaced
    }

    /// Is this message a query (vs. an action or a greeting)?
    private static func looksLikeQuery(_ lower: String, message: String) -> Bool {
        if message.contains("?") { return true }
        for cue in queryCues where lower.contains(cue) { return true }
        return false
    }

    /// Replace the first occurrence of a bare pronoun with the explicit
    /// subject. Uses regex-style word boundaries so we don't mangle words
    /// containing the pronoun (e.g., "that's", "items").
    private static func replaceFirstPronoun(in message: String, with subject: String) -> String? {
        let lower = message.lowercased()
        for pronoun in pronouns {
            guard let range = matchWholeWord(pronoun, in: lower) else { continue }
            let asOriginal = Range(range, in: message)!
            var result = message
            result.replaceSubrange(asOriginal, with: subject)
            return result
        }
        return nil
    }

    /// Find the first whole-word occurrence of `needle` in `haystack`.
    /// "Whole word" = preceded and followed by whitespace, punctuation, or
    /// string boundary. Returns an NSRange-compatible Range<String.Index>.
    private static func matchWholeWord(_ needle: String, in haystack: String) -> NSRange? {
        let pattern = "(?<![a-z0-9])\(NSRegularExpression.escapedPattern(for: needle))(?![a-z0-9])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(haystack.startIndex..., in: haystack)
        guard let match = regex.firstMatch(in: haystack, range: range) else { return nil }
        return match.range
    }
}
