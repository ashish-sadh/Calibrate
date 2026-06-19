import Foundation
import DriftCore

/// Renders a turn trace so a routing bug is visible at the exact stage it
/// occurs. The load-bearing rows are `phase_before` / `static_override` /
/// `phase_after` (the bare-"1" class dies in static_override while a phase is
/// pending) and the `db_effects` before→after diff (silent / missing writes).
enum TracePrinter {

    static func human(_ t: ChatSim.TurnTrace) -> String {
        var out = "\n━━━ TURN ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        out += row("input", "\"\(t.input)\"")
        if t.normalized != t.input { out += row("normalized", "\"\(t.normalized)\"") }
        out += row("route", t.route)
        out += row("phase_before", t.phaseBefore)
        out += row("static_override", t.staticOverride)
        if !t.agentSteps.isEmpty { out += row("agent_steps", t.agentSteps.joined(separator: " → ")) }
        out += row("tools_called", t.toolsCalled.isEmpty ? "-" : t.toolsCalled.joined(separator: ", "))
        if let c = t.clarification, !c.isEmpty { out += row("clarification", c.joined(separator: "  ")) }
        if let a = t.action { out += row("action", a) }
        out += "  db_effects     :\n"
        out += diff("calories", t.dbBefore.calories, t.dbAfter.calories)
        out += diff("protein_g", t.dbBefore.protein, t.dbAfter.protein)
        out += diff("carbs_g", t.dbBefore.carbs, t.dbAfter.carbs)
        out += diff("fat_g", t.dbBefore.fat, t.dbAfter.fat)
        out += diffInt("food(today)", t.dbBefore.foodEntries, t.dbAfter.foodEntries)
        out += diffInt("weight_rows", t.dbBefore.weightEntries, t.dbAfter.weightEntries)
        out += row("response", "\"\(t.response)\"")
        out += row("did_fail", t.didFail ? "TRUE ⚠️" : "false")
        out += row("phase_after", t.phaseAfter)
        out += row("latency_ms", "\(t.latencyMs)")
        out += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        return out
    }

    static func json(_ t: ChatSim.TurnTrace) -> String {
        let dict: [String: Any] = [
            "input": t.input,
            "normalized": t.normalized,
            "route": t.route,
            "phase_before": t.phaseBefore,
            "static_override": t.staticOverride,
            "agent_steps": t.agentSteps,
            "tools_called": t.toolsCalled,
            "clarification": t.clarification ?? [],
            "action": t.action ?? "",
            "response": t.response,
            "did_fail": t.didFail,
            "phase_after": t.phaseAfter,
            "latency_ms": t.latencyMs,
            "db_before": snap(t.dbBefore),
            "db_after": snap(t.dbAfter),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private static func snap(_ s: ChatSim.DBSnapshot) -> [String: Any] {
        ["calories": s.calories, "protein_g": s.protein, "carbs_g": s.carbs,
         "fat_g": s.fat, "fiber_g": s.fiber, "food_entries": s.foodEntries,
         "weight_entries": s.weightEntries]
    }

    private static func row(_ label: String, _ value: String) -> String {
        "  \(label.padding(toLength: 15, withPad: " ", startingAt: 0)) : \(value)\n"
    }

    private static func diff(_ label: String, _ a: Double, _ b: Double) -> String {
        let changed = abs(a - b) > 0.001
        let base = "     \(label.padding(toLength: 11, withPad: " ", startingAt: 0)): \(fmt(a))"
        return changed ? "\(base) → \(fmt(b))   *** WRITE ***\n" : "\(base)\n"
    }

    private static func diffInt(_ label: String, _ a: Int, _ b: Int) -> String {
        let base = "     \(label.padding(toLength: 11, withPad: " ", startingAt: 0)): \(a)"
        return a != b ? "\(base) → \(b)   *** WRITE ***\n" : "\(base)\n"
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.0f", v) }
}
