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
    let handler: @MainActor (ToolCallParams) async -> ToolResult
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

    /// Compact schema string for the LLM prompt. Keeps token count low.
    func schemaPrompt(forScreen screen: String? = nil) -> String {
        let relevant = screen.map { toolsForScreen($0) } ?? allTools()
        let lines = relevant.prefix(12).map { t in
            let params = t.parameters.map { "\($0.name):\($0.type)" }.joined(separator: ", ")
            return "- \(t.name)(\(params)) — \(t.description)"
        }
        return "Tools:\n\(lines.joined(separator: "\n"))"
    }

    /// Execute a tool call by name.
    func execute(_ call: ToolCall) async -> ToolResult {
        guard let tool = tools[call.tool] else {
            return .error("Unknown tool: \(call.tool)")
        }
        return await tool.handler(call.params)
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
          let toolName = json["tool"] as? String else { return nil }

    var params: [String: String] = [:]
    if let p = json["params"] as? [String: Any] {
        for (key, value) in p {
            params[key] = "\(value)"
        }
    }
    return ToolCall(tool: toolName, params: ToolCallParams(values: params))
}
