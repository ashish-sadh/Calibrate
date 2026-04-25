import Foundation

/// Token budget management for LLM prompts.
/// Pure helpers — no platform deps.
public enum PromptUtils {

    /// Rough token estimate (1 token per 4 chars for English text).
    public static func estimateTokens(_ text: String) -> Int {
        text.utf8.count / 4
    }

    /// Truncate context to fit within budget, preserving complete lines.
    public static func truncateToFit(_ context: String, maxTokens: Int = 800) -> String {
        guard estimateTokens(context) > maxTokens else { return context }
        let targetChars = maxTokens * 4
        let truncated = String(context.prefix(targetChars))
        if let lastNewline = truncated.lastIndex(of: "\n") {
            return String(truncated[...lastNewline])
        }
        return truncated
    }
}
