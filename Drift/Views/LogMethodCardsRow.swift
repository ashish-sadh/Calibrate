import SwiftUI
import DriftCore

/// V7 Phase 2 Dashboard log-methods row — 4 cards that sit between the
/// donut hero (`TodayDonutView`) and the meal timeline. Replaces the
/// V6 quick-log chip strip. Surfaces 4 entry points so first-time users
/// always have a clear path into logging:
///
///   - **Snap** → routes to PhotoLog (camera-first verb, bypasses the
///     segmented sheet so users go straight to capture).
///   - **Voice** → opens `LogMealSheet` at the Voice segment.
///   - **Search** → opens `LogMealSheet` at the Search segment.
///   - **Recent** → opens `LogMealSheet` at the Recent segment.
///
/// Each card is a stable, identifiable surface (`kind` is the identity,
/// not a per-init `UUID()` — same identity discipline `V6Rings` uses).
/// Tap handlers fan out via `NotificationCenter` so the Food tab / AI
/// overlay react without Dashboard owning those sheet bindings.
struct LogMethodCardsRow: View {
    @Binding var selectedTab: Int
    @Binding var aiEnabled: Bool

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 8
        ) {
            ForEach(LogMethodCard.allCases) { card in
                Button { fire(card) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: card.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(height: 22)
                        Text(card.label)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .padding(.vertical, 10)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Theme.separator, lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(card.accessibilityLabel)
                .accessibilityHint(card.accessibilityHint)
                .accessibilityIdentifier("log-method-\(card.rawValue)")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func fire(_ card: LogMethodCard) {
        // Snap is special-cased — user feedback on mobile: "I was
        // expecting it will just plug in and open previous photolog
        // screen we had." Camera-first verb, no intermediate empty
        // state. Routes directly to PhotoLogFlowView via `.openPhotoLog`,
        // bypassing the segmented sheet.
        if card == .snap {
            NotificationCenter.default.post(name: .openPhotoLog, object: nil)
            return
        }

        let mode: LogMealMode
        switch card {
        case .voice: mode = .voice
        case .search: mode = .search
        case .recent: mode = .recent
        case .snap: return  // unreachable — handled above
        }
        NotificationCenter.default.post(
            name: .openLogMeal,
            object: nil,
            userInfo: ["mode": mode.rawValue]
        )
    }
}

/// One log-method card. `id` is `rawValue` so SwiftUI keeps stable
/// identity across Dashboard body recomputes — same discipline as
/// `V6Ring.id`. Adding or reordering cases is a deliberate UI change,
/// not a hidden identity churn.
enum LogMethodCard: String, CaseIterable, Identifiable {
    case snap, voice, search, recent
    var id: String { rawValue }

    var label: String {
        switch self {
        case .snap: "Snap"
        case .voice: "Voice"
        case .search: "Search"
        case .recent: "Recent"
        }
    }

    var icon: String {
        switch self {
        case .snap: "camera"
        case .voice: "mic"
        case .search: "magnifyingglass"
        case .recent: "clock"
        }
    }

    var accessibilityLabel: String { label }

    var accessibilityHint: String {
        switch self {
        case .snap: "Open camera to identify a meal"
        case .voice: "Start AI chat for voice or text input"
        case .search: "Search foods to log"
        case .recent: "Jump to recent foods on the Food tab"
        }
    }
}

#if DEBUG
#Preview("LogMethodCardsRow") {
    StatefulPreview()
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.light)
}

private struct StatefulPreview: View {
    @State private var tab = 0
    @State private var ai = false
    var body: some View {
        LogMethodCardsRow(selectedTab: $tab, aiEnabled: $ai)
    }
}
#endif
