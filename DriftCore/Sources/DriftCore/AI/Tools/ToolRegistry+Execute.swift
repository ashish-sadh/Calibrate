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
    /// V7: posted by the Dashboard quick-log chips (Snap/Voice/Search/Recent)
    /// to open the unified Log-a-Meal sheet at a specific mode. ContentView
    /// listens, sets its `pendingLogMealMode` state, and flips the sheet
    /// presentation. `userInfo["mode"]` is a `LogMealMode` rawValue string.
    static let openLogMeal = Notification.Name("drift.openLogMeal")

    /// V7: the canonical "open Drift Coach" signal — posted by VoiceLogSheet's
    /// "Edit in chat" button and the Today coaching nudge's Ask AI pill (#928).
    /// ContentView listens and presents
    /// `DriftCoachSheet(prefill: userInfo["prefill"])`.
    static let openDriftCoach = Notification.Name("drift.openDriftCoach")

    /// 2026-05-24: broadcast by ContentView when the Photo Log
    /// fullScreenCover dismisses (and could be used by any other
    /// global write site). FoodTabView listens and reloads its
    /// diary so a Snap-from-dashboard lands in the diary without
    /// the user having to swipe-refresh. Centralising the cover at
    /// ContentView fixed a double-presentation race where the
    /// first Snap tap from Dashboard silently swallowed the
    /// present and only the second tap opened it.
    static let foodEntryAdded = Notification.Name("drift.foodEntryAdded")

    /// 2026-07-07: posted by PhotoLogFlowView when the user actually LOGS
    /// the reviewed meal (not on cancel/retake). LogMealSheet listens and
    /// dismisses itself so a successful Snap lands the user on the Food
    /// diary to verify the entry — instead of bouncing back to the
    /// "Log a meal" page (field complaint).
    static let photoLogCompleted = Notification.Name("drift.photoLogCompleted")
}

// MARK: - Tool Registry Execution (iOS-side)

@MainActor
extension ToolRegistry {
    /// Execute a tool call by name. Runs pre-hook → validation → handler → post-hook.
    /// Lives in Drift (not DriftCore) because it touches `ConversationState.shared`.
    public func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = self.tool(named: call.tool) else {
            // Registry size is what separates the two causes of this branch:
            // a populated registry means the model invented a tool name (the
            // benign case the canned fallback exists for), an empty one means
            // the shell forgot to call `ToolRegistration.registerAll()` — the
            // bug that shipped twice, on iOS (96e3173) and Android (#1209).
            Log.app.info("Unknown tool: \(call.tool) — registry has \(self.allTools().count) tools")
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
