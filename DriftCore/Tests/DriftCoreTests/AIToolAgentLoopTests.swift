import Foundation
@testable import DriftCore
import Testing

/// The bounded multi-step tool loop (#coach-agent-loop). Uses a stubbed classify
/// fn + temporary registered tools so it's deterministic and network-free.
@MainActor
@Test func toolChainSingleHopForNonChainableTool() async {
    let r = ToolRegistry.shared
    r.register(ToolSchema(id: "t.term", name: "loop_term_tool", service: "x", description: "d",
                          parameters: [], handler: { _ in .text("done") }))
    defer { r.unregister(name: "loop_term_tool") }

    // If the loop were entered, classify would override the text with "LOOPED".
    let stub: AIToolAgent.ClassifyFn = { _, _ in .text("LOOPED") }
    let out = await AIToolAgent.executeToolChain(
        initial: ToolCall(tool: "loop_term_tool", params: ToolCallParams(values: [:])),
        message: "x", history: "", classify: stub)
    #expect(out.text == "done")   // non-chainable → returned executeTool, never looped
}

@MainActor
@Test func toolChainWebSearchThenTerminalTool() async {
    let r = ToolRegistry.shared
    r.register(ToolSchema(id: "t.s", name: "loop_search", service: "web", description: "d",
                          parameters: [ToolParam("query", "string", "q")],
                          handler: { _ in .text("found: paneer ~265 cal/100g") }))
    r.register(ToolSchema(id: "t.l", name: "loop_log", service: "food", description: "d",
                          parameters: [ToolParam("name", "string", "n")],
                          handler: { _ in .action(.navigate(tab: 2)) }))
    defer { r.unregister(name: "loop_search"); r.unregister(name: "loop_log") }

    // After the search result, the model decides to log the found food.
    let stub: AIToolAgent.ClassifyFn = { _, _ in
        .toolCall(IntentClassifier.ClassifiedIntent(tool: "loop_log", params: ["name": "paneer"], confidence: "high"))
    }
    let out = await AIToolAgent.executeToolChain(
        initial: ToolCall(tool: "loop_search", params: ToolCallParams(values: ["query": "paneer"])),
        message: "calories in paneer then log it", history: "",
        chainable: ["loop_search"], classify: stub)
    #expect(out.toolsCalled.contains("loop_search"))
    #expect(out.toolsCalled.contains("loop_log"))
    #expect(out.action != nil)   // chained into the terminal action tool
}

@MainActor
@Test func toolChainStopsWhenModelRepliesText() async {
    let r = ToolRegistry.shared
    r.register(ToolSchema(id: "t.s2", name: "loop_search2", service: "web", description: "d",
                          parameters: [], handler: { _ in .text("raw search results") }))
    defer { r.unregister(name: "loop_search2") }

    let stub: AIToolAgent.ClassifyFn = { _, _ in .text("Paneer has ~265 cal/100g.") }
    let out = await AIToolAgent.executeToolChain(
        initial: ToolCall(tool: "loop_search2", params: ToolCallParams(values: [:])),
        message: "q", history: "", chainable: ["loop_search2"], classify: stub)
    #expect(out.text == "Paneer has ~265 cal/100g.")
    #expect(out.action == nil)
}

@MainActor
@Test func toolChainRespectsMaxHops() async {
    let r = ToolRegistry.shared
    r.register(ToolSchema(id: "t.lp", name: "loop_forever", service: "web", description: "d",
                          parameters: [], handler: { _ in .text("more") }))
    defer { r.unregister(name: "loop_forever") }

    // Model keeps calling the chainable tool — maxHops must stop the runaway.
    let stub: AIToolAgent.ClassifyFn = { _, _ in
        .toolCall(IntentClassifier.ClassifiedIntent(tool: "loop_forever", params: [:], confidence: "high"))
    }
    let out = await AIToolAgent.executeToolChain(
        initial: ToolCall(tool: "loop_forever", params: ToolCallParams(values: [:])),
        message: "q", history: "", maxHops: 3, chainable: ["loop_forever"], classify: stub)
    #expect(out.toolsCalled.filter { $0 == "loop_forever" }.count == 3)   // exactly maxHops
}
