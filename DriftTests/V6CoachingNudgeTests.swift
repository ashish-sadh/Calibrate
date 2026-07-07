import XCTest
@testable import Drift
import DriftCore

/// Tier-1 tests for `V6CoachingNudge` — the V6 Dashboard coaching nudge card
/// (anatomy step 6 of `v6-today.jsx`). Pins the pure `payload(from:aiEnabled:)`
/// factory so the priority + icon + dismissal mapping stays stable as
/// `BehaviorInsightService.computeProactiveAlerts(...)` evolves underneath.
///
/// We test the payload factory rather than the SwiftUI view tree — the
/// rendering layer is dumb (already covered by `#Preview`) and the only logic
/// worth pinning lives in the factory's "pick first alert, propagate icon,
/// gate the Ask AI pill on `aiEnabled`" contract.
@MainActor
final class V6CoachingNudgeTests: XCTestCase {

    // MARK: - Empty / non-empty alerts

    func testPayloadIsNilWhenNoAlerts() {
        // Empty list → the dashboard renders no card at all (no empty shell).
        let payload = V6CoachingNudge.payload(from: [], aiEnabled: false)
        XCTAssertNil(payload, "Empty alerts must yield nil so the dashboard skips the card entirely")
    }

    func testPayloadEchoesSingleAlertFields() {
        let alert = BehaviorInsight(
            icon: "drop.fill",
            title: "Glucose ran high after lunch",
            detail: "Spike of 38 mg/dL above baseline — try a 10-minute walk.",
            isPositive: false,
            dismissKey: "glucose_spike"
        )
        let payload = V6CoachingNudge.payload(from: [alert], aiEnabled: false)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.icon, "drop.fill")
        XCTAssertEqual(payload?.title, "Glucose ran high after lunch")
        XCTAssertEqual(payload?.detail, "Spike of 38 mg/dL above baseline — try a 10-minute walk.")
        XCTAssertEqual(payload?.dismissKey, "glucose_spike")
    }

    // MARK: - Priority

    func testPayloadPicksFirstAlertFromMultipleByServicePriorityOrder() {
        // `computeProactiveAlerts(...)` appends in fixed priority order
        // protein → glucose → supplement → workout → logging. The card
        // surfaces only the top-priority one, so test order matches the
        // intended ranking.
        let protein = BehaviorInsight(
            icon: "fork.knife",
            title: "Protein below target 3 days running",
            detail: "Avg 90g vs goal 130g.",
            isPositive: false,
            dismissKey: "protein_streak"
        )
        let glucose = BehaviorInsight(
            icon: "drop.fill",
            title: "Glucose ran high after lunch",
            detail: "Spike of 38 mg/dL above baseline.",
            isPositive: false,
            dismissKey: "glucose_spike"
        )
        let payload = V6CoachingNudge.payload(from: [protein, glucose], aiEnabled: false)
        XCTAssertEqual(payload?.title, protein.title,
                       "Multi-alert payload must pick the first (highest-priority) alert from the service-ordered array")
        XCTAssertEqual(payload?.icon, "fork.knife",
                       "Icon must come from the chosen alert, not from a downstream alert")
    }

    // MARK: - Ask AI gating

    func testAskAIPillHiddenWhenAIDisabled() {
        let alert = BehaviorInsight(
            icon: "fork.knife", title: "t", detail: "d",
            isPositive: false, dismissKey: nil
        )
        let payload = V6CoachingNudge.payload(from: [alert], aiEnabled: false)
        XCTAssertEqual(payload?.showAskAI, false,
                       "With AI beta off the Ask AI pill must NOT render — matches the dashboard nav-bar AI toggle gating")
    }

    func testAskAIPillShownWhenAIEnabled() {
        let alert = BehaviorInsight(
            icon: "fork.knife", title: "t", detail: "d",
            isPositive: false, dismissKey: nil
        )
        let payload = V6CoachingNudge.payload(from: [alert], aiEnabled: true)
        XCTAssertEqual(payload?.showAskAI, true,
                       "With AI beta on the Ask AI pill renders so the user can deep-dive on the nudge")
    }

    // MARK: - Dismissal contract

    func testPayloadCarriesDismissKeyWhenAlertProvidesOne() {
        let dismissible = BehaviorInsight(
            icon: "drop.fill", title: "t", detail: "d",
            isPositive: false, dismissKey: "glucose_spike"
        )
        let payload = V6CoachingNudge.payload(from: [dismissible], aiEnabled: false)
        XCTAssertEqual(payload?.dismissKey, "glucose_spike",
                       "Dismiss key must propagate so the dashboard wires the '×' to viewModel.dismissProactiveAlert(key:)")
    }

    func testPayloadHasNoDismissKeyForCriticalAlerts() {
        // Critical-class alerts (no dismissKey on BehaviorInsight) must
        // render WITHOUT the '×' so the user can't snooze them. The view
        // layer hides the dismiss button when dismissKey is nil; here we
        // just confirm the payload propagates that nil through.
        let critical = BehaviorInsight(
            icon: "exclamationmark.octagon.fill",
            title: "Critical", detail: "Cannot be dismissed",
            isPositive: false, dismissKey: nil
        )
        let payload = V6CoachingNudge.payload(from: [critical], aiEnabled: false)
        XCTAssertNil(payload?.dismissKey,
                     "Critical alerts (nil dismissKey) must carry nil through so the '×' is hidden")
    }

    // MARK: - Accessibility

    func testAccessibilityLabelComposition() {
        let alert = BehaviorInsight(
            icon: "fork.knife",
            title: "Protein below target 3 days running",
            detail: "Avg 90g vs goal 130g.",
            isPositive: false,
            dismissKey: "protein_streak"
        )
        guard let payload = V6CoachingNudge.payload(from: [alert], aiEnabled: false) else {
            XCTFail("Expected non-nil payload for single alert")
            return
        }
        XCTAssertTrue(payload.accessibilityLabel.contains(alert.title),
                      "Accessibility label must include the title so VoiceOver reads the nudge headline first")
        XCTAssertTrue(payload.accessibilityLabel.contains(alert.detail),
                      "Accessibility label must include the detail so VoiceOver reads the actionable context")
        XCTAssertTrue(payload.accessibilityLabel.lowercased().contains("coaching"),
                      "Label should announce itself as a coaching nudge so it's not mistaken for a generic card")
    }

    // MARK: - Ask AI action (#928)

    func testAskAIPostsOpenDriftCoachSeededWithNudgeContext() {
        // The Ask AI pill must present the chat surface: askAI(payload:) posts
        // `.openDriftCoach`, the exact notification ContentView observes to
        // flip `showingDriftCoach` and present DriftCoachSheet(prefill:). The
        // V6 `.expandAIAssistant` post it replaced had no listener — a silent
        // no-op pill. Asserts the name AND that the prefill carries the
        // nudge's real data, not a cold open.
        let payload = V6CoachingNudgePayload(
            icon: "pills.fill",
            title: "Supplements missed",
            detail: "Creatine, Electrolytes — not taken in 3+ days",
            dismissKey: "supplements_missed",
            showAskAI: true
        )
        let center = NotificationCenter()
        var received: Notification?
        let token = center.addObserver(
            forName: .openDriftCoach, object: nil, queue: nil
        ) { received = $0 }
        defer { center.removeObserver(token) }

        V6CoachingNudge.askAI(payload: payload, center: center)

        XCTAssertNotNil(received, "Ask AI must post .openDriftCoach — the notification ContentView maps to presenting the Coach sheet")
        let prefill = received?.userInfo?["prefill"] as? String
        XCTAssertNotNil(prefill, "Ask AI must seed the Coach via userInfo[\"prefill\"] — ContentView's contract")
        XCTAssertTrue(prefill?.contains("Creatine") == true,
                      "Seed must carry the actual missed supplement names so the Coach's first answer uses real data")
        XCTAssertTrue(prefill?.contains("3+ days") == true,
                      "Seed must carry how long the supplements have been missed")
        XCTAssertEqual(received?.userInfo?["autoSubmit"] as? Bool, true,
                       "#936: Ask AI must auto-submit the seeded turn, not leave it in the input")
    }

    func testOpenDriftCoachNameMatchesContentViewContract() {
        // Mirrors LogMealSheetTests' rawValue pin: DashboardView posts by
        // Notification.Name while ContentView observes the same constant —
        // pinning the string catches an accidental rename of either side.
        XCTAssertEqual(Notification.Name.openDriftCoach.rawValue, "drift.openDriftCoach")
    }
}
