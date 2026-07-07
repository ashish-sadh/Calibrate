import Foundation

/// Builds the user-voice Coach prompt seeded from a Today coaching-nudge card
/// (#928). The nudge's `title`/`detail` already carry the user's real data
/// ("Supplements missed", "Creatine, Electrolytes — not taken in 3+ days"),
/// so passing them through verbatim means the Coach's first answer references
/// the actual state instead of opening cold.
///
/// Pure string logic — lives in DriftCore so the seed contract is Tier-0
/// testable; the iOS side only decides *when* to post it.
public enum NudgeCoachSeed {
    /// User-voice prompt for the Coach input, e.g.
    /// "Supplements missed — Creatine, Electrolytes — not taken in 3+ days. What should I do?"
    public static func prompt(title: String, detail: String) -> String {
        let headline = detail.isEmpty ? title : "\(title) — \(detail)"
        return "\(headline). What should I do?"
    }
}
