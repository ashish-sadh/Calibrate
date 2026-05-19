import SwiftUI
import DriftCore

struct ContentView: View {
    @Binding var syncComplete: Bool
    var launchStage: LaunchStage
    @State private var selectedTab = 0

    init(syncComplete: Binding<Bool>, launchStage: LaunchStage = .starting) {
        self._syncComplete = syncComplete
        self.launchStage = launchStage

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
        // V6 light-mode migration 2026-05-19: titles use Theme.textPrimary
        // (near-black on paper-white). Was UIColor.white from the dark era,
        // which left nav titles invisible after the theme flip.
        navAppearance.titleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        navAppearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
        UINavigationBar.appearance().compactAppearance = navAppearance
    }

    @AppStorage("drift_ai_enabled") private var aiEnabled = false

    var body: some View {
        ZStack {
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
                    FloatingAIAssistant(currentTab: selectedTab)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToTab)) { notification in
                if let tab = notification.userInfo?["tab"] as? Int, (0...4).contains(tab) {
                    withAnimation { selectedTab = tab }
                }
            }

            // Launch splash — covers the gap between iOS launch screen and the
            // first DashboardView frame. Most pronounced after a TestFlight
            // update when GRDB migrations + cold-cache view compilation make
            // the first frame take 1-3s. Crossfades out when the launch
            // sequence in DriftApp.task finishes (HealthKit auth + sync,
            // weight trend, TDEE refresh).
            if !syncComplete {
                LaunchSplashView(stage: launchStage)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.25), value: syncComplete)
    }
}

/// Splash shown until DriftApp's launch sequence completes. Matches the app
/// theme (dark background) so the iOS UILaunchScreen → splash → tabs
/// transition has no jarring color flash. Animates a subtle icon pulse and
/// shows progressive status text per launch stage so a 5–15s cold launch
/// reads as deliberate progress, not a frozen frame.
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
