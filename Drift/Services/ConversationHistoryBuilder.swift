import Foundation

/// Serializes recent chat turns into a token-budgeted "Q: … / A: …" string
/// that AIToolAgent injects into Stage 2 (IntentClassifier), Stage 3
/// (presentation), and Stage 5 (ToolRanker.buildPrompt).
///
/// Centralizing this means the budget is enforced once and each consumer
/// truncates a shared, deterministic string instead of duplicating logic.
enum ConversationHistoryBuilder {

    /// Approximate chars-per-token ratio for Gemma/SmolLM tokenizers.
    static let charsPerToken = 4

    /// Per-message cap — keeps a single verbose assistant answer from
    /// consuming the whole budget. 60 tokens ≈ 240 chars.
    static let perMessageTokens = 60

    /// How many trailing turns to consider. 3 user + 3 assistant pairs is
    /// enough for "same for dinner" / "what about last week" follow-ups.
    static let maxTurnWindow = 6

    /// Build a Q/A formatted history string within `maxTokens`.
    /// Walks newest → oldest and drops older turns first when the budget
    /// runs out. Returns "" when the feature flag is off or no turns fit.
    @MainActor
    static func build(
        messages: [AIChatViewModel.ChatMessage],
        maxTokens: Int = 400
    ) -> String {
        guard Preferences.conversationHistoryEnabled, !messages.isEmpty else { return "" }

        let budgetChars = maxTokens * charsPerToken
        let perMsgChars = perMessageTokens * charsPerToken
        let window = messages.suffix(maxTurnWindow)

        var lines: [String] = []
        var used = 0
        for msg in window.reversed() {
            let prefix = msg.role == .user ? "Q" : "A"
            let truncated = String(msg.text.prefix(perMsgChars))
            let line = "\(prefix): \(truncated)"
            // +1 accounts for the joining newline between lines.
            if used + line.count + (lines.isEmpty ? 0 : 1) > budgetChars { break }
            lines.insert(line, at: 0)
            used += line.count + (lines.count > 1 ? 1 : 0)
        }
        return lines.joined(separator: "\n")
    }
}
