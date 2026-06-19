import Foundation
@testable import DriftCore
import Testing

/// Native function-calling schema generation (#coach-agent-loop): the registry
/// is the single source of truth for what the model sees.
@MainActor
@Test func toolsJSONSchemaProducesOpenAIFunctionShape() {
    let reg = ToolRegistry.shared
    reg.register(ToolSchema(
        id: "t_log", name: "test_log_food", service: "food",
        description: "Log a food item.",
        parameters: [
            ToolParam("name", "string", "Food name"),
            ToolParam("amount", "number", "Amount in grams", required: false),
        ],
        handler: { _ in .text("ok") }
    ))
    defer { reg.unregister(name: "test_log_food") }

    guard let fn = reg.toolsJSONSchema().first(where: {
        (($0["function"] as? [String: Any])?["name"] as? String) == "test_log_food"
    }) else {
        Issue.record("test_log_food not in schema"); return
    }
    #expect(fn["type"] as? String == "function")
    let function = fn["function"] as! [String: Any]
    #expect(function["description"] as? String == "Log a food item.")
    let params = function["parameters"] as! [String: Any]
    #expect(params["type"] as? String == "object")
    let props = params["properties"] as! [String: Any]
    #expect((props["name"] as? [String: Any])?["type"] as? String == "string")
    #expect((props["amount"] as? [String: Any])?["type"] as? String == "number")
    let required = params["required"] as! [String]
    #expect(required.contains("name"))
    #expect(!required.contains("amount"))   // optional param excluded from required
}

@MainActor
@Test func toolsJSONStringIsValidJSONArray() {
    let reg = ToolRegistry.shared
    reg.register(ToolSchema(id: "t", name: "test_probe_tool", service: "x", description: "d",
                            parameters: [], handler: { _ in .text("ok") }))
    defer { reg.unregister(name: "test_probe_tool") }

    guard let s = reg.toolsJSONString(), let data = s.data(using: .utf8) else {
        Issue.record("toolsJSONString nil"); return
    }
    let arr = try? JSONSerialization.jsonObject(with: data) as? [Any]
    #expect(arr != nil)
    #expect((arr?.isEmpty ?? true) == false)
}
