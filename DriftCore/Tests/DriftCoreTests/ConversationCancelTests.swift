import XCTest
@testable import DriftCore

/// Tests for cancel / never-mind / scratch-that handling in pending conversation phases.
/// All tests are deterministic — no LLM, no network.
@MainActor
final class ConversationCancelTests: XCTestCase {

    // MARK: - cancelPending() unit tests

    func testCancelPending_clearsAwaitingMealItems() {
        let state = ConversationState()
        state.phase = .awaitingMealItems(mealName: "lunch")
        state.cancelPending()
        XCTAssertEqual(state.phase, .idle)
    }

    func testCancelPending_clearsAwaitingExercises() {
        let state = ConversationState()
        state.phase = .awaitingExercises
        state.cancelPending()
        XCTAssertEqual(state.phase, .idle)
    }

    func testCancelPending_clearsPlanningMeals() {
        let state = ConversationState()
        state.phase = .planningMeals(mealName: "dinner", iteration: 1)
        state.cancelPending()
        XCTAssertEqual(state.phase, .idle)
    }

    func testCancelPending_clearsPlanningWorkout() {
        let state = ConversationState()
        state.phase = .planningWorkout(splitType: "PPL", currentDay: 2, totalDays: 6)
        state.cancelPending()
        XCTAssertEqual(state.phase, .idle)
    }

    func testCancelPending_clearsPendingIntent() {
        let state = ConversationState()
        state.phase = .awaitingMealItems(mealName: "breakfast")
        state.pendingIntent = .awaitingParam(tool: "log_food", missing: "name", partialParams: [:])
        state.cancelPending()
        XCTAssertNil(state.pendingIntent)
        XCTAssertEqual(state.phase, .idle)
    }

    // MARK: - StaticOverrides cancel matching (all phrases × all pending phases)

    func testCancel_inAwaitingMealItems_returnsResponse() {
        ConversationState.shared.phase = .awaitingMealItems(mealName: "lunch")
        defer { ConversationState.shared.phase = .idle }
        let result = StaticOverrides.match("cancel")
        guard case .response(let text) = result else {
            XCTFail("Expected .response, got \(String(describing: result))"); return
        }
        XCTAssertEqual(text, "Cancelled.")
    }

    func testNevermind_inAwaitingExercises_returnsResponse() {
        ConversationState.shared.phase = .awaitingExercises
        defer { ConversationState.shared.phase = .idle }
        let result = StaticOverrides.match("nevermind")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'nevermind'"); return
        }
        XCTAssertEqual(text, "Cancelled.")
    }

    func testNeverMindSpaced_inPendingPhase_returnsResponse() {
        ConversationState.shared.phase = .awaitingMealItems(mealName: "dinner")
        defer { ConversationState.shared.phase = .idle }
        let result = StaticOverrides.match("never mind")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'never mind'"); return
        }
        XCTAssertEqual(text, "Cancelled.")
    }

    func testScratchThat_inPendingPhase_returnsResponse() {
        ConversationState.shared.phase = .awaitingExercises
        defer { ConversationState.shared.phase = .idle }
        let result = StaticOverrides.match("scratch that")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'scratch that'"); return
        }
        XCTAssertEqual(text, "Cancelled.")
    }

    func testForgetIt_inPendingPhase_returnsResponse() {
        ConversationState.shared.phase = .awaitingMealItems(mealName: "snack")
        defer { ConversationState.shared.phase = .idle }
        let result = StaticOverrides.match("forget it")
        guard case .response(let text) = result else {
            XCTFail("Expected .response for 'forget it'"); return
        }
        XCTAssertEqual(text, "Cancelled.")
    }

    func testUndoLast_inPendingPhase_cancelsNotUndoes() {
        ConversationState.shared.phase = .awaitingMealItems(mealName: "lunch")
        defer { ConversationState.shared.phase = .idle }
        let result = StaticOverrides.match("undo last")
        guard case .response(let text) = result else {
            XCTFail("Expected .response(Cancelled.) for 'undo last' in pending phase"); return
        }
        XCTAssertEqual(text, "Cancelled.")
    }

    func testCancel_resetsPhaseToIdle() {
        ConversationState.shared.phase = .awaitingMealItems(mealName: "breakfast")
        _ = StaticOverrides.match("cancel")
        XCTAssertEqual(ConversationState.shared.phase, .idle)
    }

    // MARK: - Idle phase: cancel must NOT intercept

    func testCancel_inIdlePhase_doesNotProduceCancelledText() {
        ConversationState.shared.phase = .idle
        let result = StaticOverrides.match("cancel")
        if case .response(let text) = result {
            XCTAssertNotEqual(text, "Cancelled.", "cancel in idle should not short-circuit with Cancelled.")
        }
        // nil is also acceptable (falls through to AI pipeline)
    }

    func testUndoLast_inIdlePhase_doesNotProduceCancelledText() {
        ConversationState.shared.phase = .idle
        let result = StaticOverrides.match("undo last")
        // In idle, "undo last" must go to undo manager (.handler), NOT return "Cancelled."
        if case .response(let text) = result {
            XCTAssertNotEqual(text, "Cancelled.", "undo last in idle must use undo manager")
        }
    }

    // MARK: - All pending phases × all phrases

    func testAllPhrasings_inAllPendingPhases() {
        let phases: [ConversationState.Phase] = [
            .awaitingMealItems(mealName: "lunch"),
            .awaitingExercises,
            .planningMeals(mealName: "dinner", iteration: 0),
            .planningWorkout(splitType: "PPL", currentDay: 1, totalDays: 6),
        ]
        let phrases = ["cancel", "nevermind", "never mind", "scratch that", "forget it"]
        for phase in phases {
            for phrase in phrases {
                ConversationState.shared.phase = phase
                let result = StaticOverrides.match(phrase)
                guard case .response(let text) = result else {
                    XCTFail("'\(phrase)' in \(phase) should return .response"); continue
                }
                XCTAssertEqual(text, "Cancelled.", "'\(phrase)' in \(phase) should return Cancelled.")
                XCTAssertEqual(ConversationState.shared.phase, .idle, "phase should be idle after '\(phrase)'")
            }
        }
    }
}
