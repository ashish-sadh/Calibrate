import Foundation

/// Recognizes "log my usual lunch" style requests so the coach can recall the
/// user's habitual meal, narrate it, and open the editable logging sheet. Pure +
/// deterministic (Tier-0) — no LLM — so the common phrasings are reliable and
/// fast; the LLM still handles everything else. #usual-meal
public enum UsualMealRecognizer {

    /// Returns the meal slot to recall when `text` is a "usual meal" LOG request,
    /// else nil. An explicit slot word wins; a bare "the usual" / "my usual"
    /// infers the slot from the time of day. Info questions ("what's my usual
    /// lunch?") are deliberately NOT matched.
    public static func match(_ text: String, now: Date = Date()) -> MealType? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.contains("usual") || lower.contains("regular") else { return nil }

        // Don't hijack info queries — only logging intents.
        if lower.contains("?") || lower.hasPrefix("what") || lower.hasPrefix("which")
            || lower.hasPrefix("when") || lower.hasPrefix("how") { return nil }

        let logCues = ["log", "add", "track", "had", "have", "ate", "eat",
                       "get me", "give me", "do my", "same"]
        let startsUsual = lower.hasPrefix("usual") || lower.hasPrefix("my usual")
            || lower.hasPrefix("the usual") || lower.hasPrefix("my regular")
        guard startsUsual || logCues.contains(where: { lower.contains($0) }) else { return nil }

        if lower.contains("breakfast") { return .breakfast }
        if lower.contains("lunch") { return .lunch }
        if lower.contains("dinner") { return .dinner }
        if lower.contains("snack") { return .snack }

        // Bare "log my usual" / "the usual" / "usual meal" — infer from the hour.
        // Guard on brevity so "log my usual protein shake" (a specific food, not a
        // whole-meal recall) falls through to normal logging.
        let wordCount = lower.split(separator: " ").count
        if lower.contains("usual meal") || lower.contains("regular meal") || wordCount <= 4 {
            return MealType.fromHour(Calendar.current.component(.hour, from: now))
        }
        return nil
    }
}
