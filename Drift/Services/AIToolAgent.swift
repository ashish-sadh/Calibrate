import Foundation

// MARK: - Agent Output

/// What the agent returns to AIChatView.
struct AgentOutput: Sendable {
    let text: String                  // User-facing message
    let action: ToolAction?           // Optional UI action (open sheet, etc.)
    let toolsCalled: [String]         // For debugging/logging
}

// MARK: - AI Tool Agent

/// Unified tiered pipeline for both SmolLM and Gemma 4:
/// 1. Rules on raw input (instant, both models)
/// 2. LLM normalize → re-run rules (Gemma only — SmolLM too small)
/// 3. Tool-first execution → stream presentation with real data (both)
/// 4. LLM fallback (Gemma: direct streaming, SmolLM: AIChainOfThought)
/// All LLM calls have a 20s timeout.
@MainActor
enum AIToolAgent {

    private static let llmTimeout: UInt64 = 20_000_000_000 // 20 seconds in nanoseconds

    /// Thread-safe state for the streaming token callback.
    private final class StreamState: @unchecked Sendable {
        var buffer = ""
        var isToolCall = false
        var modeDetected = false
    }

    // MARK: - Query Normalizer

    /// Ultra-minimal LLM call to rewrite messy natural language into clean command form.
    /// ~80 tokens prompt, ~2-3s on device. 20s timeout.
    static func normalizeQuery(_ query: String, history: String) async -> String? {
        let (system, user) = ToolRanker.normalizePrompt(query: query, history: history)
        let response = await withTimeout(seconds: 20) {
            await LocalAIService.shared.respondDirect(systemPrompt: system, message: user)
        }
        guard let response else { return nil } // timed out
        let cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
        guard !cleaned.isEmpty,
              cleaned.count < 200,
              cleaned.lowercased() != query.lowercased() else { return nil }
        return cleaned
    }

    // MARK: - Main Entry Point (Tiered)

    static func run(
        message: String,
        screen: AIScreen,
        history: String,
        isLargeModel: Bool,
        onStep: (String) -> Void,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> AgentOutput {

        // ── Phase 1: Try rules on raw input (instant, both models) ──
        if let toolCall = ToolRanker.tryRulePick(query: message, screen: screen) {
            return await executeTool(toolCall)
        }

        // ── Phase 2: LLM normalize → re-run rules (Gemma only) ──
        if isLargeModel {
            onStep(stepMessage(for: message))
            if let rewritten = await normalizeQuery(message, history: history) {
                if let toolCall = ToolRanker.tryRulePick(query: rewritten, screen: screen) {
                    return await executeTool(toolCall)
                }
                if let staticResult = StaticOverrides.match(rewritten.lowercased()) {
                    if case .response(let text) = staticResult {
                        return AgentOutput(text: text, action: nil, toolsCalled: ["static"])
                    }
                    if case .handler(let fn) = staticResult {
                        return AgentOutput(text: fn(), action: nil, toolsCalled: ["static"])
                    }
                }
            }
        }

        // ── Phase 3: Tool-first execution → stream presentation (both models) ──
        onStep(stepMessage(for: message))
        let toolResults = await executeRelevantTools(query: message, screen: screen)

        // If a tool returned a UI action, return it directly
        if let actionResult = toolResults.first(where: { $0.action != nil }) {
            return actionResult
        }

        // If we got data, stream a natural presentation with it (large model)
        // or return raw data directly (small model — LLM presentation unreliable)
        if !toolResults.isEmpty {
            let data = toolResults.map(\.text).joined(separator: "\n")
            if isLargeModel {
                onStep("Preparing answer...")
                return await streamPresentation(
                    query: message, toolData: data, screen: screen, onToken: onToken
                )
            } else {
                return AgentOutput(text: data, action: nil, toolsCalled: toolResults.flatMap(\.toolsCalled))
            }
        }

        // ── Phase 4: LLM fallback ──
        onStep("Thinking...")
        if isLargeModel {
            // Gemma: direct streaming with tool-call detection
            let context = gatherContext(query: message, screen: screen)
            let (systemPrompt, userMessage) = ToolRanker.buildPrompt(
                query: message, screen: screen, context: context, history: history
            )

            let state = StreamState()

            let response = await withTimeout(seconds: 20) {
                await LocalAIService.shared.respondStreamingDirect(
                    systemPrompt: systemPrompt,
                    message: userMessage,
                    onToken: { token in
                        state.buffer += token
                        if !state.modeDetected {
                            let trimmed = state.buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            state.modeDetected = true
                            if trimmed.hasPrefix("{") { state.isToolCall = true; return }
                        }
                        if !state.isToolCall { onToken(token) }
                    }
                )
            }

            guard let response else {
                return AgentOutput(text: fallbackText(for: screen), action: nil, toolsCalled: ["timeout"])
            }

            if state.isToolCall, let toolCall = parseToolCallJSON(response) {
                return await executeTool(toolCall)
            }
            return handleTextResponse(response, screen: screen)
        } else {
            // SmolLM: context-enriched streaming via AIChainOfThought
            let response = await AIChainOfThought.execute(
                query: message, screen: screen, history: history,
                onStep: onStep, onToken: onToken
            )

            // Check for tool call in response
            if let toolCall = parseToolCallJSON(response) {
                return await executeTool(toolCall)
            }
            return handleTextResponse(response, screen: screen)
        }
    }

    // MARK: - Tool-First Execution

    /// Execute top relevant info tools in parallel before streaming. Actions skip this.
    private static func executeRelevantTools(query: String, screen: AIScreen) async -> [AgentOutput] {
        let tools = ToolRanker.rank(query: query, screen: screen, topN: 2)
            .filter { isInfoTool($0.name) }
        guard !tools.isEmpty else { return [] }

        // Extract params on MainActor before parallel execution
        let calls: [ToolCall] = tools.map { tool in
            let params = ToolRanker.extractParamsForTool(tool, from: query)
            return ToolCall(tool: tool.name, params: ToolCallParams(values: params))
        }

        // Execute tools in parallel
        return await withTaskGroup(of: AgentOutput?.self) { group in
            for call in calls {
                group.addTask {
                    let result = await ToolRegistry.shared.execute(call)
                    switch result {
                    case .text(let text):
                        return AgentOutput(text: text, action: nil, toolsCalled: [call.tool])
                    case .action(let action):
                        return AgentOutput(text: "", action: action, toolsCalled: [call.tool])
                    case .error:
                        return nil
                    }
                }
            }
            var results: [AgentOutput] = []
            for await output in group {
                if let output { results.append(output) }
            }
            return results
        }
    }

    private static let infoTools: Set<String> = [
        "food_info", "weight_info", "exercise_info", "sleep_recovery",
        "supplements", "glucose", "biomarkers", "body_comp", "explain_calories"
    ]

    private static func isInfoTool(_ name: String) -> Bool {
        infoTools.contains(name)
    }

    // MARK: - Streaming Presentation

    /// Stream a natural response with pre-fetched tool data injected.
    /// ~320 token prompt. First token in ~2s. Data is real, not hallucinated.
    private static func streamPresentation(
        query: String, toolData: String, screen: AIScreen,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> AgentOutput {
        let system = """
        You are a health assistant. Answer using ONLY the data below.
        Be concise (1-3 sentences). Use actual numbers. No health advice.
        """
        let user = "Data:\n\(toolData)\n\nUser: \(query)"

        let response = await withTimeout(seconds: 20) {
            await LocalAIService.shared.respondStreamingDirect(
                systemPrompt: system, message: user, onToken: onToken
            )
        }

        if let response {
            let cleaned = AIResponseCleaner.clean(response)
            if !cleaned.isEmpty && !AIResponseCleaner.isLowQuality(cleaned) {
                return AgentOutput(text: cleaned, action: nil, toolsCalled: ["presentation"])
            }
        }
        // Fallback: return raw tool data if LLM presentation fails
        return AgentOutput(text: toolData, action: nil, toolsCalled: ["presentation"])
    }

    // MARK: - Tool Execution

    private static func executeTool(_ toolCall: ToolCall) async -> AgentOutput {
        let result = await ToolRegistry.shared.execute(toolCall)
        switch result {
        case .text(let text):
            return AgentOutput(text: text, action: nil, toolsCalled: [toolCall.tool])
        case .action(let action):
            return AgentOutput(text: "", action: action, toolsCalled: [toolCall.tool])
        case .error(let msg):
            return AgentOutput(text: msg, action: nil, toolsCalled: [toolCall.tool])
        }
    }

    // MARK: - Text Response Handling

    private static func handleTextResponse(_ response: String, screen: AIScreen) -> AgentOutput {
        let cleaned = AIResponseCleaner.clean(response)
        if cleaned.isEmpty || AIResponseCleaner.isLowQuality(cleaned) {
            return AgentOutput(text: fallbackText(for: screen), action: nil, toolsCalled: [])
        }
        if AIResponseCleaner.hasHallucinatedNumbers(cleaned, context: AIContextBuilder.baseContext()) {
            return AgentOutput(text: fallbackText(for: screen), action: nil, toolsCalled: [])
        }
        return AgentOutput(text: cleaned, action: nil, toolsCalled: [])
    }

    // MARK: - Context Gathering

    private static func gatherContext(query: String, screen: AIScreen) -> String {
        guard let steps = AIChainOfThought.plan(query: query, screen: screen) else {
            return AIContextBuilder.buildContext(screen: screen)
        }
        var contextParts: [String] = [
            "Screen: \(screen.rawValue)",
            AIContextBuilder.baseContext()
        ]
        for step in steps {
            let data = step.fetch()
            if !data.isEmpty { contextParts.append(data) }
        }
        let raw = contextParts.joined(separator: "\n")
        return AIContextBuilder.truncateToFit(raw, maxTokens: 500)
    }

    // MARK: - Timeout Helper

    /// Run an async operation with a timeout. Returns nil if timed out.
    private static func withTimeout<T: Sendable>(seconds: Int, operation: @escaping @Sendable () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                return nil
            }
            // Return whichever finishes first
            if let result = await group.next() {
                group.cancelAll()
                return result
            }
            return nil
        }
    }

    // MARK: - Step Messages

    private static func stepMessage(for query: String) -> String {
        let lower = query.lowercased()
        if ["ate", "had", "log", "add", "drank", "eaten"].contains(where: { lower.contains($0) }) { return "Logging food..." }
        if ["start", "begin", "workout", "chest", "legs"].contains(where: { lower.contains($0) }) { return "Setting up workout..." }
        if ["took", "supplement", "vitamin"].contains(where: { lower.contains($0) }) { return "Updating supplements..." }
        if ["how", "what", "show", "calories", "weight", "sleep"].contains(where: { lower.contains($0) }) { return "Checking your data..." }
        return "Looking that up..."
    }

    // MARK: - Fallback Text

    private static func fallbackText(for screen: AIScreen) -> String {
        switch screen {
        case .food: return "I can help you log food, check calories, or suggest meals. What would you like?"
        case .weight: return "I can log your weight or tell you about your trend. What would you like?"
        case .exercise: return "I can suggest a workout or check your progress. What would you like?"
        default: return "I can help with food, weight, workouts, or health data. What would you like to know?"
        }
    }
}
