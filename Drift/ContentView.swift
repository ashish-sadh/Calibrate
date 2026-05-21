import SwiftUI
import DriftCore

/// V7 IA — four primary tabs (Today / Food / Body / More) + a floating
/// chat button to the right of the tab pill that opens Drift Coach.
/// The Log-a-Meal sheet is still reachable via Dashboard chips
/// (Snap/Voice/Search/Recent) and per-meal "+" rows inside the Food
/// tab — the global "+" FAB was removed once Food became a top-level
/// destination, since the dedicated tab provides better-than-FAB
/// access to logging. The per-screen nav-bar chat icons were removed
/// in the same pass; AI is now a single floating control instead of
/// being duplicated on every tab.
struct ContentView: View {
    @Binding var syncComplete: Bool
    var launchStage: LaunchStage

    @State private var selectedTab: PrimaryTab = .today
    @State private var showingLogMeal = false
    /// Mode the next LogMealSheet presentation should open at. Set by
    /// the Dashboard quick-log chips via `.openLogMeal` notification.
    @State private var pendingLogMealMode: LogMealMode = .recent
    /// V7 polish: Snap chip routes directly here instead of through
    /// the Log-a-Meal sheet — user expected camera-first.
    @State private var showingPhotoLog = false
    @State private var photoLogVM = FoodLogViewModel()
    /// Drift Coach is now the floating bottom-right control (replaces
    /// the V6 coral bubble *and* the V7 black FAB). Sheet state moved
    /// here from per-tab @State so the chat persists across tab swipes.
    @State private var showingDriftCoach = false

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

    var body: some View {
        ZStack {
            ZStack(alignment: .bottom) {
                tabContent
                    .ignoresSafeArea(.keyboard)

                tabBarOverlay
            }
            .background(Theme.background.ignoresSafeArea())
            .sheet(isPresented: $showingLogMeal) {
                LogMealSheet(initialMode: pendingLogMealMode)
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
                if let tab = notification.userInfo?["tab"] as? Int,
                   let mapped = PrimaryTab(legacyIndex: tab) {
                    withAnimation { selectedTab = mapped }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLogMeal)) { notification in
                if let rawMode = notification.userInfo?["mode"] as? String,
                   let mode = LogMealMode(rawValue: rawMode) {
                    pendingLogMealMode = mode
                } else {
                    pendingLogMealMode = .recent
                }
                showingLogMeal = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .openPhotoLog)) { _ in
                showingPhotoLog = true
            }
            .fullScreenCover(isPresented: $showingPhotoLog) {
                PhotoLogFlowView(foodLog: photoLogVM)
            }
            .sheet(isPresented: $showingDriftCoach) {
                DriftCoachSheet()
            }

            if !syncComplete {
                LaunchSplashView(stage: launchStage)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: syncComplete)
    }

    /// Tab content. Was a ViewBuilder `switch` over `selectedTab`, but that
    /// causes SwiftUI to fully tear down and rebuild the destination view
    /// on every tab change — jarring transition, lost scroll position,
    /// re-fired `.task` blocks. Native `TabView` with `.page` style keeps
    /// all three pages alive, animates the swap with the system's built-in
    /// cross-fade, and allows a horizontal swipe between tabs without
    /// touching the pill bar at the bottom. Page-indicator dots are
    /// hidden because the custom `PillTabBar` is the canonical selector.
    private var tabContent: some View {
        // Default `TabView` keeps every page alive across selection
        // (no view rebuild on switch like the original `switch` had
        // — that was the original UX complaint in #5). The PillTabBar
        // at the bottom drives `selectedTab`; we hide the system tab
        // bar so only the pill is visible.
        //
        // Earlier (commit c975c24f) this used `.tabViewStyle(.page(...))`
        // for swipe-between-tabs. That triggered an
        // NSInternalInconsistencyException when Food (which has its
        // own NavigationStack) became a tab — the page-style pager's
        // own nav-bar context fought with FoodTabView's
        // NavigationStack on tab-swap, raising "client attempt to
        // nest wrapped navigation controllers." Dropping `.page`
        // keeps all tabs alive without the nav-bar nesting conflict.
        TabView(selection: $selectedTab) {
            DashboardView(syncComplete: $syncComplete, selectedTab: selectedTabBindingLegacy)
                .tag(PrimaryTab.today)
                .accessibilityIdentifier("tab-today-content")
            FoodTabView(selectedTab: selectedTabBindingLegacy)
                .tag(PrimaryTab.food)
                .accessibilityIdentifier("tab-food-content")
            WeightTabView(syncComplete: $syncComplete, selectedTab: selectedTabBindingLegacy)
                .tag(PrimaryTab.body)
                .accessibilityIdentifier("tab-body-content")
            MoreTabView(selectedTab: selectedTabBindingLegacy)
                .tag(PrimaryTab.more)
                .accessibilityIdentifier("tab-more-content")
        }
        .toolbar(.hidden, for: .tabBar)
        // V7 polish: floating PillTabBar + FAB sit in the bottom 78pt of
        // the screen but don't contribute to the safe area (they live
        // in an overlay ZStack). Without this inset, ScrollViews inside
        // the tab destinations let their last row slide *under* the
        // tab bar — the V7 mobile review surfaced this as "content
        // gets cut off at the bottom" and contributed to the
        // "UI not flowing" complaint.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 78)
        }
    }

    private var tabBarOverlay: some View {
        HStack(spacing: 12) {
            PillTabBar(selected: $selectedTab)
            ChatIconButton(isPresented: $showingDriftCoach)
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
    case today = 0, food = 1, body = 2, more = 3
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .food: "Food"
        case .body: "Body"
        case .more: "More"
        }
    }
    var icon: String {
        switch self {
        case .today: "target"
        case .food: "fork.knife"
        case .body: "figure"
        case .more: "line.3.horizontal"
        }
    }
    var accessibilityIdentifier: String {
        switch self {
        case .today: "tab-today"
        case .food: "tab-food"
        case .body: "tab-body"
        case .more: "tab-more"
        }
    }

    /// Map V7 tab → legacy 5-tab index used by inner-view bindings.
    /// Today=0 (was Drift=0), Food=2 (was Food=2), Body=1 (was Weight=1),
    /// More=4 (was More=4). Food was briefly dropped in the 3-tab
    /// collapse (c0e4f674) and re-added 2026-05-20 after the food
    /// diary felt "almost gone" — user wanted it as a visible tab.
    var legacyIndex: Int {
        switch self {
        case .today: 0
        case .food: 2
        case .body: 1
        case .more: 4
        }
    }

    /// Inverse of `legacyIndex`. Returns nil for legacy 3 (Exercise),
    /// which lives under More → Activity in V7.
    init?(legacyIndex: Int) {
        switch legacyIndex {
        case 0: self = .today
        case 1: self = .body
        case 2: self = .food
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
