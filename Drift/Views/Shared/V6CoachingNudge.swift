import SwiftUI
import DriftCore

/// V6 Dashboard coaching nudge — a single friendly card that replaces the
/// previous N-card `ForEach(viewModel.proactiveAlerts)` stack per
/// `Docs/design-references/v6-2026-05-14/v6/v6-today.jsx` anatomy step 6.
///
/// V6 makes coaching a single calm moment, not a wall: only the topmost-priority
/// alert renders. The 36×36 accent-soft circle holds an SF Symbol that maps from
/// the underlying `BehaviorInsight.icon`; the title runs in the display weight
/// (rounded, semibold, 15pt) and the detail in the secondary sans body. A
/// trailing "Ask AI" ghost pill (gated on the AI-beta toggle, same way the
/// dashboard nav-bar AI switch is gated) and an optional "×" dismiss control
/// round out the card.
///
/// The view is intentionally dumb: all decision-making (which alert wins, what
/// the icon should be, whether AI is enabled) flows in via a pre-formatted
/// `V6CoachingNudgePayload`. The pure `payload(from:aiEnabled:)` factory is
/// `static` so tier-1 tests can pin the priority + icon-mapping rules without
/// instantiating the SwiftUI view, matching the same factory-then-render
/// discipline as `TodayDonutView`.
struct V6CoachingNudge: View {
    let payload: V6CoachingNudgePayload
    let onAskAI: () -> Void
    let onDismiss: (() -> Void)?

    init(
        payload: V6CoachingNudgePayload,
        onAskAI: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        self.payload = payload
        self.onAskAI = onAskAI
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: payload.icon)
                .font(.system(size: Theme.FontSize.base, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accent.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(payload.title)
                    .font(.system(size: Theme.FontSize.subheadline, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(payload.detail)
                    .font(.system(size: Theme.FontSize.footnote))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                if payload.showAskAI {
                    Button(action: onAskAI) {
                        Text("Ask AI")
                            .font(.system(size: Theme.FontSize.caption, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ask AI about \(payload.title)")
                    .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: Theme.FontSize.tiny, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss \(payload.title)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControl)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(payload.accessibilityLabel)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

/// Pre-formatted payload for the coaching nudge card. Pure value type so the
/// `payload(from:aiEnabled:)` factory is unit-testable without spinning up a
/// SwiftUI view.
struct V6CoachingNudgePayload: Equatable {
    let icon: String
    let title: String
    let detail: String
    let dismissKey: String?
    let showAskAI: Bool

    var accessibilityLabel: String {
        "Coaching nudge. \(title). \(detail)"
    }
}

extension V6CoachingNudge {
    /// Build the single-card payload from the dashboard's existing proactive
    /// alert list. Returns `nil` when there are no alerts so the dashboard
    /// renders nothing (no empty placeholder shell).
    ///
    /// Priority is "first in the array" — `BehaviorInsightService
    /// .computeProactiveAlerts(...)` appends in a fixed protein → glucose →
    /// supplement → workout → logging order, which is also the urgency order
    /// the product wants surfaced. Picking `.first` keeps the priority logic
    /// owned by the existing service rather than this view layer.
    ///
    /// `aiEnabled` flows through to `showAskAI` so the Ask AI pill respects
    /// the dashboard AI-beta toggle. An alert without a `dismissKey` (e.g.
    /// future critical-class alerts) renders without the "×" dismiss
    /// control, matching the existing legacy behavior at the call site.
    static func payload(
        from alerts: [BehaviorInsight],
        aiEnabled: Bool
    ) -> V6CoachingNudgePayload? {
        guard let first = alerts.first else { return nil }
        return V6CoachingNudgePayload(
            icon: first.icon,
            title: first.title,
            detail: first.detail,
            dismissKey: first.dismissKey,
            showAskAI: aiEnabled
        )
    }

    /// Ask-AI action for the nudge card (#928): opens Drift Coach seeded with
    /// this card's real data by posting the V7 `.openDriftCoach` notification
    /// that ContentView observes (`DriftCoachSheet(prefill:)`). The V6
    /// `.expandAIAssistant` post it replaces had no listener after the
    /// floating bubble was retired, so the pill was a silent no-op.
    static func askAI(payload: V6CoachingNudgePayload,
                      center: NotificationCenter = .default) {
        center.post(
            name: .openDriftCoach, object: nil,
            userInfo: ["prefill": NudgeCoachSeed.prompt(title: payload.title,
                                                        detail: payload.detail),
                       // #936: nudge questions fire immediately — only the
                       // edit-in-chat hand-off leaves text in the input.
                       "autoSubmit": true])
    }
}

#if DEBUG
#Preview("V6CoachingNudge with AI") {
    V6CoachingNudge(
        payload: V6CoachingNudgePayload(
            icon: "exclamationmark.triangle.fill",
            title: "Protein below target 3 days running",
            detail: "Avg 90g vs goal 130g. A protein-forward snack now would help close the gap before dinner.",
            dismissKey: "protein_streak",
            showAskAI: true
        ),
        onAskAI: {},
        onDismiss: {}
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}

#Preview("V6CoachingNudge AI off") {
    V6CoachingNudge(
        payload: V6CoachingNudgePayload(
            icon: "drop.fill",
            title: "Glucose ran high after lunch",
            detail: "Spike of 38 mg/dL above baseline — try a 10-minute walk after your next high-carb meal.",
            dismissKey: nil,
            showAskAI: false
        ),
        onAskAI: {},
        onDismiss: nil
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}
#endif
