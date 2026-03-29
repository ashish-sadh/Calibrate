import SwiftUI

struct SupplementsTabView: View {
    @State private var viewModel = SupplementViewModel()
    @State private var showingAddSupplement = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Status header
                    HStack {
                        Text("Today")
                            .font(.headline)
                        Spacer()
                        Text("\(viewModel.takenCount)/\(viewModel.totalCount) taken")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)

                    // Checklist
                    ForEach(viewModel.supplements) { supplement in
                        supplementRow(supplement)
                    }

                    if viewModel.supplements.isEmpty {
                        ContentUnavailableView(
                            "No Supplements",
                            systemImage: "pill",
                            description: Text("Add supplements to track your daily intake.")
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Supplements")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSupplement = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSupplement) {
                AddSupplementView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.seedDefaultsIfNeeded()
                viewModel.loadSupplements()
            }
        }
    }

    private func supplementRow(_ supplement: Supplement) -> some View {
        Button {
            if let id = supplement.id {
                viewModel.toggleTaken(supplementId: id)
            }
        } label: {
            HStack {
                Image(systemName: viewModel.isTaken(supplement.id ?? 0) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(viewModel.isTaken(supplement.id ?? 0) ? .green : .secondary)

                VStack(alignment: .leading) {
                    Text(supplement.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    if !supplement.dosageDisplay.isEmpty {
                        Text(supplement.dosageDisplay)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if viewModel.isTaken(supplement.id ?? 0),
                   let log = viewModel.todayLogs[supplement.id ?? 0],
                   let takenAt = log.takenAt {
                    Text(formatTime(takenAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ isoString: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: isoString) else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
