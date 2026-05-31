import SwiftUI
import DriftCore

/// The proactive "Today's Brief" coaching surface (S3 / #878).
///
/// Turns the analytical engine's narrated insights (`BriefItem`s from the S2 narrator,
/// #877) into a single calm card — 1-3 cross-domain insight rows, never a wall. Zero
/// qualifying insights renders a single thin-data onboarding nudge, never an empty shell.
///
/// The view is intentionally dumb, mirroring `V6CoachingNudge`: all decisions (which
/// insights, their goal-alignment, their seed queries) arrive pre-resolved in a
/// `CoachingBriefPayload`. The pure `payload(from:)` factory is `static` so Tier-1 tests
/// can pin the 0 / 1 / 3 / >3-cap / thin-data states without instantiating the SwiftUI
/// tree, the same factory-then-render discipline as `V6CoachingNudge` and `TodayDonutView`.
///
/// Goal-aware color, never good/bad: each row's accent is `Theme.deficit` (green) when the
/// signal is aligned with the goal direction, `Theme.surplus` (red) when against, `Theme.ink`
/// when informational. V7 styling — white card, ink/textPrimary text, hairline separators,
/// no retired `Theme.accent` pink as a primary fill.
///
/// Wiring into `DashboardView` + the once/day cadence is S4 (#879); this card owns its
/// states + the per-row tap/dismiss behavior, surfaced as closures so the call site reuses
/// the V6 Ask-AI plumbing (`onAskCoach` opens Drift Coach pre-seeded with `seedQuery`).
struct CoachingBriefCard: View {
    let payload: CoachingBriefPayload
    /// Opens Drift Coach pre-seeded with the tapped insight's `seedQuery`.
    let onAskCoach: (String) -> Void
    /// Dismisses a single insight (keyed by its `sourceSignalId` at the call site).
    let onDismiss: (BriefItem) -> Void

    init(
        payload: CoachingBriefPayload,
        onAskCoach: @escaping (String) -> Void,
        onDismiss: @escaping (BriefItem) -> Void
    ) {
        self.payload = payload
        self.onAskCoach = onAskCoach
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var header: some View {
        Text("Today's Brief")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var content: some View {
        switch payload {
        case .thinData:
            thinDataNudge
        case .brief(let items):
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(Theme.separator)
                        .frame(height: 0.5)
                        .padding(.horizontal, 16)
                }
                insightRow(item)
            }
        }
    }

    private func insightRow(_ item: BriefItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Goal-aware accent bar — the color is the signal's stance, never good/bad iconography.
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Self.accentColor(for: item.alignment))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    onAskCoach(item.seedQuery)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                        Text("Ask Coach")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Self.accentColor(for: item.alignment))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Self.accentColor(for: item.alignment).opacity(0.12),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ask Coach about \(item.title)")
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onDismiss(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(item.title)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title). \(item.detail)")
    }

    /// Zero qualifying insights → a single calm onboarding nudge, never an empty shell.
    private var thinDataNudge: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Theme.separator.opacity(0.6), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Building your brief")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Log a few days and I'll start spotting patterns across your meals, sleep, and training.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Today's Brief. Building your brief. Log a few days and I'll start spotting patterns.")
    }
}

/// Pre-resolved render state for `CoachingBriefCard` — a pure value type so the
/// `payload(from:)` factory is unit-testable without instantiating the SwiftUI view.
enum CoachingBriefPayload: Equatable {
    /// Not enough qualifying insights yet → a single onboarding nudge, never an empty shell.
    case thinData
    /// 1-3 narrated insights (the factory caps to `CoachingBriefCard.maxItems`).
    case brief([BriefItem])
}

extension CoachingBriefCard {
    /// The brief never shows more than three rows — a calm moment, not a wall.
    static let maxItems = 3

    /// Goal-aware row accent, never a generic good/bad palette: `aligned` (moving toward
    /// the goal) reads green, `against` reads red, `neutral` (informational) reads ink.
    static func accentColor(for alignment: BriefItem.GoalAlignment) -> Color {
        switch alignment {
        case .aligned: return Theme.deficit
        case .against: return Theme.surplus
        case .neutral: return Theme.ink
        }
    }

    /// Build the card payload from the narrator's items. Caps to `maxItems` (never a wall);
    /// an empty list yields the thin-data onboarding nudge (never an empty shell).
    static func payload(from items: [BriefItem]) -> CoachingBriefPayload {
        let capped = Array(items.prefix(maxItems))
        return capped.isEmpty ? .thinData : .brief(capped)
    }
}

#if DEBUG
private extension BriefItem {
    static let sampleProtein = BriefItem(
        title: "Protein dipped 3 days while sleep slid",
        detail: "Avg 92g vs your 130g target, and sleep is down ~40 min — recovery is the thing to protect this week.",
        seedQuery: "My protein has been low and my sleep is down — how do I fix recovery this week?",
        sourceSignalId: "protein_sleep_recovery",
        alignment: .against
    )
    static let sampleSteps = BriefItem(
        title: "Steps are trending up 4 days running",
        detail: "Averaging 9.2k vs your usual 7k — the extra movement is quietly widening your deficit.",
        seedQuery: "My steps are up — how much is that helping my weight goal?",
        sourceSignalId: "steps_trend_up",
        alignment: .aligned
    )
    static let sampleGlucose = BriefItem(
        title: "Glucose runs higher after late dinners",
        detail: "Post-meal readings are ~30 mg/dL higher on nights you eat after 9pm.",
        seedQuery: "Why does my glucose spike after late dinners and what should I change?",
        sourceSignalId: "glucose_late_dinner",
        alignment: .neutral
    )
}

#Preview("Brief — 3 insights") {
    CoachingBriefCard(
        payload: .brief([.sampleProtein, .sampleSteps, .sampleGlucose]),
        onAskCoach: { _ in },
        onDismiss: { _ in }
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}

#Preview("Brief — 1 insight") {
    CoachingBriefCard(
        payload: .brief([.sampleSteps]),
        onAskCoach: { _ in },
        onDismiss: { _ in }
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}

#Preview("Brief — thin data") {
    CoachingBriefCard(
        payload: .thinData,
        onAskCoach: { _ in },
        onDismiss: { _ in }
    )
    .padding()
    .background(Theme.background)
    .preferredColorScheme(.light)
}
#endif
