import Foundation

// MARK: - Tool Schema

/// Describes a tool the SLM can invoke. UI views also call service methods directly.
struct ToolParam: Sendable {
    let name: String
    let type: String          // "string", "number", "boolean"
    let description: String
    let required: Bool

    init(_ name: String, _ type: String, _ description: String, required: Bool = true) {
        self.name = name; self.type = type; self.description = description; self.required = required
    }
}

/// Result of executing a tool.
enum ToolResult: Sendable {
    case text(String)                       // Inline chat response
    case action(ToolAction)                 // Open a sheet or navigate
    case error(String)                      // Something went wrong
}

/// UI actions a tool can trigger.
enum ToolAction: Sendable {
    case openFoodSearch(query: String, servings: Double?)
    case openWorkout(templateName: String)
    case openWeightEntry
    case navigate(tab: Int)
}

/// Parameters passed to a tool handler, extracted from LLM JSON output.
struct ToolCallParams: Sendable {
    let values: [String: String]

    func string(_ key: String) -> String? { values[key] }

    func double(_ key: String) -> Double? {
        guard let s = values[key] else { return nil }
        return Double(s)
    }

    func int(_ key: String) -> Int? {
        guard let s = values[key] else { return nil }
        return Int(s)
    }
}

/// A parsed tool call from LLM output.
struct ToolCall: Sendable {
    let tool: String
    let params: ToolCallParams
}

/// A registered tool with schema + handler.
struct ToolSchema: Identifiable {
    let id: String              // "food.search_food"
    let name: String            // "search_food"
    let service: String         // "food"
    let description: String     // Shown to LLM
    let parameters: [ToolParam]
    var needsConfirmation: Bool = false  // Tool asks user "yes" before executing
    var preHook: (@MainActor (ToolCallParams) async -> ToolCallParams)?  // Enrich params before execution
    var validate: (@MainActor (ToolCallParams) -> String?)?  // Returns error message if invalid, nil if OK
    let handler: @MainActor (ToolCallParams) async -> ToolResult
    var postHook: (@MainActor (ToolResult) -> String)?  // Suggest follow-up after execution
}

// MARK: - Tool Registry

/// Singleton registry of all tools. Both AI chat and UI can use this.
@MainActor
final class ToolRegistry {
    static let shared = ToolRegistry()
    private var tools: [String: ToolSchema] = [:]

    func register(_ tool: ToolSchema) {
        tools[tool.name] = tool
    }

    func tool(named name: String) -> ToolSchema? {
        tools[name]
    }

    func allTools() -> [ToolSchema] {
        Array(tools.values)
    }

    /// Tools relevant to a screen (food screen → food tools first, etc.)
    func toolsForScreen(_ screen: String) -> [ToolSchema] {
        let screenService: String? = switch screen {
        case "food": "food"
        case "weight", "goal": "weight"
        case "exercise": "exercise"
        case "bodyRhythm": "sleep"
        case "supplements": "supplement"
        case "glucose": "glucose"
        case "biomarkers": "biomarker"
        default: nil
        }
        // Put screen-relevant tools first, then the rest
        let sorted = tools.values.sorted { a, b in
            if a.service == screenService && b.service != screenService { return true }
            if a.service != screenService && b.service == screenService { return false }
            return a.name < b.name
        }
        return sorted
    }

    /// Compact schema string for the LLM prompt.
    /// Large models (Gemma 4) get ALL tools with a screen hint. Small models get max 6, screen-filtered.
    func schemaPrompt(forScreen screen: String? = nil, isLargeModel: Bool = false) -> String {
        let toolList: [ToolSchema]
        if isLargeModel {
            // Gemma 4: show all tools — it handles 10+ tools well
            toolList = Array(allTools().sorted { $0.name < $1.name })
        } else {
            // Small model: screen-filtered, max 6
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

    /// Execute a tool call by name. Runs pre-hook → validation → handler → post-hook.
    func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = tools[call.tool] else {
            return .error("Unknown tool: \(call.tool)")
        }
        // Pre-hook: enrich params (e.g., DB lookup, gram conversion)
        var params = call.params
        if let preHook = tool.preHook {
            params = await preHook(params)
        }
        // Validation
        if let validate = tool.validate, let error = validate(params) {
            return .error(error)
        }
        let result = await tool.handler(params)
        // Post-hook: append follow-up suggestion
        if let postHook = tool.postHook, case .text(let text) = result {
            let followUp = postHook(result)
            return .text(text + " " + followUp)
        }
        return result
    }

}

// MARK: - JSON Tool Call Parsing (nonisolated — usable from any context)

/// Parse a JSON tool call from LLM output.
/// Expected format: {"tool":"name","params":{"key":"value"}}
func parseToolCallJSON(_ text: String) -> ToolCall? {
    guard let start = text.firstIndex(of: "{"),
          let end = text.lastIndex(of: "}") else { return nil }
    let jsonStr = String(text[start...end])
    guard let data = jsonStr.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          var toolName = json["tool"] as? String else { return nil }

    // LLM sometimes copies parens from prompt: "sleep_recovery()" → "sleep_recovery"
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
