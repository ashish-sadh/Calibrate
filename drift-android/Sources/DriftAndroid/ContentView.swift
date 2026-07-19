import SwiftUI
import DriftCore

struct ContentView: View {
    @AppStorage("tab") var tab = "workout"

    var body: some View {
        TabView(selection: $tab) {
            FoodTab()
                .tabItem { Label("Food", systemImage: "cart") }
                .tag("food")

            WorkoutTab()
                .tabItem { Label("Workout", systemImage: "heart.fill") }
                .tag("workout")

            WeightTab()
                .tabItem { Label("Weight", systemImage: "chart.bar.xaxis") }
                .tag("weight")
        }
        .tint(Theme.accent)
    }
}
