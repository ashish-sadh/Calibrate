import Foundation

// MARK: - Tool Schema

/// Describes a tool the SLM can invoke. UI views also call service methods directly.
public struct ToolParam: Sendable {
    public let name: String
    public let type: String          // "string", "number", "boolean"
    public let description: String
    public let required: Bool

    public init(_ name: String, _ type: String, _ description: String, required: Bool = true) {
        self.name = name; self.type = type; self.description = description; self.required = required
    }
}

/// Result of executing a tool.
public enum ToolResult: Sendable {
    case text(String)
    case action(ToolAction)
    case error(String)
}

/// UI actions a tool can trigger.
public enum ToolAction: Sendable {
    case openFoodSearch(query: String, servings: Double?)
    case openRecipeBuilder(items: [String], mealName: String?)
    case openWorkout(templateName: String)
    case openWeightEntry
    case openBarcodeScanner
    case navigate(tab: Int)
    case openManualFoodEntry(name: String, calories: Int, proteinG: Double, carbsG: Double, fatG: Double)
}

/// Parameters passed to a tool handler, extracted from LLM JSON output.
public struct ToolCallParams: Sendable {
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public func string(_ key: String) -> String? { values[key] }

    public func double(_ key: String) -> Double? {
        guard let s = values[key] else { return nil }
        return Double(s)
    }

    public func int(_ key: String) -> Int? {
        guard let s = values[key] else { return nil }
        return Int(s)
    }
}

/// A parsed tool call from LLM output.
public struct ToolCall: Sendable {
    public let tool: String
    public let params: ToolCallParams

    public init(tool: String, params: ToolCallParams) {
        self.tool = tool
        self.params = params
    }
}

// MARK: - Hook Result Types

/// PreHook result — validate, transform, route, or ask for confirmation before execution.
public enum PreHookResult: Sendable {
    case valid(ToolCallParams)
    case transform(ToolCallParams)
    case invalid(reason: String)
    case route(ToolResult)
    case confirm(message: String, params: ToolCallParams)
}

/// PostHook result — verify tool output, optionally reject with fallback.
public enum PostHookResult: Sendable {
    case accept(followUp: String?)
    case reject(reason: String, fallback: String)
}

/// A registered tool with schema + handler.
public struct ToolSchema: Identifiable {
    public let id: String
    public let name: String
    public let service: String
    public let description: String
    public let parameters: [ToolParam]
    public var needsConfirmation: Bool = false
    public var preHook: (@MainActor (ToolCallParams) async -> PreHookResult)?
    public var validate: (@MainActor (ToolCallParams) -> String?)?
    public let handler: @MainActor (ToolCallParams) async -> ToolResult
    public var postHook: (@MainActor (ToolResult) -> PostHookResult)?

    public init(
        id: String,
        name: String,
        service: String,
        description: String,
        parameters: [ToolParam],
        needsConfirmation: Bool = false,
        preHook: (@MainActor (ToolCallParams) async -> PreHookResult)? = nil,
        validate: (@MainActor (ToolCallParams) -> String?)? = nil,
        handler: @MainActor @escaping (ToolCallParams) async -> ToolResult,
        postHook: (@MainActor (ToolResult) -> PostHookResult)? = nil
    ) {
        self.id = id
        self.name = name
        self.service = service
        self.description = description
        self.parameters = parameters
        self.needsConfirmation = needsConfirmation
        self.preHook = preHook
        self.validate = validate
        self.handler = handler
        self.postHook = postHook
    }
}

// MARK: - Tool Registry

/// Singleton registry of all tools. Both AI chat and UI can use this.
@MainActor
public final class ToolRegistry {
    public static let shared = ToolRegistry()
    private var tools: [String: ToolSchema] = [:]

    private init() {}

    public func register(_ tool: ToolSchema) {
        tools[tool.name] = tool
    }

    /// Remove a tool by name. No-op if not registered.
    public func unregister(name: String) {
        tools.removeValue(forKey: name)
    }

    public func tool(named name: String) -> ToolSchema? {
        tools[name]
    }

    public func allTools() -> [ToolSchema] {
        Array(tools.values)
    }

    /// Tools relevant to a screen (food screen → food tools first, etc.).
    /// Screen→service mapping lives on `AIScreen.serviceName` — single source of truth.
    public func toolsForScreen(_ screen: String) -> [ToolSchema] {
        let screenService = AIScreen(rawValue: screen)?.serviceName
        let sorted = tools.values.sorted { a, b in
            if a.service == screenService && b.service != screenService { return true }
            if a.service != screenService && b.service == screenService { return false }
            return a.name < b.name
        }
        return sorted
    }

    /// Compact schema string for the LLM prompt.
    public func schemaPrompt(forScreen screen: String? = nil, isLargeModel: Bool = false) -> String {
        let toolList: [ToolSchema]
        if isLargeModel {
            toolList = Array(allTools().sorted { $0.name < $1.name })
        } else {
            let relevant = screen.map { toolsForScreen($0) } ?? allTools()
            toolList = Array(relevant.prefix(6))
        }
        let lines = toolList.map { t in
            let params = t.parameters.map { "\($0.name):\($0.type)" }.joined(separator: ", ")
            return "- \(t.name)(\(params)) — \(t.description)"
        }
        var result = "Tools:\n\(lines.joined(separator: "\n"))"
        if isLargeModel, let screen {
            result += "\nCurrent screen: \(screen)"
        }
        return result
    }
}

// MARK: - JSON Tool Call Parsing

/// Parse a JSON tool call from LLM output.
/// Expected format: {"tool":"name","params":{"key":"value"}}
public func parseToolCallJSON(_ text: String) -> ToolCall? {
    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}") else { return nil }
    let jsonStr = String(text[start...end])
    guard let data = jsonStr.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          var toolName = json["tool"] as? String else { return nil }

    if let parenIdx = toolName.firstIndex(of: "(") {
        toolName = String(toolName[..<parenIdx])
    }
    toolName = toolName.trimmingCharacters(in: .whitespaces)

    var params: [String: String] = [:]
    if let p = json["params"] as? [String: Any] {
        for (key, value) in p {
            params[key] = "\(value)"
        }
    }
    return ToolCall(tool: toolName, params: ToolCallParams(values: params))
}
