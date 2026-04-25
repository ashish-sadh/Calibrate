import Foundation
import DriftCore

// MARK: - Agent Output

/// What the agent returns to AIChatView.
public struct AgentOutput: Sendable {
    public let text: String                  // User-facing message
    public let action: ToolAction?           // Optional UI action (open sheet, etc.)
    public let toolsCalled: [String]         // For debugging/logging
    public var clarificationOptions: [ClarificationOption]? = nil
    public var didFail: Bool = false

    public init(text: String, action: ToolAction?, toolsCalled: [String], clarificationOptions: [ClarificationOption]? = nil, didFail: Bool = false) {
        self.text = text
        self.action = action
        self.toolsCalled = toolsCalled
        self.clarificationOptions = clarificationOptions
        self.didFail = didFail
    }
}

// MARK: - AI Tool Agent

/// Unified tiered pipeline for both SmolLM and Gemma 4:
/// 1. Rules on raw input (instant, both models)
/// 2. LLM classify → tool call or text (Gemma only)
/// 3. Tool-first execution → stream presentation with real data (both)
/// 4. LLM fallback (Gemma: direct streaming, SmolLM: AIChainOfThought)
/// All LLM calls have a 20s timeout.
/// Token budget: 4096 context, ~3300 max prompt, 256 max generation.
@MainActor
public enum AIToolAgent {

    private static let llmTimeout: UInt64 = 20_000_000_000 // 20 seconds in nanoseconds

    // MARK: - #240 Auto-retry on empty/incomplete extraction

    /// Tools that justify a second classify pass when the first returns no
    /// tool call or missing required params. Chosen from the per-tool gold
    /// set tail: log_food/log_weight/mark_supplement are most common; the
    /// other two sit at ~90% and benefit most from the retry lift.
    nonisolated static let retryTargetTools: Set<String> = [
        "log_food", "edit_meal", "log_weight", "mark_supplement", "food_info"
    ]

    /// Literal-mode hint appended to the user message on the retry call.
    /// Intentionally short — long nudges crowd the instruction window on Gemma.
    nonisolated static let literalRetryHint = "Be literal. Extract whatever food, weight, or supplement the user named. If unsure which tool, pick the most specific one."

    /// Decide whether to retry intent classification with a literal hint.
    /// True when the flag is on AND the first result is nil OR a target
    /// tool with missing required params. Pure — safe to unit-test.
    nonisolated static func shouldRetryClassify(_ result: IntentClassifier.ClassifyResult?) -> Bool {
        guard Features.autoRetryOnEmpty else { return false }
        guard let result else { return true } // nil = LLM timed out or returned empty
        switch result {
        case .text:
            // LLM chose to respond with plain text — don't retry, it had reason
            return false
        case .toolCall(let intent):
            let tool = intent.tool.replacingOccurrences(of: "()", with: "")
            guard retryTargetTools.contains(tool) else { return false }
            return !hasRequiredParams(tool: tool, params: intent.params)
        }
    }

    /// Tool-specific required-param check — mirrors the minimum the tool
    /// needs to do its job without prompting the user.
    nonisolated static func hasRequiredParams(tool: String, params: [String: String]) -> Bool {
        func filled(_ key: String) -> Bool {
            guard let v = params[key]?.trimmingCharacters(in: .whitespaces) else { return false }
            return !v.isEmpty
        }
        switch tool {
        case "log_food":        return filled("name")
        case "edit_meal":       return filled("action")
        case "log_weight":      return filled("value")
        case "mark_supplement": return filled("name")
        case "food_info":       return filled("query") || filled("name")
        default:                return true
        }
    }

    /// Thread-safe state for the streaming token callback.
    private final class StreamState: @unchecked Sendable {
        var buffer = ""
        var isToolCall = false
        var modeDetected = false
    }

    // MARK: - Main Entry Point (Tiered)

    public static func run(
        message: String,
        screen: AIScreen,
        history: String,
        isLargeModel: Bool,
        onStep: (String) -> Void,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> AgentOutput {
        let telemetryStart = CFAbsoluteTimeGetCurrent()
        let output = await runInner(
            message: message, screen: screen, history: history,
            isLargeModel: isLargeModel, onStep: onStep, onToken: onToken
        )
        // #261 — opt-in gate is inside the service; this call is a no-op by default.
        // When opt-in is on, `output.text` (the final user-facing response) is
        // captured alongside the query so transcripts drive multi-turn analysis.
        let latencyMs = Int((CFAbsoluteTimeGetCurrent() - telemetryStart) * 1000)
        ChatTelemetryService.shared.record(
            query: message,
            response: output.text,
            intent: telemetryIntent(for: output),
            tool: output.toolsCalled.first,
            outcome: telemetryOutcome(for: output),
            latencyMs: latencyMs,
            turnIndex: ConversationState.shared.turnCount
        )
        return output
    }

    /// Classify the pipeline outcome into a telemetry `IntentLabel`. Ordering
    /// matters: clarifications surface before tool labels because a clarifier
    /// result includes no tool in `toolsCalled`.
    nonisolated static func telemetryIntent(for output: AgentOutput) -> ChatTelemetryService.IntentLabel? {
        if output.clarificationOptions?.isEmpty == false { return .clarification }
        let first = output.toolsCalled.first ?? ""
        switch first {
        case "timeout":     return .timeout
        case "classifier":  return .text
        case "clarifier":   return .clarification
        case "":            return nil
        default:            return .toolCall
        }
    }

    /// Map output → telemetry outcome. `failed`/`timeout` are distinct so we
    /// can tell "user needed clarification" from "tool handler errored" from
    /// "pipeline hit the wall." Order matters: timeout beats everything,
    /// clarification beats didFail (a clarifying response isn't a failure),
    /// didFail beats success. #281.
    nonisolated static func telemetryOutcome(for output: AgentOutput) -> ChatTelemetryService.Outcome {
        let first = output.toolsCalled.first ?? ""
        if first == "timeout" { return .timeout }
        if output.clarificationOptions?.isEmpty == false { return .clarified }
        if output.didFail { return .failed }
        return .success
    }

    private static func runInner(
        message: String,
        screen: AIScreen,
        history: String,
        isLargeModel: Bool,
        onStep: (String) -> Void,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> AgentOutput {

        let pipelineStart = CFAbsoluteTimeGetCurrent()

        // ── Step 0: Input normalization (instant, no LLM) ──
        // Strips filler words, voice artifacts, repeated words, collapses whitespace.
        // All subsequent phases see clean input.
        var normalized = InputNormalizer.normalize(message)

        // ── Step 0b: Cross-domain pronoun resolution (#241) ──
        // Rewrite "how much protein in that" → "how much protein in <last entry>"
        // before classification so the LLM sees a concrete subject. Food
        // action pronouns ("log that") are still handled by the chat VM's
        // food-scoped resolver — PronounResolver returns nil for action
        // verbs to avoid double-binding.
        if let freshEntry = ConversationState.shared.freshLastEntry(),
           let rewritten = PronounResolver.resolve(message: normalized, context: freshEntry) {
            Log.app.info("Pronoun resolved: '\(normalized)' → '\(rewritten)'")
            normalized = rewritten
        }

        // ── Phase 1: Try rules on raw input (instant, both models) ──
        // Only for high-confidence action commands (undo, delete, greetings)
        if let toolCall = ToolRanker.tryRulePick(query: normalized, screen: screen) {
            logTiming("Phase 1 (rules)", start: pipelineStart)
            return await executeTool(toolCall)
        }

        // ── Phase 2a: Ask-don't-guess clarification (pre-classifier) ──
        // Genuinely-ambiguous inputs ("biryani", "creatine", bare numbers)
        // divert to a tappable clarifier BEFORE spending an LLM call. Keeps
        // gold sets stable — narrow detection by design. #226.
        if isLargeModel, let options = ClarificationBuilder.buildOptions(for: normalized),
           options.count >= 2 {
            Log.app.info("Clarification: offering \(options.count) options for '\(message)'")
            return AgentOutput(
                text: ClarificationBuilder.promptText(options),
                action: nil, toolsCalled: ["clarifier"],
                clarificationOptions: options
            )
        }

        // ── Phase 2: LLM Intent Classification (Gemma only) ──
        // Handles: intent detection, typo fixing, word numbers, pronoun resolution — all in one call
        if isLargeModel {
            onStep(stepMessage(for: message))

            // Try LLM intent classifier first. If the first extraction
            // returns no tool call or incomplete params for a top-5 tool,
            // retry ONCE with a "be literal" hint (#240).
            let classifyStart = CFAbsoluteTimeGetCurrent()
            let firstResult = await IntentClassifier.classifyFull(message: normalized, history: history)
            let finalResult: IntentClassifier.ClassifyResult?
            if shouldRetryClassify(firstResult) {
                Log.app.info("IntentClassifier: empty/incomplete first result — retrying with literal hint (#240)")
                let retried = await IntentClassifier.classifyFull(
                    message: normalized, history: history, literalHint: literalRetryHint
                )
                finalResult = retried ?? firstResult
            } else {
                finalResult = firstResult
            }
            if let result = finalResult {
                logTiming("Phase 2 (classify)", start: classifyStart)
                switch result {
                case .toolCall(let intent):
                    // Strip parentheses from tool name (LLM quirk: "food_info()" → "food_info")
                    let toolName = intent.tool.replacingOccurrences(of: "()", with: "")
                    // Clarify-vs-proceed is delegated to `IntentThresholds`,
                    // which encodes the per-domain policy (food leans toward
                    // proceed, meta/navigate_to demands high confidence, etc.).
                    // Complete params still beat keyword ambiguity — we don't
                    // prompt on "log 3 eggs" because `log` is a bare verb. #302.
                    let extractorComplete = ClarificationBuilder.hasCompleteParams(
                        tool: toolName, params: intent.params
                    )
                    let decision = IntentThresholds.shouldClarify(
                        tool: toolName,
                        confidence: intent.confidence,
                        hasCompleteParams: extractorComplete
                    )
                    if decision == .clarify {
                        Log.app.info("IntentThresholds: clarify → \(intent.tool) for '\(message)' (confidence: \(intent.confidence))")
                        if let opts = ClarificationBuilder.buildOptions(for: normalized),
                           opts.count >= 2 {
                            return AgentOutput(
                                text: ClarificationBuilder.promptText(opts),
                                action: nil, toolsCalled: ["clarifier"],
                                clarificationOptions: opts
                            )
                        }
                    }
                    let rawCall = ToolCall(tool: toolName, params: ToolCallParams(values: intent.params))
                    // Stage 3b: Validate LLM-extracted params with Swift checks
                    let call = validateExtraction(rawCall, message: message)
                    if isInfoTool(toolName) {
                        // Stage label 1: show query-specific lookup label before tool execute
                        onStep(toolLookupMessage(for: call, query: message))
                        let stageStart = CFAbsoluteTimeGetCurrent()
                        let toolResult = await ToolRegistry.shared.execute(call)
                        // Guarantee ≥300ms on the lookup stage so users can read it
                        let elapsed = CFAbsoluteTimeGetCurrent() - stageStart
                        if elapsed < 0.3 {
                            try? await Task.sleep(nanoseconds: UInt64((0.3 - elapsed) * 1_000_000_000))
                        }
                        if case .text(let data) = toolResult, !data.isEmpty {
                            ConversationState.shared.captureToolSummary(data)
                            // Stage label 2: data ready, starting presentation
                            onStep(toolFoundMessage(for: toolName))
                            return await streamPresentation(
                                query: message, toolData: data, screen: screen, history: history, onToken: onToken
                            )
                        }
                    } else {
                        onStep(toolStepMessage(for: call.tool))
                        // #178: multi-item food → stream per-item results before recipe builder
                        if toolName == "log_food",
                           let name = call.params.values["name"],
                           name.contains(",") {
                            return await executeMultiItemFoodDisclosure(
                                name: name, mealHint: call.params.values["meal"], onToken: onToken
                            )
                        }
                        return await executeTool(call)
                    }
                case .text(let response):
                    // LLM chose to respond with text (follow-up question, greeting, etc.)
                    // Surface it directly — this enables multi-turn clarification
                    return AgentOutput(text: response, action: nil, toolsCalled: ["classifier"])
                }
            }

            // Normalizer removed — classifier now handles typos, word numbers,
            // pronoun resolution, and multi-turn context in one LLM call.
        }

        // ── Phase 3: Tool-first execution → stream presentation (both models) ──
        onStep(stepMessage(for: normalized))
        let toolResults = await executeRelevantTools(query: normalized, screen: screen)

        // If a tool returned a UI action, return it directly
        if let actionResult = toolResults.first(where: { $0.action != nil }) {
            return actionResult
        }

        // If we got data, stream a natural presentation with it (large model)
        // or return raw data directly (small model — LLM presentation unreliable)
        if !toolResults.isEmpty {
            let data = toolResults.map(\.text).joined(separator: "\n")
            ConversationState.shared.captureToolSummary(data)
            if isLargeModel {
                onStep("Preparing answer...")
                return await streamPresentation(
                    query: normalized, toolData: data, screen: screen, history: history, onToken: onToken
                )
            } else {
                // SmolLM: add a brief insight prefix to raw data
                let prefixed = addInsightPrefix(to: data)
                return AgentOutput(text: prefixed, action: nil, toolsCalled: toolResults.flatMap(\.toolsCalled))
            }
        }

        // ── Phase 4: LLM fallback ──
        onStep("Thinking...")
        if isLargeModel {
            // Gemma: direct streaming with tool-call detection
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
        } else {
            // SmolLM: context-enriched streaming via AIChainOfThought
            let response = await AIChainOfThought.execute(
                query: normalized, screen: screen, history: history,
                onStep: onStep, onToken: onToken
            )

            // Check for tool call in response
            if let toolCall = parseToolCallJSON(response) {
                return await executeTool(toolCall)
            }
            return handleTextResponse(response, screen: screen)
        }
    }

    // MARK: - Multi-Item Food Disclosure (#178)

    /// For "rice, dal" inputs: look up each item in the local DB in parallel and stream
    /// each result via onToken as it resolves (first-come-first-served). Returns the
    /// recipe-builder action alongside a text summary so the chat bubble persists after
    /// the sheet opens. Final order matches input order for the recipe builder.
    static func executeMultiItemFoodDisclosure(
        name: String,
        mealHint: String?,
        onToken: @escaping @Sendable (String) -> Void
    ) async -> AgentOutput {
        let items = name.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard items.count > 1 else {
            return await executeTool(ToolCall(tool: "log_food", params: ToolCallParams(values: ["name": name])))
        }

        // Resolve all items in parallel; stream each as it completes (progressive disclosure).
        // findFood is nonisolated sync, so tasks run off MainActor for true concurrency.
        var resultsByIndex = [(Int, String, String)]()  // (originalIndex, resolvedName, summaryLine)
        await withTaskGroup(of: (Int, String, String).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask {
                    if let match = AIActionExecutor.findFood(query: item, servings: nil, gramAmount: nil) {
                        let cal = Int(match.food.calories * match.servings)
                        return (index, match.food.name, "\(match.food.name) — \(cal) cal")
                    }
                    return (index, item, item.capitalized)
                }
            }
            for await (idx, resolvedName, line) in group {
                onToken(line + "\n")  // stream as each task finishes
                resultsByIndex.append((idx, resolvedName, line))
            }
        }

        // Sort back to input order for the recipe builder and final bubble text.
        let sorted = resultsByIndex.sorted { $0.0 < $1.0 }
        let resolvedNames = sorted.map { $0.1 }
        let summaryLines = sorted.map { $0.2 }

        let summary = resolvedNames.joined(separator: ", ")
        ConversationState.shared.captureToolSummary("Multi-item log: \(summary)")
        let action = ToolAction.openRecipeBuilder(items: resolvedNames, mealName: mealHint)
        return AgentOutput(text: summaryLines.joined(separator: "\n"), action: action, toolsCalled: ["log_food"])
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
        "supplements", "glucose", "biomarkers", "body_comp", "explain_calories",
        "cross_domain_insight"
    ]

    static func isInfoTool(_ name: String) -> Bool {
        infoTools.contains(name)
    }

    // MARK: - Stage 3b: Swift Validation

    /// Validate LLM-extracted params before execution. Catches obvious errors
    /// (bad names, out-of-range values) and falls back to Swift extraction.
    /// Always returns a ToolCall — let preHook handle nuanced edge cases.
    static func validateExtraction(_ call: ToolCall, message: String) -> ToolCall {
        switch call.tool {
        case "log_food":
            return validateFoodParams(call, message: message)
        case "log_weight":
            return validateWeightParams(call, message: message)
        case "log_activity":
            return validateActivityParams(call)
        default:
            return call
        }
    }

    private static func validateFoodParams(_ call: ToolCall, message: String) -> ToolCall {
        var values = call.params.values

        // Fix param name mismatch: IntentClassifier sends "servings", tool expects "amount"
        if let servings = values["servings"], values["amount"] == nil {
            values["amount"] = servings
            values.removeValue(forKey: "servings")
        }

        let name = values["name"]?.trimmingCharacters(in: .whitespaces) ?? ""
        let nameLooksBad = name.isEmpty || name.count <= 1 || name.allSatisfy(\.isNumber)

        if nameLooksBad, let foodIntent = AIActionExecutor.parseFoodIntent(message) {
            values["name"] = foodIntent.query
            if let g = foodIntent.gramAmount {
                values["amount"] = "\(Int(g))g"
            } else if let s = foodIntent.servings {
                values["amount"] = "\(s)"
            }
            if let m = foodIntent.mealHint { values["meal"] = m }
            return ToolCall(tool: call.tool, params: ToolCallParams(values: values))
        }

        // Clamp out-of-range servings — let preHook apply defaults
        if let amountStr = values["amount"], let amount = Double(amountStr),
           amount <= 0 || amount >= 100 {
            values.removeValue(forKey: "amount")
        }

        // Strip obviously bad calories/macros
        if let calStr = values["calories"], let cal = Double(calStr), cal > 10000 {
            values.removeValue(forKey: "calories")
        }
        for key in ["protein", "carbs", "fat"] {
            if let str = values[key], let val = Double(str), val < 0 {
                values.removeValue(forKey: key)
            }
        }

        return ToolCall(tool: call.tool, params: ToolCallParams(values: values))
    }

    private static func validateWeightParams(_ call: ToolCall, message: String) -> ToolCall {
        if let valueStr = call.params.values["value"], let value = Double(valueStr),
           value < 20 || value > 500 {
            // LLM extracted nonsense weight — try Swift extraction
            if let w = AIActionExecutor.parseWeightIntent(message, defaultUnit: Preferences.weightUnit) {
                return ToolCall(tool: call.tool, params: ToolCallParams(values: [
                    "value": "\(w.weightValue)",
                    "unit": w.unit == .kg ? "kg" : "lbs"
                ]))
            }
        }
        return call
    }

    private static func validateActivityParams(_ call: ToolCall) -> ToolCall {
        var values = call.params.values
        if let durStr = values["duration"], let dur = Double(durStr),
           dur < 1 || dur > 600 {
            values.removeValue(forKey: "duration")
        }
        return ToolCall(tool: call.tool, params: ToolCallParams(values: values))
    }

    // MARK: - Streaming Presentation

    /// Mutable presentation system prompt. Extracted for PromptOptimizer mutations.
    /// Placeholders: {timeContext} and {toneHint} are substituted at runtime.
    static var presentationPrompt: String = """
    Health coach. It's {timeContext}. {toneHint}
    Answer using ONLY the data below. Main observation first, then numbers. Warm, 2-3 sentences. No medical advice. No repeating the question. If topic shifts, acknowledge it naturally.
    Example: "Doing well — 1200 of 2000 cal, protein 85g. A chicken dinner closes the gap."
    """

    /// Stream a natural response with pre-fetched tool data injected.
    /// ~320 token prompt. First token in ~2s. Data is real, not hallucinated.
    private static func streamPresentation(
        query: String, toolData: String, screen: AIScreen, history: String = "",
        onToken: @escaping @Sendable (String) -> Void
    ) async -> AgentOutput {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeContext = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening"
        let toneHint: String
        if hour >= 20 {
            toneHint = "It's evening — be summary-oriented and encouraging about tomorrow."
        } else if hour < 10 {
            toneHint = "It's early — be motivating and forward-looking."
        } else {
            toneHint = "Keep it practical and action-oriented."
        }
        let system = presentationPrompt
            .replacingOccurrences(of: "{timeContext}", with: timeContext)
            .replacingOccurrences(of: "{toneHint}", with: toneHint)
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
            ConversationState.shared.captureToolSummary(text)
            return AgentOutput(text: text, action: nil, toolsCalled: [toolCall.tool])
        case .action(let action):
            // Action tools produce no user-visible text — synthesize a summary
            // so follow-ups ("what did I just log?") have context to reference.
            ConversationState.shared.captureToolSummary(actionSummary(toolCall: toolCall, action: action))
            return AgentOutput(text: "", action: action, toolsCalled: [toolCall.tool])
        case .error(let msg):
            // User-friendly error message instead of raw error
            let friendly = "I couldn't quite do that — \(msg.lowercased()). Try rephrasing or say \"help\" to see what I can do."
            return AgentOutput(text: friendly, action: nil, toolsCalled: [toolCall.tool], didFail: true)
        }
    }

    /// Human-readable one-liner for an action tool-call (log_food, start_workout,
    /// etc.) used as the "last action" summary when no text result is available.
    private static func actionSummary(toolCall: ToolCall, action: ToolAction) -> String {
        let p = toolCall.params.values
        switch toolCall.tool {
        case "log_food":
            let name = p["name"] ?? p["query"] ?? "food"
            if let amount = p["amount"] { return "Opened log for \(amount) \(name)" }
            if let servings = p["servings"] { return "Opened log for \(servings) \(name)" }
            return "Opened log for \(name)"
        case "log_weight":
            if let v = p["value"] { return "Opened weight entry: \(v) \(p["unit"] ?? "kg")" }
            return "Opened weight entry"
        case "start_workout":
            return "Started workout: \(p["name"] ?? "custom")"
        case "log_activity":
            return "Logged activity: \(p["name"] ?? "workout")"
        default:
            return "Executed \(toolCall.tool)"
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
            return AgentOutput(text: fallbackText(for: screen), action: nil, toolsCalled: [], didFail: true)
        }
        if AIResponseCleaner.hasHallucinatedNumbers(cleaned, context: AIContextBuilder.baseContext()) {
            return AgentOutput(text: fallbackText(for: screen), action: nil, toolsCalled: [], didFail: true)
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

    /// Stage 1 label: shown while the info tool is executing. Uses the actual query subject when available.
    static func toolLookupMessage(for call: ToolCall, query: String) -> String {
        switch call.tool {
        case "food_info":
            let subject = call.params.values["name"]
                ?? call.params.values["query"]
                ?? query.components(separatedBy: " ").filter { $0.count > 3 }.first
            if let subject, !subject.isEmpty { return "Looking up \(subject)..." }
            return "Looking up nutrition..."
        case "weight_info": return "Looking up your weight..."
        case "sleep_recovery": return "Looking up your sleep..."
        case "exercise_info": return "Looking up your workouts..."
        case "supplements": return "Looking up supplements..."
        case "glucose": return "Looking up glucose data..."
        case "biomarkers": return "Looking up lab results..."
        case "body_comp": return "Looking up body composition..."
        case "explain_calories": return "Looking up calorie data..."
        default: return "Looking that up..."
        }
    }

    /// Stage 2 label: shown after data is retrieved, while the presentation LLM warms up.
    static func toolFoundMessage(for toolName: String) -> String {
        switch toolName {
        case "food_info": return "Finding macros..."
        case "weight_info": return "Reading your trends..."
        case "sleep_recovery": return "Checking your recovery..."
        case "exercise_info": return "Reviewing your history..."
        case "supplements": return "Checking supplement status..."
        case "glucose": return "Analysing glucose data..."
        case "biomarkers": return "Reviewing lab results..."
        case "body_comp": return "Reading body composition..."
        case "explain_calories": return "Calculating your calories..."
        default: return "Putting it together..."
        }
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
