import XCTest
import DriftCore
import Foundation

/// Live grounding eval for the proactive "Today's Brief" narrator (epic #875).
///
/// Measures how often the real model, narrating a deterministic `BriefInput`, stays GROUNDED —
/// i.e. introduces no number the deterministic layer didn't compute (the over-claim /
/// 2-point-extrapolation bug class, #801). `BriefNarrator`'s Tier-0 `isGrounded` predicate already
/// guards the commit path on canned output; this is the live counterpart.
///
/// Gated behind `DRIFT_DEEP_EVAL=1` so it never runs in CI — the ~12-min real-Gemma RUN is #885's
/// job (off the headless commit path; a per-task commit gate here previously caused a death-loop).
/// This file (the committed gold set + the named `groundingThreshold` constant) ships in the SAME
/// PR as the narrator per tenet #13.
///
/// Requires: ~/drift-state/models/gemma-4-e2b-q4_k_m.gguf  (bash scripts/download-models.sh)
/// Run:      DRIFT_DEEP_EVAL=1 xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
///             -only-testing:DriftLLMEvalMacOS/BriefNarratorGroundingEval
final class BriefNarratorGroundingEval: XCTestCase {

    /// Single source of truth for the green-light bar. #885 records the measured live grounded rate
    /// against this constant in Docs/decisions.md; #879 only wires the user-facing surface if the
    /// measured rate ≥ this value. Quote this constant — never restate a bare literal.
    static let groundingThreshold = 0.75

    static let gemmaPath = URL.homeDirectory.appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")
    nonisolated(unsafe) static var backend: LlamaCppBackend?

    // MARK: - Gold set (Indian-first; every signal carries the only numbers the narrator may state)

    /// A case is the deterministic `BriefInput` the narrator must stay grounded to.
    private struct GroundingCase {
        let name: String
        let input: BriefInput
    }

    private func goldSet() -> [GroundingCase] {
        func alert(_ id: String, _ title: String, _ detail: String, _ dir: BriefSignal.GoalDirection) -> BriefSignal {
            BriefSignal(id: id, source: .alert, title: title, detail: detail, goalDirection: dir)
        }
        func pattern(_ id: String, _ title: String, _ detail: String) -> BriefSignal {
            BriefSignal(id: id, source: .pattern, title: title, detail: detail, goalDirection: .neutral)
        }
        func tool(_ id: String, _ title: String, _ detail: String) -> BriefSignal {
            BriefSignal(id: id, source: .tool, title: title, detail: detail, goalDirection: .neutral)
        }
        func input(_ signals: [BriefSignal]) -> BriefInput {
            BriefInput(signals: signals, isThinData: false, dataDayCount: 21)
        }

        return [
            GroundingCase(name: "dal-paneer protein dip", input: input([
                alert("protein-low", "Protein below target",
                      "Protein from dal and paneer averaged 48 g over the last 3 days, under your 90 g goal.", .against),
                pattern("pattern-protein-sleep", "Protein ↔ Sleep",
                        "Sleep dropped to 6 hours on those same 3 days."),
            ])),
            GroundingCase(name: "roti carbs vs glucose", input: input([
                pattern("pattern-carbs-glucose", "Carbs ↔ Glucose",
                        "Glucose rose about 35 mg/dL within 2 hours of roti-heavy dinners."),
                tool("weight-trend", "Weight trend",
                     "At the current pace you reach your goal weight in about 9 weeks."),
            ])),
            GroundingCase(name: "idli breakfast streak", input: input([
                alert("logging-streak", "Logging streak",
                      "You logged breakfast 12 days running — mostly idli and sambar.", .aligned),
            ])),
            GroundingCase(name: "fiber from sabzi low", input: input([
                alert("fiber-low", "Fiber below target",
                      "Fiber averaged 14 g this week against a 30 g goal — light on sabzi and dal.", .against),
                tool("food-timing", "Late dinners",
                     "Dinner landed after 10 PM on 4 of the last 7 days."),
            ])),
            GroundingCase(name: "biryani-heavy weekend", input: input([
                pattern("pattern-calories-weight", "Calories ↔ Weight",
                        "Weekend intake ran 700 kcal above weekdays, tracking with a 0.4 kg uptick."),
            ])),
            GroundingCase(name: "supplement adherence", input: input([
                alert("supplement-gap", "Vitamin D gaps",
                      "You took vitamin D on 9 of the last 14 days.", .against),
                pattern("pattern-protein-recovery", "Protein ↔ Recovery",
                        "Recovery scores were higher on the days protein cleared 100 g."),
            ])),
            GroundingCase(name: "thin-but-multi-signal", input: input([
                alert("water-low", "Hydration low",
                      "You averaged 1.2 L of water daily this week, under the 3 L goal.", .against),
                tool("weight-trend", "Weight trend",
                     "Weight is flat over the last 10 days — no clear trend yet."),
            ])),
        ]
    }

    // MARK: - Eval

    func testBriefNarratorLiveGroundingRate() async throws {
        guard ProcessInfo.processInfo.environment["DRIFT_DEEP_EVAL"] == "1" else {
            throw XCTSkip("Set DRIFT_DEEP_EVAL=1 to run the BriefNarrator live grounding eval (#885)")
        }
        let backend = try loadBackend()

        var grounded = 0
        var total = 0
        var caseMisses: [String] = []

        for c in goldSet() {
            let prompt = BriefNarrator.buildPrompt(from: c.input)
            let raw = await backend.respond(to: prompt, systemPrompt: BriefNarrator.systemPrompt)
            let report = BriefNarrator.groundingReport(raw: raw, input: c.input)
            grounded += report.grounded
            total += report.total
            if report.total == 0 || report.grounded < report.total {
                caseMisses.append("\(c.name) [\(report.grounded)/\(report.total)]")
            }
        }

        let rate = total > 0 ? Double(grounded) / Double(total) : 0
        let pct = Int(rate * 100)
        print("📊 BriefNarrator grounded rate: \(grounded)/\(total) (\(pct)%) vs threshold \(Self.groundingThreshold)")
        if !caseMisses.isEmpty {
            print("⚠️ Cases with ungrounded or empty output: \(caseMisses.joined(separator: ", "))")
        }

        XCTAssertGreaterThanOrEqual(
            rate, Self.groundingThreshold,
            "BriefNarrator grounded rate \(pct)% below groundingThreshold \(Int(Self.groundingThreshold * 100))% — narrator is inventing numbers. Do NOT green-light #879; file a fix-forward prompt/parse task under #875."
        )
    }

    // MARK: - Backend

    private func loadBackend() throws -> LlamaCppBackend {
        if let b = Self.backend { return b }
        guard FileManager.default.fileExists(atPath: Self.gemmaPath.path) else {
            throw XCTSkip("Gemma 4 model not found at \(Self.gemmaPath.path) — run bash scripts/download-models.sh")
        }
        let b = LlamaCppBackend(modelPath: Self.gemmaPath, threads: 6)
        try? b.loadSync()
        guard b.isLoaded else {
            throw XCTSkip("Gemma 4 failed to load — check model file integrity")
        }
        Self.backend = b
        return b
    }
}
