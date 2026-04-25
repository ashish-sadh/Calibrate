import Foundation

// MARK: - Navigation Notifications

public extension Notification.Name {
    static let navigateToTab = Notification.Name("drift.navigateToTab")
    static let saveConversationState = Notification.Name("drift.saveConversationState")
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
