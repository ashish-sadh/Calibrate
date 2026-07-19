import SwiftUI
import DriftCore

struct ContentView: View {
    @AppStorage("tab") var tab = "workout"

    var body: some View {
        TabView(selection: $tab) {
            WorkoutTab()
                .tabItem { Label("Workout", systemImage: "heart.fill") }
                .tag("workout")

            FoodSearchTab()
                .tabItem { Label("Foods", systemImage: "cart") }
                .tag("foods")
        }
        .tint(DriftTheme.accent)
    }
}

/// The P1 spike screen, kept as the Foods tab: searches the seeded food DB
/// through the real DriftCore AppDatabase.
struct FoodSearchTab: View {
    @State var viewModel = ViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                HStack {
                    TextField("Search foods", text: $viewModel.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { viewModel.search() }
                    Button("Search") { viewModel.search() }
                }
                .padding(.horizontal)

                Text(viewModel.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List(viewModel.results) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Foods")
        }
    }
}
