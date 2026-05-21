import Foundation

// MARK: - Navigation Notifications

public extension Notification.Name {
    static let navigateToTab = Notification.Name("drift.navigateToTab")
    static let saveConversationState = Notification.Name("drift.saveConversationState")
    /// Posted by the V6 Dashboard quick-log row's "Snap" chip. FoodTabView
    /// listens and flips its `showingPhotoLog` binding; PhotoLogFlowView
    /// renders its own opt-in onboarding when CloudVisionKey isn't configured,
    /// so no separate gate is needed at the call site.
    static let openPhotoLog = Notification.Name("drift.openPhotoLog")
    /// Posted by the V6 Dashboard quick-log row's "Search" chip. FoodTabView
    /// flips `showingSearch` to present FoodSearchView.
    static let openFoodSearch = Notification.Name("drift.openFoodSearch")
    /// Posted by the V6 Dashboard quick-log row's "Voice" chip after enabling
    /// AI. FloatingAIAssistant listens and auto-expands so the user sees the
    /// chat + mic button on the first tap instead of a stranded corner bubble.
    /// V7: FloatingAIAssistant is gone (replaced by DriftCoachSheet) — the
    /// Voice chip now posts `.openLogMeal(mode: .voice)` instead and the
    /// notification below is retained for backwards-compat in case a
    /// straggler call site still posts it.
    static let expandAIAssistant = Notification.Name("drift.expandAIAssistant")

    /// V7: posted by the Dashboard quick-log chips (Snap/Voice/Search/Recent)
    /// to open the unified Log-a-Meal sheet at a specific mode. ContentView
    /// listens, sets its `pendingLogMealMode` state, and flips the sheet
    /// presentation. `userInfo["mode"]` is a `LogMealMode` rawValue string.
    static let openLogMeal = Notification.Name("drift.openLogMeal")
}

// MARK: - Tool Registry Execution (iOS-side)

@MainActor
extension ToolRegistry {
    /// Execute a tool call by name. Runs pre-hook → validation → handler → post-hook.
    /// Lives in Drift (not DriftCore) because it touches `ConversationState.shared`.
    public func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = self.tool(named: call.tool) else {
            return .error("Unknown tool: \(call.tool)")
        }

        var params = call.params
        if let preHook = tool.preHook {
            switch await preHook(params) {
            case .valid(let p): params = p
            case .transform(let p): params = p
            case .invalid(let reason):
                ConversationState.shared.pendingIntent = .awaitingParam(
                    tool: call.tool, missing: reason, partialParams: call.params.values)
                return .error(reason)
            case .route(let result):
                ConversationState.shared.recordToolExecution(tool: call.tool, params: call.params.values)
                return result
            case .confirm(let message, let confirmParams):
                ConversationState.shared.pendingIntent = .awaitingConfirmation(
                    tool: call.tool, message: message, params: confirmParams.values)
                return .text(message)
            }
        }

        if let validate = tool.validate, let error = validate(params) {
            return .error(error)
        }

        let result = await tool.handler(params)
        ConversationState.shared.recordToolExecution(tool: call.tool, params: params.values)

        if let postHook = tool.postHook {
            switch postHook(result) {
            case .accept(let followUp):
                if let followUp, case .text(let text) = result {
                    return .text(text + " " + followUp)
                }
                return result
            case .reject(_, let fallback):
                return .text(fallback)
            }
        }

        return result
    }
}
