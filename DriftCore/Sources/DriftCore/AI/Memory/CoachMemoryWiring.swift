import Foundation

/// Shared coach-memory instance. `LocalCoachMemory` (on-device) is the default;
/// kept behind a holder so a different backend could be swapped in later without
/// touching the classify path. #coach-agent-loop.
public enum CoachMemoryStore {
    public static let shared: any CoachMemory = LocalCoachMemory()
}

/// Pulls durable facts worth remembering out of a user message — goals,
/// preferences, and explicit "remember …" statements. Heuristic + pure (Tier-0
/// tested); deliberately conservative so the coach stores signal, not chatter.
/// Raw data (weights, glucose) is NOT captured here — that lives in GRDB; this
/// is the "what matters about you" layer.
public enum CoachMemoryExtractor {

    public static func extract(from userMessage: String) -> [MemoryItem] {
        let text = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 4 else { return [] }
        let lower = text.lowercased()
        var items: [MemoryItem] = []

        // Explicit "remember …" — the strongest signal.
        if lower.hasPrefix("remember ") || lower.contains("remember that ") {
            items.append(MemoryItem(text: text, kind: .fact))
            return items   // explicit beats heuristics; one item
        }

        // Goals.
        let goalSignals = ["my goal", "i want to", "i'm trying to", "im trying to",
                           "trying to", "aiming to", "i'd like to", "i plan to", "want to hit"]
        if goalSignals.contains(where: { lower.contains($0) }) {
            items.append(MemoryItem(text: text, kind: .goal))
        }

        // Preferences / constraints.
        let prefSignals = ["i'm vegetarian", "i am vegetarian", "i'm vegan", "i am vegan",
                           "i prefer", "i don't eat", "i dont eat", "i can't eat", "i cant eat",
                           "i avoid", "i'm allergic", "i am allergic", "no gym", "i don't have a gym",
                           "i'm lactose", "i am lactose"]
        if prefSignals.contains(where: { lower.contains($0) }) {
            items.append(MemoryItem(text: text, kind: .preference))
        }

        return items
    }
}
