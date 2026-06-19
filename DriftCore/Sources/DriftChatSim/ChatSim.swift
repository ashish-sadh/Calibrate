import Foundation
import DriftCore

/// The per-turn engine. Mirrors the DriftCore-reachable subset of the iOS
/// `sendMessage` dispatch:
///   normalize → Phase 1 (StaticOverrides.match) → Phase 8 (AIToolAgent.run)
///
/// It does NOT cover the iOS-resident Phases 0.5–7 (multi-turn pick handlers,
/// food-intent parsing, confirmations, clarifications) — those live in
/// `AIChatViewModel` and aren't in DriftCore yet (see the v2 ChatEngine plan).
/// The boot banner states this so we never mistake coverage for completeness.
@MainActor
enum ChatSim {

    static var backendLabel = "none"

    // MARK: - DB snapshot (for before→after effect diffs)

    struct DBSnapshot {
        let calories, protein, carbs, fat, fiber: Double
        let foodEntries, weightEntries: Int

        static func capture() -> DBSnapshot {
            let db = AppDatabase.shared
            let today = DateFormatters.todayString
            let n = try? db.fetchDailyNutrition(for: today)
            return DBSnapshot(
                calories: n?.calories ?? 0,
                protein: n?.proteinG ?? 0,
                carbs: n?.carbsG ?? 0,
                fat: n?.fatG ?? 0,
                fiber: n?.fiberG ?? 0,
                foodEntries: (try? db.fetchFoodEntries(for: today))?.count ?? 0,
                weightEntries: (try? db.fetchWeightEntries())?.count ?? 0
            )
        }
    }

    // MARK: - Turn result

    struct TurnTrace {
        var input = ""
        var normalized = ""
        var phaseBefore = ""
        var staticOverride = ""
        var route = ""            // "static" | "agent" | "deterministic-only"
        var agentSteps: [String] = []
        var toolsCalled: [String] = []
        var clarification: [String]? = nil
        var action: String? = nil
        var response = ""
        var didFail = false
        var phaseAfter = ""
        var dbBefore = DBSnapshot.capture()
        var dbAfter = DBSnapshot.capture()
        var latencyMs = 0
    }

    // MARK: - Run one turn

    /// `allowAgent` is false in deterministic-only mode (no backend installed):
    /// static overrides + tool execution still run, but Phase 8 is skipped.
    static func runTurn(_ raw: String, screen: AIScreen, history: String, allowAgent: Bool) async -> TurnTrace {
        let t0 = CFAbsoluteTimeGetCurrent()
        var trace = TurnTrace()
        trace.input = raw
        trace.normalized = InputNormalizer.normalize(raw)
        let lower = trace.normalized.lowercased()
        trace.phaseBefore = describePhase(ConversationState.shared.phase)
        trace.dbBefore = DBSnapshot.capture()

        if let result = StaticOverrides.match(lower) {
            trace.route = "static"
            switch result {
            case .response(let text):
                trace.staticOverride = "MATCH .response"
                trace.response = text
            case .toolCall(let call):
                trace.staticOverride = "MATCH .toolCall(\(call.tool))"
                let r = await ToolRegistry.shared.execute(call)
                trace.toolsCalled = [call.tool]
                trace.response = String(describing: r)
            case .uiAction(let action, let msg):
                trace.staticOverride = "MATCH .uiAction"
                trace.action = String(describing: action)
                trace.response = msg ?? "(opens UI: \(action))"
            case .handler(let fn):
                trace.staticOverride = "MATCH .handler"
                trace.response = fn()
            case .helpCard:
                trace.staticOverride = "MATCH .helpCard"
                trace.response = "(capability help card)"
            }
        } else if allowAgent {
            trace.staticOverride = "no-match → agent"
            trace.route = "agent"
            let sink = StepSink()
            let out = await AIToolAgent.run(
                message: trace.normalized,
                screen: screen,
                history: history,
                isLargeModel: LocalAIService.shared.isLargeModel,
                onStep: { sink.steps.append($0) },
                onToken: { _ in }
            )
            trace.agentSteps = sink.steps
            trace.response = out.text
            trace.toolsCalled = out.toolsCalled
            trace.didFail = out.didFail
            trace.clarification = out.clarificationOptions?.map { "\($0.id)) \($0.label)" }
            trace.action = out.action.map { String(describing: $0) }
        } else {
            trace.staticOverride = "no-match"
            trace.route = "deterministic-only (no backend — Phase 8 skipped)"
            trace.response = "[no backend installed: this turn would go to the LLM agent]"
        }

        trace.dbAfter = DBSnapshot.capture()
        trace.phaseAfter = describePhase(ConversationState.shared.phase)
        trace.latencyMs = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        return trace
    }

    // MARK: - Phase helpers (for the :phase repro meta-command + trace)

    static func describePhase(_ p: ConversationState.Phase) -> String {
        switch p {
        case .idle: return "idle"
        case .awaitingMealItems(let m): return "awaitingMealItems(\(m))"
        case .awaitingExercises: return "awaitingExercises"
        case .planningMeals(let m, let i): return "planningMeals(\(m), iter \(i))"
        case .planningWorkout(let s, let d, let t): return "planningWorkout(\(s), day \(d)/\(t))"
        case .awaitingClarification(let opts): return "awaitingClarification(\(opts.count) opts)"
        }
    }

    /// Parses "planningMeals:lunch:0" / "awaitingMealItems:lunch" / "idle".
    static func parsePhase(_ spec: String) -> ConversationState.Phase? {
        let parts = spec.split(whereSeparator: { $0 == ":" || $0 == " " }).map(String.init)
        guard let head = parts.first else { return nil }
        switch head {
        case "idle": return .idle
        case "awaitingExercises": return .awaitingExercises
        case "awaitingMealItems": return .awaitingMealItems(mealName: parts.count > 1 ? parts[1] : "lunch")
        case "planningMeals":
            return .planningMeals(mealName: parts.count > 1 ? parts[1] : "lunch",
                                  iteration: parts.count > 2 ? (Int(parts[2]) ?? 0) : 0)
        default: return nil
        }
    }
}

/// Collects `onStep` markers from the non-escaping agent callback.
final class StepSink: @unchecked Sendable {
    var steps: [String] = []
}
