import SwiftUI

struct SupplementsTabView: View {
    @State private var viewModel = SupplementViewModel()
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Status
                    HStack {
                        Text("\(viewModel.takenCount)/\(viewModel.totalCount)")
                            .font(.title.weight(.bold).monospacedDigit())
                            .foregroundStyle(viewModel.takenCount == viewModel.totalCount && viewModel.totalCount > 0 ? Theme.deficit : .primary)
                        Text("taken today")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .card()

                    // Checklist
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.supplements.enumerated()), id: \.element.id) { index, supplement in
                            Button {
                                if let id = supplement.id { viewModel.toggleTaken(supplementId: id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: viewModel.isTaken(supplement.id ?? 0) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(viewModel.isTaken(supplement.id ?? 0) ? Theme.deficit : .secondary)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(supplement.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if !supplement.dosageDisplay.isEmpty {
                                            Text(supplement.dosageDisplay)
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }

                                    Spacer()

                                    if viewModel.isTaken(supplement.id ?? 0),
                                       let log = viewModel.todayLogs[supplement.id ?? 0],
                                       let takenAt = log.takenAt {
                                        Text(formatTime(takenAt))
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)

                            if index < viewModel.supplements.count - 1 {
                                Divider().overlay(Color.white.opacity(0.05))
                            }
                        }
                    }
                    .card()

                    if viewModel.supplements.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "pill")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.accent.opacity(0.5))
                            Text("No supplements yet")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("Supplements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddSupplementView(viewModel: viewModel)
            }
            .onAppear {
                viewModel.seedDefaultsIfNeeded()
                viewModel.loadSupplements()
            }
        }
    }

    private func formatTime(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}
