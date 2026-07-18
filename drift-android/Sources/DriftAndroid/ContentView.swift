import SwiftUI

struct ContentView: View {
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
            .navigationTitle("DriftCore Spike")
        }
    }
}
