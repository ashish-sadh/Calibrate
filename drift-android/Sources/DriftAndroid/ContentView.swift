import SwiftUI
import DriftCore

/// Android shell — mirrors iOS ContentView's V7 IA: five tabs behind a
/// floating pill bar + the Drift Coach button (see AppShell.swift).
struct ContentView: View {
    @State var selectedTab: PrimaryTab = .today
    @State var showingCoach = false

    var body: some View {
        ZStack(alignment: .bottom) {
            // .id(selectedTab) forces the outgoing tab (and any NavigationStack
            // it pushed) to be torn down on a tab switch. Without it, a pushed
            // destination's Compose NavHost stays composed on top, so tapping
            // the pill bar while on a sub-screen (e.g. More → Friends) did
            // nothing — only the system back button worked. #android-tab-switch
            //
            // frame(maxWidth/maxHeight: .infinity) + .transition(.opacity) are
            // the #1074 letter-stacking fix: iOS's TabView cross-fades two
            // already-measured pages, but this switch rebuilds the incoming tab
            // DURING the 0.22s animation — with no size modifier the content was
            // measured at intermediate animated widths, so text re-wrapped into
            // vertical letter stacks mid-swap ("fonts keep changing", operator).
            // Pinning the frame means text can never be measured narrow, and the
            // opacity transition makes the swap alpha-only (Compose fadeIn/Out —
            // real on SkipUI, Transition.swift:122) instead of layout-animating.
            tabContent
                .id(selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                // Scroll clear of the floating pill bar.
                //
                // The bar is an OVERLAY in this ZStack and nothing reserved
                // space for it, so the last card on every tab sat underneath
                // it — Today's weight/workouts/streak row and Workout's Health
                // Connect card were both cut off mid-content. iOS has had this
                // all along via `floatingTabBarClearance()` (78pt of
                // additionalSafeAreaInsets), but that modifier lives in
                // Drift/Views/Shared and is UIKit-based, so it never applied
                // here.
                //
                // safeAreaInset rather than padding: a ScrollView insets its
                // CONTENT and still scrolls under the bar, which is what iOS
                // does — padding would leave a dead band the page can't use.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 78)
                }

            VStack(spacing: 0) {
                // Strong-style minimized-workout pill (#1167) — visible on every
                // tab, taps to resume the live sheet. It owns its own bottom gap,
                // so an empty bar reserves no space.
                MinimizedWorkoutBar()
                    .padding(.horizontal, 10)
                HStack(spacing: 8) {
                    PillTabBar(selected: $selectedTab)
                        .frame(maxWidth: .infinity)
                    ChatIconButton(isPresented: $showingCoach)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .onAppear { LiveWorkoutMonitor.shared.refresh() }
        .onChange(of: LiveWorkoutMonitor.shared.wantsResume) { _, wants in
            // The pill asked to resume: bring the Workout tab forward (it's torn
            // down when not selected here, so this rebuilds WorkoutView, whose
            // onAppear reads the same flag and presents the sheet).
            if wants { selectedTab = .workout }
        }
        // Compose defaults every native control (Toggle, Stepper, TextField
        // caret/focus ring, checkboxes) to MaterialTheme's blue primary, which
        // read as a different app next to Drift's pink accent (#1078). `tint`
        // is a real skip-fuse-ui bridge, so one root-level tint recolors them
        // all rather than per-control patches.
        .tint(Theme.accent)
        .sheet(isPresented: $showingCoach) {
            // Real Drift Coach chat — Nebius-backed, SharedUI single-source. #1066
            AIChatView()
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .today: TodayTab(selectedTab: $selectedTab)
        case .food: FoodTab()
        case .workout: WorkoutTab()
        case .body: WeightTab()
        case .more: MoreTab()
        }
    }
}
