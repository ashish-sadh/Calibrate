import SwiftUI

struct ContentView: View {
    @Binding var syncComplete: Bool

    init(syncComplete: Binding<Bool>) {
        self._syncComplete = syncComplete

        // Solid dark tab bar - no blur/glass effect
        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(Theme.background)

        // Normal state
        tabAppearance.stackedLayoutAppearance.normal.iconColor = .secondaryLabel
        tabAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.secondaryLabel]

        // Selected state - clean accent color, no blob
        let accentColor = UIColor(Theme.accent)
        tabAppearance.stackedLayoutAppearance.selected.iconColor = accentColor
        tabAppearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: accentColor]

        UITabBar.appearance().standardAppearance = tabAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance

        // Dark nav bar
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(Theme.background)
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }

    var body: some View {
        TabView {
            DashboardView(syncComplete: $syncComplete)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis")
                }

            WeightTabView(syncComplete: $syncComplete)
                .tabItem {
                    Label("Weight", systemImage: "scalemass")
                }

            FoodTabView()
                .tabItem {
                    Label("Food", systemImage: "fork.knife")
                }

            SupplementsTabView()
                .tabItem {
                    Label("Supplements", systemImage: "pill")
                }

            MoreTabView()
                .tabItem {
                    Label("More", systemImage: "ellipsis")
                }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    ContentView(syncComplete: .constant(true))
}
