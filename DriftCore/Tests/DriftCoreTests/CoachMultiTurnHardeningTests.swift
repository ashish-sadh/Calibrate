import XCTest
@testable import DriftCore

/// Tier 0 — pure logic + seeded AppDatabase.shared, no LLM, no simulator.
///
/// Launch-hardening regression guards for Drift Coach multi-turn behaviour
/// (#892, epic #909). Two invariants that separate "works" from "flawless":
///   1. Conversation context HOLDS across turns — the user's earlier statements
///      thread forward into the next turn's prompt AND the coach references the
///      user's own logged data.
///   2. A clarification ACTS on the user's answer rather than re-asking (anti-loop).
///
/// Tier-0 by design: #892's Done-When criterion-1 verify and the epic-#909
/// criterion-2 gate both grep DriftCore/Tests/DriftCoreTests/ alongside
/// DriftLLMEvalMacOS/, so the per-commit regression guard is a fast deterministic
/// predicate (~2s). The live-Nebius multi-turn cases already exist at Tier-3
/// (DriftLLMEvalMacOS/MultiTurnRegressionTests.swift + PipelineE2EEval.swift, run
/// pre-TestFlight) — keeping the commit gate off a multi-minute cloud run is the
/// intended split. These tests HARDEN the existing plumbing; no source changes,
/// no new data sources (launch scope).
///
/// Run: `cd DriftCore && swift test --filter CoachMultiTurnHardeningTests`
final class CoachMultiTurnHardeningTests: XCTestCase {

    // MARK: - Context holds across turns (#892 criterion 2)

    /// Two-part guard for "conversation context holds across turns":
    ///  (A) the user's distinctive turn-1 statement threads forward into a later
    ///      turn's composed prompt — via ConversationHistoryBuilder (the Q/A window)
    ///      AND IntentClassifier.buildUserMessage (the "Chat:" prefix);
    ///  (B) the coach references the user's OWN logged data — AIContextBuilder
    ///      .foodContext() surfaces a meal the user logged today.
    /// No new data sources are introduced — this locks the EXISTING injection plumbing.
    @MainActor
    func testContextHoldsAcrossTurns() throws {
        // History injection is gated on this pref (default true). Pin it + restore so
        // the test is order-independent of sibling XCTest classes that toggle it
        // (e.g. CrossSessionHistoryTests.testRespectsDisabledPref sets it false).
        let originalHistoryPref = Preferences.conversationHistoryEnabled
        Preferences.conversationHistoryEnabled = true
        defer { Preferences.conversationHistoryEnabled = originalHistoryPref }

        // (A) History holds across a 4-turn chain: a distinctive turn-1 fact must
        //     survive into the serialized history the next turn sees.
        let turns = [
            HistoryTurn(role: .user, text: "my goal is to cut to 165 lbs"),
            HistoryTurn(role: .assistant, text: "Got it — targeting 165 lbs."),
            HistoryTurn(role: .user, text: "logged paneer tikka for lunch"),
            HistoryTurn(role: .assistant, text: "Logged paneer tikka.")
        ]
        let history = ConversationHistoryBuilder.build(turns: turns, maxTokens: 800)
        XCTAssertTrue(history.contains("165 lbs"),
            "Turn-1 goal must persist in the history window the next turn sees")
        XCTAssertTrue(history.contains("paneer tikka"),
            "Later-turn food log must also be in the carried history")

        // The composed message for the NEXT turn must thread that history under "Chat:".
        let composed = IntentClassifier.buildUserMessage(
            message: "am i on track?",
            history: history
        )
        XCTAssertTrue(composed.contains("Chat:"),
            "History must thread under the Chat: prefix on the follow-up turn")
        XCTAssertTrue(composed.contains("165 lbs"),
            "The user's turn-1 goal must be visible to the model on the follow-up turn")
        XCTAssertTrue(composed.contains("am i on track?"),
            "The current question must be present in the composed message")

        // (B) The coach references the user's OWN logged data via AIContextBuilder.
        //     Seed a uniquely-named meal in AppDatabase.shared (UUID suffix → no
        //     collision with parallel tests), assert foodContext() surfaces it, clean up.
        let today = DateFormatters.todayString
        let uniqueFood = "CtxHoldPaneer\(UUID().uuidString.prefix(8))"
        var mealLog = MealLog(date: today, mealType: "lunch")
        try AppDatabase.shared.saveMealLog(&mealLog)
        let mealLogId = try XCTUnwrap(mealLog.id, "seeded meal log must have an id")
        defer { try? AppDatabase.shared.deleteMealLog(id: mealLogId) }

        var entry = FoodEntry(
            mealLogId: mealLogId, foodName: String(uniqueFood), servingSizeG: 100, servings: 1,
            calories: 250, proteinG: 18, carbsG: 8, fatG: 16, fiberG: 2,
            loggedAt: ISO8601DateFormatter().string(from: Date()), date: today, mealType: "lunch"
        )
        try AppDatabase.shared.saveFoodEntry(&entry)

        let context = AIContextBuilder.foodContext()
        XCTAssertTrue(context.contains(String(uniqueFood)),
            "AIContextBuilder.foodContext() must reference the user's own logged meal — context injection holds across turns")
    }

    // MARK: - Clarification anti-loop (#892 criterion 1)

    /// "Clarifications act on the user's answer rather than re-asking."
    /// The anti-loop invariant has two halves, both deterministic (#226/#242):
    ///  (1) every clarification option carries a concrete executable tool+params, so
    ///      the dispatcher EXECUTES the picked option and never re-runs the clarifier
    ///      (#226 carry-the-tool: resolution can't bounce back into a clarifier);
    ///  (2) once the user supplies structure (a quantity or meal-time), the builder
    ///      returns nil — it does NOT re-ask — and the params are complete enough to act.
    func testClarificationDoesNotReLoop() throws {
        // A genuinely-ambiguous bare noun produces options...
        let options = try XCTUnwrap(
            ClarificationBuilder.buildOptions(for: "biryani"),
            "A bare ambiguous food noun should produce clarification options")
        XCTAssertGreaterThanOrEqual(options.count, 2, "Ambiguous input should offer ≥2 reads")
        // ...and EACH option carries a concrete tool + params (#226 carry-the-tool):
        // resolving an option dispatches that tool directly — it can never bounce back
        // into the clarifier, so the clarification can't loop.
        for opt in options {
            XCTAssertFalse(opt.tool.isEmpty,
                "Option '\(opt.label)' must carry an executable tool so resolution never re-clarifies")
            XCTAssertFalse(opt.params.isEmpty,
                "Option '\(opt.label)' must carry params so the tool can execute without a re-ask")
        }

        // Once the user ANSWERS with structure, the builder must NOT re-ask.
        XCTAssertNil(ClarificationBuilder.buildOptions(for: "2 biryani"),
            "A quantified answer carries enough structure — must act, not re-clarify")
        XCTAssertNil(ClarificationBuilder.buildOptions(for: "biryani for lunch"),
            "A meal-time answer carries enough structure — must act, not re-clarify")

        // ...and the resolved answer's params are complete enough to execute → act, don't loop.
        XCTAssertTrue(
            ClarificationBuilder.hasCompleteParams(tool: "log_food",
                                                   params: ["name": "biryani", "servings": "2"]),
            "A named food with a quantity is executable — the coach acts instead of re-asking")
    }
}
