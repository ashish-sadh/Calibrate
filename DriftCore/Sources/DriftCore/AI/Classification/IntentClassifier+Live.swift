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
        var msg = buildContextualUserMessage(
            message: message, history: history, literalHint: literalHint
        )
        // Cross-session memory: recall durable user facts/goals and inject them;
        // extract + persist any new ones the message states (fire-and-forget).
        // On-device (LocalCoachMemory) — cheap, private, no network. #coach-agent-loop
        if let memoryContext = await coachMemoryContext(for: message) {
            msg = memoryContext + "\n\n" + msg
        }
        rememberDurableFacts(from: message)
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

    /// Recall durable facts relevant to this message, formatted for the prompt.
    private static func coachMemoryContext(for message: String) async -> String? {
        let hits = await CoachMemoryStore.shared.recall(query: message, limit: 3)
        guard !hits.isEmpty else { return nil }
        let lines = hits.map { "- \($0.text)" }.joined(separator: "\n")
        return "What you remember about the user:\n\(lines)"
    }

    /// Extract goals/preferences the message states and persist them off the
    /// turn's critical path (fire-and-forget).
    private static func rememberDurableFacts(from message: String) {
        let items = CoachMemoryExtractor.extract(from: message)
        guard !items.isEmpty else { return }
        Task { for item in items { await CoachMemoryStore.shared.remember(item) } }
    }

    /// Legacy: returns nil for text responses (backward compat)
    static func classify(message: String, history: String) async -> ClassifiedIntent? {
        guard let result = await classifyFull(message: message, history: history) else { return nil }
        if case .toolCall(let intent) = result { return intent }
        return nil
    }
}
