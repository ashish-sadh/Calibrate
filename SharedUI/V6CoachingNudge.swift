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
///
/// Lives in `SharedUI/` since #1130: the card has no iOS-app-target dependency
/// at all (`Theme` is shared; `BehaviorInsight`, `NudgeCoachSeed` and
/// `.openDriftCoach` are DriftCore), so Android's Today tab renders this exact
/// file instead of a re-creation of it.
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
            behaviorInsightGlyph(payload.icon, tint: Theme.accent,
                                 font: .system(size: Theme.FontSize.base, weight: .semibold),
                                 drawnSize: 18)
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
        // skip-fuse-ui ships accessibilityElement and dynamicTypeSize as
        // @available(*, unavailable); Android reads the children separately and
        // follows the system font scale without our upper clamp.
        #if !os(Android)
        .accessibilityElement(children: .combine)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        #endif
        // Text(_:) rather than the bare String: SkipUI only bridges the
        // LocalizedStringKey and Text overloads, so a String *variable* fails to
        // compile for Android. Same overload on iOS, so nothing changes there.
        .accessibilityLabel(Text(payload.accessibilityLabel))
    }
}

/// Renders a `BehaviorInsight.icon` — a raw SF Symbol name minted in DriftCore,
/// never routed through `sym()` by its call sites.
///
/// On Android an unmapped name renders skip-ui's **warning triangle**, and
/// `BehaviorInsight` emits ten names of which only two survive the map. Every
/// one the service can produce is handled here (#1130): drawn Shapes where
/// Material has no equivalent object, a same-meaning mapped glyph otherwise,
/// and `sym()` for the rest so a *new* service icon shows a visible triangle
/// rather than a silently wrong object (directive 0a).
///
/// `font` drives the Darwin path so iOS keeps its exact type-scaled symbol;
/// `drawnSize` is the point size for the Android shapes, which have no font.
@ViewBuilder
func behaviorInsightGlyph(_ symbol: String, tint: Color, font: Font, drawnSize: CGFloat) -> some View {
    #if os(Android)
    switch symbol {
    // fork.knife / chart.bar.fill: the two icons the live sim showed on a
    // seeded account, and both were triangles. `chart.bar.xaxis` is NOT the
    // fix — it only exists in skip-ui ≥1.59 and this build is pinned to 1.58
    // (#1134), so it is unmapped too (see Symbols.swift).
    case "fork.knife":
        ForkKnifeShape().fill(tint).frame(width: drawnSize, height: drawnSize)
    case "chart.bar.fill":
        BarChartShape().fill(tint).frame(width: drawnSize, height: drawnSize)
    case "moon.zzz.fill":
        MoonStarsShape().fill(tint).frame(width: drawnSize, height: drawnSize)
    case "pill.fill":
        PillShape().fill(tint).frame(width: drawnSize, height: drawnSize)
            .rotationEffect(.degrees(-45))
    case "waveform.path.ecg":
        EcgWaveShape().stroke(tint, style: StrokeStyle(lineWidth: max(1.4, drawnSize / 11),
                                                       lineCap: .round, lineJoin: .round))
            .frame(width: drawnSize, height: drawnSize)
    // "pencil" IS mapped; the slash isn't expressible, and the card title
    // ("Food logging paused") already carries the "stopped" half of the meaning.
    case "pencil.slash":
        Image(systemName: "pencil").font(font).foregroundStyle(tint)
    // exclamationmark.triangle.fill falls through to sym() and stays a warning
    // triangle — deliberate, and identical to iOS, which draws the same glyph
    // accent-tinted for the protein-streak alert.
    default:
        Image(systemName: sym(symbol)).font(font).foregroundStyle(tint)
    }
    #else
    Image(systemName: symbol).font(font).foregroundStyle(tint)
    #endif
}

/// The dashboard's Behavior Insights list — a card of `BehaviorInsight` rows
/// under a lightbulb header, goal-aware green/red per `isPositive`.
///
/// Extracted from `DashboardView.insightsCard` into `SharedUI/` by #1130 so the
/// Android Today tab renders the same rows rather than a second copy that can
/// drift. iOS rendering is unchanged.
struct BehaviorInsightsCard: View {
    let insights: [BehaviorInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                // Material's mapped set has no lightbulb of any kind, so the
                // header glyph is drawn (LightbulbShape) on Android.
                #if os(Android)
                LightbulbShape().fill(Theme.fatYellow).frame(width: 13, height: 13)
                #else
                Image(systemName: "lightbulb.fill")
                    .font(.caption).foregroundStyle(Theme.fatYellow)
                #endif
                Text("Insights").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            ForEach(insights, id: \.id) { insight in
                HStack(alignment: .top, spacing: 8) {
                    behaviorInsightGlyph(insight.icon,
                                         tint: insight.isPositive ? Theme.deficit : Theme.surplus,
                                         font: .caption, drawnSize: 13)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title)
                            .font(.caption.weight(.semibold))
                        Text(insight.detail)
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(3)
                    }
                }
            }
        }
        .card()
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

// The #Preview macro exists in neither the Android Swift build nor Skip's
// Darwin bridging pass, so previews are iOS-app-only in SharedUI files.
#if DEBUG && DRIFT_IOS_APP
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
