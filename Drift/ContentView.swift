import SwiftUI

struct ContentView: View {
    @Binding var syncComplete: Bool
    @State private var selectedTab = 0

    init(syncComplete: Binding<Bool>) {
        self._syncComplete = syncComplete

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Theme.background)
        tabAppearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]
        let accentColor = UIColor(Theme.accent)
        tabAppearance.stackedLayoutAppearance.selected.iconColor = accentColor
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accentColor]
        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Theme.background)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }

    @AppStorage("drift_ai_enabled") private var aiEnabled = false

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(syncComplete: $syncComplete, selectedTab: $selectedTab)
                .tabItem { Label("Drift", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(0)

            WeightTabView(syncComplete: $syncComplete, selectedTab: $selectedTab)
                .tabItem { Label("Weight", systemImage: "scalemass") }
                .tag(1)

            FoodTabView(selectedTab: $selectedTab)
                .tabItem { Label("Food", systemImage: "fork.knife") }
                .tag(2)

            WorkoutView(selectedTab: $selectedTab)
                .wrapInNav()
                .tabItem { Label("Exercise", systemImage: "dumbbell.fill") }
                .tag(3)

            MoreTabView(selectedTab: $selectedTab)
                .tabItem { Label("More", systemImage: "ellipsis") }
                .tag(4)
        }
        .tint(Theme.accent)
        .background(Theme.background.ignoresSafeArea())
        .overlay {
            if aiEnabled {
                FloatingAIAssistant()
            }
        }


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
