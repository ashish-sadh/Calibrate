import Foundation
@testable import DriftCore
import Testing

/// The registration contract itself — what `ToolRegistration.registerAll()`
/// owes every app shell that calls it.
///
/// This file exists because the "empty registry" bug shipped **twice**: on iOS
/// when the DriftCore migration (96e3173) moved `registerAll()` out of
/// `LocalAIService.init()` without adding the caller wiring, and on Android
/// where the shell never had the call at all (#1209) — so every Coach turn
/// answered "unknown tool" from day one of the port.
///
/// The suite could not see either one. All ~50 `registerAll()` call sites in
/// the repo are a test's own setup or an entry point, and several tests
/// self-heal (`if ToolRegistry.shared.allTools().isEmpty { ... }`), so the
/// registry is *always* populated under test and the production configuration
/// is never observed. Shell wiring is pinned per-platform instead —
/// `DriftTests/DriftAppLaunchTests.swift` for iOS,
/// `drift-android/.../DriftAndroidApp.swift` for Android. What lives here is
/// the contract both of those shells depend on.
enum ToolRegistrationContract {
    /// Tool names the `LocalAIService` system prompt hardcodes as few-shot
    /// examples (`LocalAIService.swift:67-72`). A name the prompt teaches the
    /// model to emit but nothing registers is a guaranteed user-visible
    /// "unknown tool" — the two must not drift apart.
    static let promptExamples = [
        "log_food", "food_info", "weight_info",
        "start_workout", "exercise_info", "sleep_recovery",
    ]

    /// The exact catalog size today: 24 inline registrations + 16
    /// `syncRegistration` calls, one tool each. Asserted as a floor rather
    /// than an equality only because sibling tests register temporary tools
    /// into the shared registry (`AIToolAgentLoopTests`, `ToolsJSONSchemaTests`)
    /// and can transiently inflate the count — a floor set AT the true value
    /// still fails the moment any real tool stops registering.
    static let minimumToolCount = 40
}

@MainActor
@Test func registerAllRegistersEveryPromptExampleTool() {
    ToolRegistration.registerAll()
    let registered = Set(ToolRegistry.shared.allTools().map(\.name))

    for tool in ToolRegistrationContract.promptExamples {
        #expect(registered.contains(tool),
                "LocalAIService's prompt teaches the model to emit '\(tool)' but registerAll() doesn't register it")
    }
}

@MainActor
@Test func registerAllRegistersTheFullToolCatalog() {
    ToolRegistration.registerAll()
    let count = ToolRegistry.shared.allTools().count

    #expect(count >= ToolRegistrationContract.minimumToolCount,
            "registerAll() registered only \(count) tools, expected at least \(ToolRegistrationContract.minimumToolCount)")
}

@MainActor
@Test func registerAllIsIdempotent() {
    // Shells may register more than once (iOS layers `PhotoLogTool` on top);
    // `register()` overwrites by name, so a second pass must not grow the
    // registry. No `await` between the two reads — the main actor keeps
    // sibling tests that register temporary tools from interleaving here.
    ToolRegistration.registerAll()
    let before = ToolRegistry.shared.allTools().count
    ToolRegistration.registerAll()
    let after = ToolRegistry.shared.allTools().count

    #expect(after == before, "a second registerAll() changed the registry size: \(before) → \(after)")

    // Same catalog, not just the same count — re-registering must not swap a
    // tool out for a differently-named one. (A duplicate-name check would be
    // vacuous here: the registry is a dictionary keyed by `tool.name`.)
    let registered = Set(ToolRegistry.shared.allTools().map(\.name))
    for tool in ToolRegistrationContract.promptExamples {
        #expect(registered.contains(tool), "'\(tool)' went missing after a second registerAll()")
    }
}

@MainActor
@Test func registeredToolsProduceCloudFunctionSchema() {
    // `toolsJSONString` is the single source of the function-calling schema
    // sent to Nebius, and it returns nil on an empty registry — which is why
    // #1209's Android requests carried no tool schemas at all and the model
    // invented tool names from the prompt's examples.
    ToolRegistration.registerAll()

    let schema = ToolRegistry.shared.toolsJSONString(forScreen: nil)

    #expect(schema != nil, "a populated registry must produce a non-nil cloud function schema")
    #expect(schema?.contains("log_food") == true, "the cloud schema must carry the registered tools")
}
