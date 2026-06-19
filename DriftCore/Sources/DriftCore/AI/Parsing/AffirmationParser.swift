import Foundation

/// Deterministic yes / no / unclear parser for spoken (or typed) confirmations.
///
/// The coach's talk-mode action confirm ("…add it?") must resolve a one-word
/// reply the same way whether it arrives by voice ("yeah") or a tapped card
/// (Confirm/Cancel maps to "yes"/"no"). Pure + Tier-0 testable; no LLM, no UI —
/// the single source of truth both paths call. #coach-talk-mode
public enum AffirmationParser {

    public enum Verdict: Equatable, Sendable { case yes, no, unclear }

    /// Affirmatives. Multi-word phrases ("go ahead") are matched as substrings;
    /// single tokens are matched whole-word so "knot" can't trip "no".
    private static let yesWords: Set<String> = [
        "yes", "yep", "yeah", "yup", "ya", "sure", "ok", "okay",
        "confirm", "confirmed", "correct", "right", "perfect", "good", "great",
        "please", "definitely", "absolutely", "affirmative", "y",
    ]
    private static let yesPhrases: [String] = [
        "go ahead", "do it", "add it", "log it", "save it", "go for it",
        "sounds good", "that's right", "thats right", "yes please", "do that",
    ]

    private static let noWords: Set<String> = [
        "no", "nope", "nah", "naw", "cancel", "stop", "wrong", "don't", "dont",
        "negative", "n",
    ]
    private static let noPhrases: [String] = [
        "never mind", "nevermind", "scratch that", "not now", "no thanks",
        "no thank you", "don't", "forget it", "hold on", "wait no",
    ]

    /// Classify a confirmation reply. Negatives win ties (a "no thanks" that also
    /// contains "thanks" must not read as agreement); safety-biased toward NOT
    /// committing a write on ambiguity.
    public static func verdict(_ raw: String) -> Verdict {
        let s = normalize(raw)
        guard !s.isEmpty else { return .unclear }

        // Phrase matches first — most specific, and allowed at any length.
        if noPhrases.contains(where: { s.contains($0) }) { return .no }
        if yesPhrases.contains(where: { s.contains($0) }) { return .yes }

        // A bare confirmation is TERSE ("yes", "no", "yeah"). A longer sentence
        // that merely contains "no"/"yes" ("no, I had chicken instead", "yes but
        // make it two servings") is a correction or a new request — defer it to
        // .unclear so the caller routes it as a fresh turn instead of cancelling.
        let tokens = s.split(separator: " ").map(String.init)
        guard tokens.count <= 4 else { return .unclear }

        let set = Set(tokens)
        if !set.isDisjoint(with: noWords) { return .no }   // negative bias on ambiguity
        if !set.isDisjoint(with: yesWords) { return .yes }
        return .unclear
    }

    /// Lowercase, strip punctuation to spaces, collapse whitespace.
    private static func normalize(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let cleaned = lowered.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) || scalar == " " ? Character(scalar) : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }
}
