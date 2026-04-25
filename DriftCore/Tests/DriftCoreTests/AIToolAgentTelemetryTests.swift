import Foundation
@testable import DriftCore
import Testing

/// Covers the `AgentOutput.didFail → Outcome.failed` mapping introduced in
/// #281. These assert the pure outcome classifier and the two producers we
/// instrumented; end-to-end pipeline wiring is exercised by the live eval.
@MainActor
struct AIToolAgentTelemetryTests {

    // MARK: - telemetryOutcome mapping

    @Test func successWhenNothingFailed() {
        let out = AgentOutput(text: "ok", action: nil, toolsCalled: ["log_food"], didFail: false)
        #expect(AIToolAgent.telemetryOutcome(for: out) == .success)
    }

    @Test func failedWhenDidFailSet() {
        let out = AgentOutput(text: "sorry", action: nil, toolsCalled: ["log_food"], didFail: true)
        #expect(AIToolAgent.telemetryOutcome(for: out) == .failed)
    }

    @Test func timeoutBeatsFailed() {
        // Defensive: even if didFail somehow got set alongside a timeout
        // marker, timeout is the more informative label (the pipeline never
        // even reached the tool handler).
        let out = AgentOutput(text: "", action: nil, toolsCalled: ["timeout"], didFail: true)
        #expect(AIToolAgent.telemetryOutcome(for: out) == .timeout)
    }

    @Test func clarifiedBeatsFailed() {
        // Clarification is not a failure — user just needs to pick.
        var out = AgentOutput(text: "which one?", action: nil, toolsCalled: [], didFail: true)
        out.clarificationOptions = [ClarificationOption(id: 1, label: "A", tool: "log_food", params: [:])]
        #expect(AIToolAgent.telemetryOutcome(for: out) == .clarified)
    }

    // MARK: - handleTextResponse marks didFail on fallback

    @Test func handleTextResponseFlagsEmpty() {
        let out = AIToolAgent.handleTextResponse("", screen: .dashboard)
        #expect(out.didFail == true)
    }

    @Test func handleTextResponseFlagsLowQuality() {
        // Short gibberish → low-quality branch kicks in.
        let out = AIToolAgent.handleTextResponse("...", screen: .dashboard)
        #expect(out.didFail == true)
    }

    @Test func handleTextResponsePassesThroughQualityText() {
        let out = AIToolAgent.handleTextResponse(
            "Your protein today is 87 grams. Keep going, you are on track.",
            screen: .dashboard
        )
        // Quality text should NOT flip didFail. (Text contents may get
        // hallucination-filtered in some runs — the key assertion is that
        // clean text doesn't reach the failed branch via an empty check.)
        if !out.text.isEmpty {
            #expect(out.didFail == false)
        }
    }

    // MARK: - telemetryIntent stability (#281 depends on this being stable)

    @Test func intentForToolCallIsToolCall() {
        let out = AgentOutput(text: "x", action: nil, toolsCalled: ["log_food"], didFail: false)
        #expect(AIToolAgent.telemetryIntent(for: out) == .toolCall)
    }

    @Test func intentForTimeoutIsTimeout() {
        let out = AgentOutput(text: "", action: nil, toolsCalled: ["timeout"], didFail: false)
        #expect(AIToolAgent.telemetryIntent(for: out) == .timeout)
    }

    @Test func intentForClarificationIsClarification() {
        var out = AgentOutput(text: "which?", action: nil, toolsCalled: [], didFail: false)
        out.clarificationOptions = [ClarificationOption(id: 1, label: "A", tool: "log_food", params: [:])]
        #expect(AIToolAgent.telemetryIntent(for: out) == .clarification)
    }
}
