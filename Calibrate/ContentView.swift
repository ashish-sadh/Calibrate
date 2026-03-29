import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "chart.line.uptrend.xyaxis") {
                DashboardView()
            }

            Tab("Weight", systemImage: "scalemass") {
                WeightTabView()
            }

            Tab("Food", systemImage: "fork.knife") {
                FoodTabView()
            }

            Tab("Supplements", systemImage: "pill") {
                SupplementsTabView()
            }

            Tab("More", systemImage: "ellipsis") {
                MoreTabView()
            }
        }
    }
}

#Preview {
    ContentView()
}
