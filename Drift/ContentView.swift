import SwiftUI
import DriftCore

/// V7 IA — three primary tabs (Today / Body / More) + a black floating "+"
/// FAB to the right of the tab pill that opens the Log-a-Meal sheet.
///
/// Old V6 layout had five tabs (Drift / Weight / Food / Exercise / More)
/// and a coral floating AI bubble overlay. Food + Exercise are no longer
/// destinations — Food is reachable only via the FAB (where logging
/// belongs), Exercise lives under More → Activity → Exercise. The AI
/// floating bubble is kept temporarily; Phase 5 replaces it with a
/// Drift Coach sheet and a per-screen nav-bar chat icon.
struct ContentView: View {
    @Binding var syncComplete: Bool
    var launchStage: LaunchStage

    @State private var selectedTab: PrimaryTab = .today
    @State private var showingLogMeal = false

    init(syncComplete: Binding<Bool>, launchStage: LaunchStage = .starting) {
        self._syncComplete = syncComplete
        self.launchStage = launchStage

        // Pre-V7 we customized UITabBarAppearance for the system tab bar.
        // V7 renders its own pill tab bar, so the system one is unused.
        // We still configure UINavigationBar so large titles read as ink
        // on paper-white (the dark-era titles were white-on-white after
        // the light migration).
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Theme.background)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }

    @AppStorage("drift_ai_enabled") private var aiEnabled = true

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                tabContent
                    .ignoresSafeArea(.keyboard)

                tabBarOverlay
            }
            .background(Theme.background.ignoresSafeArea())
            .overlay {
                if aiEnabled {
                    // V6 floating bubble — Phase 5 replaces with a sheet
                    // triggered from a nav-bar chat icon per the V7 design.
                    FloatingAIAssistant(currentTab: selectedTab.legacyIndex)
                }
            }
            .sheet(isPresented: $showingLogMeal) {
                LogMealSheet()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
                if let tab = notification.userInfo?["tab"] as? Int,
                   let mapped = PrimaryTab(legacyIndex: tab) {
                    withAnimation { selectedTab = mapped }
                }
            }

            if !syncComplete {
                LaunchSplashView(stage: launchStage)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: syncComplete)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .today:
            DashboardView(syncComplete: $syncComplete, selectedTab: selectedTabBindingLegacy)
                .accessibilityIdentifier("tab-today-content")
        case .body:
            WeightTabView(syncComplete: $syncComplete, selectedTab: selectedTabBindingLegacy)
                .accessibilityIdentifier("tab-body-content")
        case .more:
            MoreTabView(selectedTab: selectedTabBindingLegacy)
                .accessibilityIdentifier("tab-more-content")
        }
    }

    private var tabBarOverlay: some View {
        HStack(spacing: 12) {
            PillTabBar(selected: $selectedTab)
            FAB { showingLogMeal = true }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    /// Backwards-compat shim: inner views (DashboardView, WeightTabView,
    /// MoreTabView) still take `@Binding var selectedTab: Int` keyed off
    /// the old 5-tab indices. We expose a derived binding that maps to
    /// the legacy index so existing tab-jump logic (e.g. "Log →" links
    /// that set selectedTab=2 to jump to Food) doesn't have to change in
    /// this commit. Phase 2 + 3 will rewrite the inner views and we can
    /// drop the legacy mapping then.
    private var selectedTabBindingLegacy: Binding<Int> {
        Binding(
            get: { selectedTab.legacyIndex },
            set: { newValue in
                if let mapped = PrimaryTab(legacyIndex: newValue) {
                    selectedTab = mapped
                }
                // Legacy values that don't map (2 = Food, 3 = Exercise)
                // are intentionally ignored — Food opens via FAB,
                // Exercise lives under More. Inner views may attempt
                // these jumps; they become no-ops in V7. Phase 2 will
                // route Food jumps to the FAB sheet.
            }
        )
    }
}

// MARK: - Primary tabs

enum PrimaryTab: Int, CaseIterable, Identifiable {
    case today = 0, body = 1, more = 2
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .body: "Body"
        case .more: "More"
        }
    }
    var icon: String {
        switch self {
        case .today: "target"
        case .body: "figure"
        case .more: "line.3.horizontal"
        }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .today: "tab-today"
        case .body: "tab-body"
        case .more: "tab-more"
        }
    }

    /// Map V7 tab → legacy 5-tab index used by inner-view bindings.
    /// Today=0 (was Drift=0), Body=1 (was Weight=1), More=2 (was More=4).
    var legacyIndex: Int {
        switch self {
        case .today: 0
        case .body: 1
        case .more: 4
        }
    }

    /// Inverse of `legacyIndex`. Returns nil for legacy values that don't
    /// map (2 = Food, 3 = Exercise — Food now opens via FAB, Exercise lives
    /// under More).
    init?(legacyIndex: Int) {
        switch legacyIndex {
        case 0: self = .today
        case 1: self = .body
        case 4: self = .more
        default: return nil
        }
    }
}

// MARK: - Pill tab bar

private struct PillTabBar: View {
    @Binding var selected: PrimaryTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PrimaryTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selected = tab }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(selected == tab ? Theme.ink : Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
            }
        }
        .padding(.horizontal, 6)
        .background(Theme.cardBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator, lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
    }
}

// MARK: - Floating + button

private struct FAB: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Theme.ink, in: Circle())
                .shadow(color: Color.black.opacity(0.20), radius: 14, x: 0, y: 6)
        }
        .accessibilityIdentifier("fab-log-meal")
        .accessibilityLabel("Log a meal")
    }
}

// MARK: - Log a Meal sheet
//
// V7 places meal logging behind the floating "+" FAB. Phase 5 redesigns
// this sheet as a 4-mode segmented picker (Recent / Search / Voice / Snap)
// matching reference mocks 16-19. For Phase 4 we wrap the existing
// FoodTabView so the FAB has a working destination — the visual refresh
// of the picker itself lands in the next commit.

private struct LogMealSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            FoodTabView(selectedTab: .constant(0))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

// MARK: - Launch splash (unchanged from V6)

private struct LaunchSplashView: View {
    let stage: LaunchStage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconPulse = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .scaleEffect(iconPulse ? 1.05 : 1.0)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: iconPulse)
                Text("Drift")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text(stage.statusText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: stage)
                    .padding(.top, 8)
                    .frame(minHeight: 18)
            }
        }
        .onAppear { if !reduceMotion { iconPulse = true } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let text = stage.statusText
        return text.isEmpty ? "Drift is loading" : "Drift is loading. \(text)"
    }
}

extension View {
    func wrapInNav() -> some View {
        NavigationStack { self }
    }
}

#Preview {
    ContentView(syncComplete: .constant(true))
}
