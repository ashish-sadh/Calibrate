import SwiftUI
import DriftCore

/// Android shell — mirrors iOS ContentView's V7 IA: five tabs behind a
/// floating pill bar + the Drift Coach button (see AppShell.swift).
struct ContentView: View {
    @State var selectedTab: PrimaryTab = .today
    @State var showingCoach = false

    var body: some View {
        ZStack(alignment: .bottom) {
            tabContent

            HStack(spacing: 8) {
                PillTabBar(selected: $selectedTab)
                    .frame(maxWidth: .infinity)
                ChatIconButton(isPresented: $showingCoach)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .background(Theme.background.ignoresSafeArea())
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
