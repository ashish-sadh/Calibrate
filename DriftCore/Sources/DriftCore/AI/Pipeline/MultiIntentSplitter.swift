import Foundation

/// Stage 0.5 pre-pass: detect compound multi-intent queries and split them
/// before any LLM call. Runs after normalization + pronoun resolution so it
/// sees clean input, but before the rule engine and classifier.
///
/// v2 extends v1 with:
/// - **Strong separators** (", also" / "; also" / ", then" / "; then"): coarse
///   split first, then refine each segment with the original " and " logic.
///   This lets "log eggs and toast, also log my workout" split cleanly without
///   breaking the compound food name on the food side.
/// - **Workout** as a recognised domain (gym, cardio, pushups, leg day, …).
/// - **Temporal** scheduling intents ("remind me to log dinner at 7pm") — these
///   get a "temporal" domain so a same-domain compound is allowed to split when
///   one segment is temporal; the executor then skips the temporal segment with
///   a transparent "no reminders yet" message rather than logging anything.
///
/// Design constraints:
/// - Pure heuristics, no LLM, no DB.
/// - Only splits when every refined segment has a classifiable domain AND
///   either domains differ OR a temporal segment is present.
/// - Large-model only (AIToolAgent guards the call).
public enum MultiIntentSplitter {

    // MARK: - Sub-Query Handling

    /// How `AIToolAgent.executeMultiIntent` should treat a sub-query.
    /// Decided per-segment by `handling(for:)`.
    public enum SubQueryHandling: Equatable, Sendable {
        case execute
        case skipTemporal(message: String)
    }

    /// Decide how a single sub-query should be handled inside the multi-intent
    /// executor. Pure — safe to unit-test without touching the LLM pipeline.
    /// Temporal segments are not routed through `runInner`; the executor
    /// substitutes the returned message directly.
    public static func handling(for subQuery: String) -> SubQueryHandling {
        if isTemporal(subQuery) {
            return .skipTemporal(message: temporalSkipMessage(for: subQuery))
        }
        return .execute
    }

    /// Fixed user-facing message for a temporal sub-query. Drift has no
    /// scheduling primitive yet, so we acknowledge the request and ask the
    /// user to log it themselves — transparent failure over a silent miss.
    public static func temporalSkipMessage(for subQuery: String) -> String {
        let cleaned = subQuery.trimmingCharacters(in: .whitespaces)
        return "For \"\(cleaned)\": I don't have reminders yet — log it manually when the time comes."
    }

    // MARK: - Domain Detection

    /// Classify a phrase into its primary health tracking domain.
    /// Returns nil when no clear domain signal is present — callers use nil
    /// to prevent splitting (missing domain = same-domain fallback).
    ///
    /// Order matters: temporal wins over everything because "remind me to log
    /// dinner" should never be routed as food; weight and supplement specifics
    /// beat the generic food verbs; workout sits above food so "log my workout"
    /// resolves correctly.
    public static func domain(of phrase: String) -> String? {
        let s = phrase.lowercased()

        // Temporal: explicit scheduling intent. Wins over all domains.
        if isTemporal(phrase) { return "temporal" }

        // Weight: explicit weight vocabulary or number+unit pattern.
        let weightWords = ["weigh", "weight", "scale", "kilos"]
        let hasWeightWord = weightWords.contains(where: { s.contains($0) })
        let hasWeightUnit = s.range(
            of: #"\d+\.?\d*\s*(kg|kgs|lb|lbs|pounds|kilos?)\b"#,
            options: .regularExpression
        ) != nil
        if hasWeightWord || hasWeightUnit { return "weight" }

        // Supplement: known supplement item names. Action verbs alone ("mark",
        // "took") without a named item are intentionally excluded to avoid
        // false positives like "I haven't taken it".
        let supplementItems = [
            "creatine", "vitamin", "omega", "zinc", "magnesium",
            "probiotic", "melatonin", "ashwagandha", "fish oil"
        ]
        if supplementItems.contains(where: { s.contains($0) }) {
            return "supplement"
        }

        // Workout: gym / cardio / lift-style vocabulary. Conservative list to
        // avoid false positives on phrases like "I ran out of milk".
        let workoutWords = [
            "gym", "workout", "work out", "cardio", "yoga", "pilates",
            "treadmill", "elliptical",
            "pushup", "push-up", "pullup", "pull-up",
            "squats", "deadlift", "bench press", "bench-press",
            "leg day", "push day", "pull day", "chest day", "back day", "arm day"
        ]
        if workoutWords.contains(where: { s.contains($0) }) {
            return "workout"
        }
        // "did <body part>" — common spoken-style workout reference.
        let didWorkoutPhrases = ["did legs", "did chest", "did push", "did pull", "did arms", "did back", "did cardio"]
        if didWorkoutPhrases.contains(where: { s.contains($0) }) {
            return "workout"
        }

        // Food: eating/drinking action verbs or explicit log/add/track verbs.
        // Bare food nouns ("rice", "chicken") intentionally produce nil so that
        // "I had chicken and rice" is not split.
        let foodVerbs = ["had ", "ate ", "eaten", "drank ", "drink ", "having "]
        let logVerbs = ["log ", "add ", "track "]
        if foodVerbs.contains(where: { s.contains($0) }) ||
           logVerbs.contains(where: { s.contains($0) }) {
            return "food"
        }

        return nil
    }

    /// True when a phrase is a scheduling intent ("remind me to ...", "remember
    /// to ..."). Conservative — only fires on explicit reminder language so a
    /// sentence that merely mentions a time of day ("I ate at 7pm") is NOT
    /// classified as temporal.
    public static func isTemporal(_ phrase: String) -> Bool {
        let s = phrase.lowercased()
        return s.contains("remind me") ||
               s.contains("reminder") ||
               s.contains("remember to")
    }

    // MARK: - Split

    /// Split a compound multi-intent query into ordered sub-queries.
    /// Returns nil when the message is single-intent or any segment is
    /// unclassifiable (preventing false splits on same-domain multi-item food).
    ///
    /// Two-stage:
    /// 1. Coarse split on STRONG separators (", also" / "; also" / ", then" /
    ///    "; then"). Each coarse segment is then refined by the fine " and "
    ///    splitter so compound food names inside one segment stay attached.
    /// 2. If no strong separators present, fall back to the fine " and "
    ///    splitter directly (v1 behaviour).
    ///
    /// Examples:
    /// - "I had eggs and logged 70kg"                  → ["I had eggs", "logged 70kg"]
    /// - "log eggs and toast, also log my workout"     → ["log eggs and toast", "log my workout"]
    /// - "log breakfast and remind me to log dinner"   → ["log breakfast", "remind me to log dinner"]
    /// - "I had chicken and rice"                      → nil (rice has no domain signal)
    /// - "log breakfast, then log dinner"              → nil (same-domain, no temporal)
    public static func split(_ message: String) -> [String]? {
        let coarseSegments = splitOnStrongSeparators(message)
        if coarseSegments.count >= 2 {
            var refined: [String] = []
            for coarse in coarseSegments {
                if let fine = fineAndSplit(coarse) {
                    refined.append(contentsOf: fine)
                } else {
                    refined.append(coarse.trimmingCharacters(in: .whitespaces))
                }
            }
            return validateSegments(refined)
        }

        return fineAndSplit(message)
    }

    // MARK: - Private

    /// Fine-grained " and " split with domain validation. Returns nil unless
    /// every segment has a domain AND (≥2 distinct domains OR any segment is
    /// temporal). The temporal exception lets "log breakfast and remind me to
    /// log dinner" split even though both segments would otherwise look like
    /// food intents.
    private static func fineAndSplit(_ message: String) -> [String]? {
        guard message.lowercased().contains(" and ") else { return nil }

        let parts = splitOnAnd(message)
        guard parts.count >= 2 else { return nil }

        return validateSegments(parts.map { $0.trimmingCharacters(in: .whitespaces) })
    }

    /// Apply the domain-disjointness / temporal-allowance rules to a candidate
    /// segment list. Shared by both the coarse and fine paths so the split
    /// policy is identical regardless of which separator triggered it.
    private static func validateSegments(_ segments: [String]) -> [String]? {
        guard segments.count >= 2 else { return nil }

        let domains = segments.map { domain(of: $0) }
        guard domains.allSatisfy({ $0 != nil }) else { return nil }

        let unique = Set(domains.compactMap { $0 })
        let anyTemporal = domains.contains(where: { $0 == "temporal" })
        guard unique.count >= 2 || anyTemporal else { return nil }

        return segments
    }

    private static func splitOnAnd(_ message: String) -> [String] {
        var parts: [String] = []
        var remaining = message[...]
        while !remaining.isEmpty {
            if let range = remaining.range(of: " and ", options: .caseInsensitive) {
                parts.append(String(remaining[..<range.lowerBound]))
                remaining = remaining[range.upperBound...]
            } else {
                parts.append(String(remaining))
                break
            }
        }
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Split on strong sequencing separators. Conservative list — only fires
    /// on punctuation+conjunction combinations the user clearly meant as a
    /// sequencing signal, never on bare commas (which appear inside lists).
    private static func splitOnStrongSeparators(_ message: String) -> [String] {
        let pattern = #"(?i)(?:,|;)\s*(?:also|then)\s+"#
        let nsMessage = message as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [message] }
        let matches = regex.matches(in: message, range: NSRange(location: 0, length: nsMessage.length))
        guard !matches.isEmpty else { return [message] }

        var parts: [String] = []
        var cursor = 0
        for match in matches {
            let segmentRange = NSRange(location: cursor, length: match.range.location - cursor)
            let segment = nsMessage.substring(with: segmentRange)
            parts.append(segment)
            cursor = match.range.location + match.range.length
        }
        if cursor < nsMessage.length {
            parts.append(nsMessage.substring(from: cursor))
        }
        return parts
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
