import SwiftUI
import DriftCore

/// Android shell — mirrors iOS ContentView's V7 IA: five tabs behind a
/// floating pill bar + the Drift Coach button (see AppShell.swift).
struct ContentView: View {
    @State var selectedTab: PrimaryTab = .today
    @State var showingCoach = false
    // #1216. Compose applies the IME inset to the window, so opening the
    // keyboard SHRINKS this ZStack — the bottom-aligned overlay row below then
    // rides up and parks on top of the keyboard, while the clearance spacer
    // stays stranded above it. Measured on build 108 (1080x2400 @ 420dpi): the
    // pill bar jumped from y=2270px to y=1450px, leaving 51dp between the
    // Friends search field and the bar where a result row needs ~60 — so you
    // type a handle and the only match is drawn behind the bar until you
    // dismiss the keyboard. iOS never shows this: its clearance is UIKit
    // `additionalSafeAreaInsets` and the iOS keyboard OVERLAYS the tab bar.
    //
    // Hiding the row while the IME is up (and zeroing the clearance with it) is
    // standard Android bottom-nav behavior, so it reads as native rather than
    // as a workaround — and it reclaims the full ~110dp instead of just
    // un-occluding it. These two are NOT private: Fuse cannot bridge private
    // @State (the errors point at line 1), same as `selectedTab`.
    @State var imeVisible = false
    @State var imeBaseline: CGSize = .zero

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
                //
                // The minimized-workout pill (#1167) sits in the SAME overlay
                // stack and is conditional, so the clearance has to grow with
                // it — otherwise resuming a workout re-buries the last card the
                // fixed inset just uncovered.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: bottomOverlayClearance)
                }

            // Hidden while the keyboard is up (#1216) — see `imeVisible`.
            if !imeVisible {
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
                // Alpha-only, like the tab cross-fade at :30 — Compose fadeIn/Out
                // is real on SkipUI, so the row doesn't slide with the keyboard.
                .transition(.opacity)
            }
        }
        .background(imeProbe)
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

    /// How much of the screen bottom the floating overlays cover.
    ///
    /// 78 matches iOS's `FloatingTabBar.clearance` for the pill bar; the
    /// minimized-workout pill stacks above it and only exists sometimes, so its
    /// height is added only when it's actually on screen. Same visibility
    /// condition as `MinimizedWorkoutBar.body`, which is what keeps the two from
    /// disagreeing.
    private var bottomOverlayClearance: CGFloat {
        // Nothing is drawn down there while the keyboard is up (#1216), and this
        // is not a real safe-area inset on Android — the SkipUICompat shim
        // stacks it as a plain VStack spacer under the content, so leaving it at
        // 78 would strand a dead band directly above the IME and make hiding the
        // row a no-op for the content that needed the space.
        if imeVisible { return 0 }
        let monitor = LiveWorkoutMonitor.shared
        let pillShowing = !monitor.isPresented && monitor.minimizedName != nil
        return pillShowing ? 78 + 56 : 78
    }

    /// Zero-cost IME detector: a `Color.clear` leaf that reports the shell
    /// root's height. It backs the ZStack rather than wrapping the content, so
    /// the per-frame GeometryReader recomposition never touches the view tree,
    /// and the `@State` write originates inside skip-ui's own composition loop
    /// (the proven repaint path — unlike a bridged/Kotlin callback, #1180).
    private var imeProbe: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { rootGeometryChanged(width: geo.size.width, height: geo.size.height) }
                .onChange(of: geo.size.height) { _, height in
                    rootGeometryChanged(width: geo.size.width, height: height)
                }
        }
    }

    /// Treats "the root got shorter at the same width" as the keyboard opening.
    ///
    /// Any WIDER/NARROWER width (rotation, multi-window) or any TALLER height
    /// re-baselines instead, which also self-heals the first composition when it
    /// reports 0. Threshold is 150pt because the emulator IME measures ~312dp
    /// (820px @ 420dpi) and nothing else transiently removes that much height at
    /// a constant width. Known cosmetic residual, deliberately not engineered
    /// around: rotating WHILE the keyboard is open re-baselines to the shrunk
    /// size, so the row can reappear over the IME until it is closed once.
    private func rootGeometryChanged(width: CGFloat, height: CGFloat) {
        if width != imeBaseline.width || height > imeBaseline.height {
            imeBaseline = CGSize(width: width, height: height)
        }
        let visible = (imeBaseline.height - height) > 150
        if visible != imeVisible {
            withAnimation(.easeInOut(duration: 0.15)) { imeVisible = visible }
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
