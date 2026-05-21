import SwiftUI
import DriftCore

/// V6 Dashboard quick-log strip — 4 chip buttons that sit under the rings hero.
/// Maps 1:1 to `V6QuickIcon` + the chip grid in
/// `Docs/design-references/v6-2026-05-14/v6/v6-today.jsx` (anatomy step 3).
///
/// Each chip is a stable, identifiable surface (`kind` is the identity, not a
/// per-init `UUID()` — same identity discipline the V6Rings ForEach uses).
/// Tap handlers fan out via `NotificationCenter` so the Food tab / AI overlay
/// can react without Dashboard owning those sheet bindings. The Voice chip
/// uses an explicit `aiEnabled = true` (never `.toggle()`) so a double-tap
/// can't surprise-disable AI.
struct V6QuickLogRow: View {
    @Binding var selectedTab: Int
    @Binding var aiEnabled: Bool

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
            spacing: 8
        ) {
            ForEach(QuickLogChip.allCases) { chip in
                Button { fire(chip) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: chip.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(height: 22)
                        Text(chip.label)
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
                .accessibilityLabel(chip.accessibilityLabel)
                .accessibilityHint(chip.accessibilityHint)
                .accessibilityIdentifier("quick-log-\(chip.rawValue)")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func fire(_ chip: QuickLogChip) {
        // V7: all four chips open the unified Log-a-Meal sheet at the
        // matching mode. The legacy `selectedTab = 2` (jump to Food tab)
        // is a no-op in V7's 3-tab IA — the Food tab doesn't exist
        // anymore. Posting `.openLogMeal` lets ContentView present
        // LogMealSheet at the right mode without each tab root knowing
        // about the sheet binding.
        let mode: LogMealMode
        switch chip {
        case .snap: mode = .snap
        case .voice: mode = .voice
        case .search: mode = .search
        case .recent: mode = .recent
        }
        NotificationCenter.default.post(
            name: .openLogMeal,
            object: nil,
            userInfo: ["mode": mode.rawValue]
        )
    }
}

/// One quick-log chip. `id` is `rawValue` so SwiftUI keeps stable identity
/// across Dashboard body recomputes — same discipline as `V6Ring.id`. Adding
/// or reordering cases is a deliberate UI change, not a hidden identity churn.
enum QuickLogChip: String, CaseIterable, Identifiable {
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
#Preview("V6QuickLogRow") {
    StatefulPreview()
        .padding()
        .background(Theme.background)
        .preferredColorScheme(.light)
}

private struct StatefulPreview: View {
    @State private var tab = 0
    @State private var ai = false
    var body: some View {
        V6QuickLogRow(selectedTab: $tab, aiEnabled: $ai)
    }
}
#endif
