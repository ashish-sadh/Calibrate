import Foundation

// MARK: - Agent Output

/// What the agent returns to AIChatView.
struct AgentOutput: Sendable {
    let text: String                  // User-facing message
    let action: ToolAction?           // Optional UI action (open sheet, etc.)
    let toolsCalled: [String]         // For debugging/logging
}

// MARK: - AI Tool Agent

/// Dual pipeline for SmolLM and Gemma 4:
///
/// **Gemma 4 (multi-stage pipeline, design doc #65):**
/// Stage 0: Input normalization (instant) → Stage 1: Thin rules (instant) →
/// Stage 2: Intent classification (LLM) → Stage 3: Domain extraction (stub) →
/// Stage 3b: Swift validation (stub) → Stage 4-5: Confirm + Execute
/// Fallback: tool-first execution → LLM streaming
///
/// **SmolLM (legacy pipeline, unchanged):**
/// Phase 1: Rules → Phase 3: Tool-first → Phase 4: AIChainOfThought
///
/// All LLM calls have a 20s timeout.
///
/// Token budget (2048 context, 1776 max prompt, 256 max generation):
///   Stage 2: ~538 tokens (IntentClassifier 463 sys + 75 user)
///   Presentation: ~800 tokens (100 sys + 600 data + 100 history/query)
///   Fallback: ~875 tokens (buildPrompt 200 sys + 500 context + 150 history + 25 query)
@MainActor
enum AIToolAgent {

    private static let llmTimeout: UInt64 = 20_000_000_000 // 20 seconds in nanoseconds

    /// Thread-safe state for the streaming token callback.
    private final class StreamState: @unchecked Sendable {
        var buffer = ""
        var isToolCall = false
        var modeDetected = false
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

        let pipelineStart = CFAbsoluteTimeGetCurrent()

        // ── Stage 0: Input normalization (instant, no LLM) ──
        let normalized = InputNormalizer.normalize(message)

        // Route by model capability
        if isLargeModel {
            return await runGemmaPipeline(
                normalized: normalized,
                originalMessage: message,
                screen: screen,
                history: history,
                pipelineStart: pipelineStart,
                onStep: onStep,
                onToken: onToken
            )
        }

        // ── SmolLM path (unchanged legacy pipeline) ──

        // Phase 1: Rules on raw input (instant)
        if let toolCall = ToolRanker.tryRulePick(query: normalized, screen: screen) {
            logTiming("Phase 1 (rules)", start: pipelineStart)
            return await executeTool(toolCall)
        }

        // Phase 3: Tool-first execution
        onStep(stepMessage(for: normalized))
        let toolResults = await executeRelevantTools(query: normalized, screen: screen)

        if let actionResult = toolResults.first(where: { $0.action != nil }) {
            return actionResult
        }

        if !toolResults.isEmpty {
            let data = toolResults.map(\.text).joined(separator: "\n")
            let prefixed = addInsightPrefix(to: data)
            return AgentOutput(text: prefixed, action: nil, toolsCalled: toolResults.flatMap(\.toolsCalled))
        }

        // Phase 4: LLM fallback (AIChainOfThought)
        onStep("Thinking...")
        let response = await AIChainOfThought.execute(
            query: normalized, screen: screen, history: history,
            onStep: onStep, onToken: onToken
        )

        if let toolCall = parseToolCallJSON(response) {
            return await executeTool(toolCall)
        }
        return handleTextResponse(response, screen: screen)
    }

    // MARK: - Gemma Multi-Stage Pipeline (#129)

    /// Multi-stage pipeline for Gemma 4 per design doc #65:
    /// Stage 1: Thin static rules → Stage 2: Intent classification (LLM) →
    /// Stage 3: Domain extraction (stub) → Stage 3b: Validation (stub) →
    /// Stage 4-5: Confirm + Execute
    private static func runGemmaPipeline(
        normalized: String,
        originalMessage: String,
        screen: AIScreen,
        history: String,
        pipelineStart: CFAbsoluteTime,
        onStep: (String) -> Void,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> AgentOutput {

        // ── Stage 1: Thin static rules (instant) ──
        // Currently: ToolRanker.tryRulePick. Future (#93): trimmed StaticOverrides.
        if let toolCall = ToolRanker.tryRulePick(query: normalized, screen: screen) {
            logTiming("Stage 1 (rules)", start: pipelineStart)
            return await executeTool(toolCall)
        }

        // ── Stage 2: Intent classification (LLM, ~2s) ──
        onStep(stepMessage(for: originalMessage))
        let classifyStart = CFAbsoluteTimeGetCurrent()
        if let result = await IntentClassifier.classifyFull(message: normalized, history: history) {
            logTiming("Stage 2 (classify)", start: classifyStart)
            switch result {
            case .toolCall(let intent):
                let toolName = intent.tool.replacingOccurrences(of: "()", with: "")

                // ── Stage 3: Domain extraction (stub) ──
                // Future (#95): per-domain extraction prompts replace classifier's combined result.
                let extractedCall = extractDomain(intent: intent, toolName: toolName, message: normalized)

                // ── Stage 3b: Swift validation (stub) ──
                // Future (#130): parseFoodIntent/regex as validation fallback + sanity checks.
                let validatedCall = validateExtraction(extractedCall, message: normalized)

                // ── Stage 4-5: Confirm + Execute ──
                onStep(toolStepMessage(for: toolName))
                if isInfoTool(toolName) {
                    let toolResult = await ToolRegistry.shared.execute(validatedCall)
                    if case .text(let data) = toolResult, !data.isEmpty {
                        onStep("Preparing answer...")
                        return await streamPresentation(
                            query: originalMessage, toolData: data, screen: screen,
                            history: history, onToken: onToken
                        )
                    }
                } else {
                    return await executeTool(validatedCall)
                }

            case .text(let response):
                return AgentOutput(text: response, action: nil, toolsCalled: ["classifier"])
            }
        }

        // ── Fallback: Tool-first execution ──
        onStep(stepMessage(for: normalized))
        let toolResults = await executeRelevantTools(query: normalized, screen: screen)

        if let actionResult = toolResults.first(where: { $0.action != nil }) {
            return actionResult
        }

        if !toolResults.isEmpty {
            let data = toolResults.map(\.text).joined(separator: "\n")
            onStep("Preparing answer...")
            return await streamPresentation(
                query: normalized, toolData: data, screen: screen,
                history: history, onToken: onToken
            )
        }

        // ── Fallback: LLM streaming with tool-call detection ──
        onStep("Thinking...")
        let context = gatherContext(query: normalized, screen: screen)
        let (systemPrompt, userMessage) = ToolRanker.buildPrompt(
            query: normalized, screen: screen, context: context, history: history
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
    }

    // MARK: - Stage 3: Domain Extraction (stub for #95)

    /// Uses IntentClassifier's combined result. Future: per-domain extraction prompts.
    private static func extractDomain(
        intent: IntentClassifier.ClassifiedIntent,
        toolName: String,
        message: String
    ) -> ToolCall {
        ToolCall(tool: toolName, params: ToolCallParams(values: intent.params))
    }

    // MARK: - Stage 3b: Swift Validation (stub for #130)

    /// Passes through unchanged. Future: parseFoodIntent/regex sanity checks.
    private static func validateExtraction(_ call: ToolCall, message: String) -> ToolCall {
        call
    }

    // MARK: - Tool-First Execution

    /// Execute top relevant info tools in parallel before streaming. Actions skip this.
    static func executeRelevantTools(query: String, screen: AIScreen) async -> [AgentOutput] {
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

    static func isInfoTool(_ name: String) -> Bool {
        infoTools.contains(name)
    }

    // MARK: - Streaming Presentation

    /// Stream a natural response with pre-fetched tool data injected.
    /// ~320 token prompt. First token in ~2s. Data is real, not hallucinated.
    private static func streamPresentation(
        query: String, toolData: String, screen: AIScreen, history: String = "",
        onToken: @escaping @Sendable (String) -> Void
    ) async -> AgentOutput {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeContext = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        // Context-aware tone based on time and progress
        let toneHint: String
        if hour >= 20 {
            toneHint = "It's evening — be summary-oriented and encouraging about tomorrow."
        } else if hour < 10 {
            toneHint = "It's early — be motivating and forward-looking."
        } else {
            toneHint = "Keep it practical and action-oriented."
        }
        let system = """
        You are a friendly health tracker assistant. It's \(timeContext). \(toneHint)
        Answer the user's question using ONLY the data below. Lead with your main observation, then give the numbers.
        Be warm and brief (2-3 sentences). Use the actual numbers. No medical advice. No repeating the question.
        Example: "You're doing well today — 1200 of 2000 cal with solid protein at 85g. A chicken dinner would close the gap nicely."
        """
        let historyPrefix = history.isEmpty ? "" : "Recent chat:\n\(String(history.prefix(300)))\n\n"
        let truncatedData = AIContextBuilder.truncateToFit(toolData, maxTokens: 600)
        let user = "\(historyPrefix)Data:\n\(truncatedData)\n\nQuestion: \(query)"

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

    // MARK: - SmolLM Insight Prefix

    /// Add a brief conversational prefix to raw tool data for SmolLM (no LLM presentation available).
    static func addInsightPrefix(to data: String) -> String {
        let lower = data.lowercased()
        // Empty/no-data states: don't prefix
        if lower.contains("no food logged") || lower.contains("nothing logged") || lower.contains("no data") || lower.contains("no weight") {
            return data
        }
        // Negative states
        if lower.contains("over target") || (lower.contains("over") && lower.contains("cal")) {
            return "Heads up — \(data)"
        }
        if lower.contains("low recovery") || lower.contains("poor sleep") {
            return "Take it easy — \(data)"
        }
        // Positive states
        if lower.contains("on track") || lower.contains("target reached") || lower.contains("well recovered") {
            return "Nice work! \(data)"
        }
        if lower.contains("remaining") || lower.contains("left") {
            return "Looking good — \(data)"
        }
        // Exercise/workout
        if lower.contains("workout") || lower.contains("streak") || lower.contains("exercise") {
            return "Here's your activity — \(data)"
        }
        // Weight
        if lower.contains("trend") || lower.contains("losing") || lower.contains("gaining") {
            return "Here's the trend — \(data)"
        }
        // Default: add a light prefix
        return "Here's what I found — \(data)"
    }

    // MARK: - Tool Execution

    static func executeTool(_ toolCall: ToolCall) async -> AgentOutput {
        let result = await ToolRegistry.shared.execute(toolCall)
        switch result {
        case .text(let text):
            return AgentOutput(text: text, action: nil, toolsCalled: [toolCall.tool])
        case .action(let action):
            return AgentOutput(text: "", action: action, toolsCalled: [toolCall.tool])
        case .error(let msg):
            // User-friendly error message instead of raw error
            let friendly = "I couldn't quite do that — \(msg.lowercased()). Try rephrasing or say \"help\" to see what I can do."
            return AgentOutput(text: friendly, action: nil, toolsCalled: [toolCall.tool])
        }
    }

    // MARK: - Pipeline Timing

    private static func logTiming(_ label: String, start: CFAbsoluteTime) {
        let ms = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        Log.app.info("⏱ AIToolAgent \(label): \(ms)ms")
    }

    // MARK: - Text Response Handling

    static func handleTextResponse(_ response: String, screen: AIScreen) -> AgentOutput {
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

    static func gatherContext(query: String, screen: AIScreen) -> String {
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
    static func withTimeout<T: Sendable>(seconds: Int, operation: @escaping @Sendable () async -> T) async -> T? {
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

    static func stepMessage(for query: String) -> String {
        let lower = query.lowercased()
        if ["ate", "had", "log", "add", "drank", "eaten"].contains(where: { lower.contains($0) }) { return "Logging food..." }
        if ["start", "begin", "workout", "chest", "legs", "push", "pull"].contains(where: { lower.contains($0) }) { return "Setting up workout..." }
        if ["took", "supplement", "vitamin", "creatine"].contains(where: { lower.contains($0) }) { return "Updating supplements..." }
        if lower.contains("glucose") || lower.contains("blood sugar") || lower.contains("spike") { return "Checking glucose..." }
        if lower.contains("plan") && lower.contains("meal") { return "Planning meals..." }
        if ["how", "what", "show", "calories", "weight", "sleep"].contains(where: { lower.contains($0) }) { return "Checking your data..." }
        return "Looking that up..."
    }

    /// Tool-specific step message for when a classified tool is about to execute.
    static func toolStepMessage(for toolName: String) -> String {
        switch toolName {
        case "log_food": return "Looking up food..."
        case "food_info": return "Checking nutrition..."
        case "log_weight", "weight_info", "set_goal": return "Checking weight data..."
        case "start_workout", "exercise_info", "log_activity": return "Checking workout history..."
        case "sleep_recovery": return "Checking recovery..."
        case "supplements", "mark_supplement", "add_supplement": return "Checking supplements..."
        case "glucose": return "Checking glucose data..."
        case "biomarkers": return "Checking lab results..."
        case "body_comp", "log_body_comp": return "Checking body composition..."
        case "copy_yesterday": return "Copying yesterday's food..."
        case "delete_food": return "Removing food entry..."
        case "explain_calories": return "Calculating your calories..."
        default: return "Processing..."
        }
    }

    // MARK: - Fallback Text

    static func fallbackText(for screen: AIScreen) -> String {
        switch screen {
        case .food: return "I can help you log food, check calories, or suggest meals. Try \"log 2 eggs\" or \"calories left\"."
        case .weight, .goal: return "I can log your weight or show your trend. Try \"I weigh 165\" or \"weight trend\"."
        case .exercise: return "I can start a workout or check your history. Try \"start push day\" or \"what should I train\"."
        case .bodyRhythm: return "I can tell you about your sleep and recovery. Try \"how did I sleep\" or \"HRV trend\"."
        case .supplements: return "I can check your supplement status. Try \"took vitamin D\" or \"did I take everything\"."
        case .glucose: return "I can look at your glucose patterns. Try \"any spikes today\"."
        case .biomarkers: return "I can check your lab results. Try \"which markers are out of range\"."
        case .bodyComposition: return "I can show your body composition data. Try \"body fat\" or \"DEXA results\"."
        case .cycle: return "I can tell you about your cycle. Try \"what phase am I in\"."
        default: return "I can help with food, weight, workouts, sleep, and more. Try \"log 2 eggs\", \"calories left\", or \"how am I doing\"."
        }
    }
}
