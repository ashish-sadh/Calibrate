import Foundation

/// iOS-side IntentClassifier methods that touch ConversationState / LocalAIService.
/// Pure parsing + composition lives in DriftCore (`IntentClassifier` enum).
@MainActor
extension IntentClassifier {

    /// MainActor variant used by the live pipeline. Prepends the recent-entries
    /// block when the message looks like a delete/edit turn AND the window has rows.
    /// Injects the user profile preamble when one exists.
    /// `literalHint` is used by the #240 auto-retry path to nudge the extractor.
    static func buildContextualUserMessage(
        message: String, history: String, literalHint: String? = nil
    ) -> String {
        let recentBlock = needsRecentEntries(message)
            ? ConversationState.shared.recentEntriesContextBlock()
            : nil
        let profile = AIProfileService.buildSummary()
        return composeUserMessage(
            message: message, history: history,
            recentBlock: recentBlock, literalHint: literalHint, profileContext: profile
        )
    }

    /// Classify user message into intent + tool call via LLM.
    /// Returns nil only on timeout. Text responses are returned as `.text`.
    /// Picks routerPrompt / intelligencePrompt / remotePrompt based on the
    /// active backend — small local gets tight, large local gets rich,
    /// remote BYOK gets rich + brevity-clamping extras.
    static func classifyFull(
        message: String, history: String, literalHint: String? = nil
    ) async -> ClassifyResult? {
        let msg = buildContextualUserMessage(
            message: message, history: history, literalHint: literalHint
        )
        let backend = await LocalAIService.shared.activeBackendType
        let isLarge = await LocalAIService.shared.isLargeModel
        let prompt = backend == .remote
            ? activeSystemPrompt(backend: .remote)
            : activeSystemPrompt(isLargeModel: isLarge)
        // Native function-calling for the remote coach: ship the tool schemas so
        // Nebius/Qwen3 returns structured tool_calls (the SSE parser normalizes
        // them to Drift's {"tool":...} shape, so mapResponse is unchanged). Added
        // ADDITIVELY — the prose tool list stays for now as a fallback; it is
        // stripped only once the Tier-3 routing eval confirms no regression.
        // Local backends stay prose-routed (toolsJSON nil). #coach-agent-loop.
        let toolsJSON = backend == .remote ? ToolRegistry.shared.toolsJSONString() : nil
        let response = await withTimeout(seconds: 10) {
            await LocalAIService.shared.respondDirect(
                systemPrompt: prompt,
                message: msg,
                toolsJSON: toolsJSON
            )
        }
        return mapResponse(response)
    }

    /// Legacy: returns nil for text responses (backward compat)
    static func classify(message: String, history: String) async -> ClassifiedIntent? {
        guard let result = await classifyFull(message: message, history: history) else { return nil }
        if case .toolCall(let intent) = result { return intent }
        return nil
    }
}
