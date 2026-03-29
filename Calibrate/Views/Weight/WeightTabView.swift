import SwiftUI
import Charts

struct WeightTabView: View {
    @State private var viewModel = WeightViewModel()
    @State private var showingAddWeight = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Time range picker
                    Picker("Time Range", selection: $viewModel.selectedTimeRange) {
                        ForEach(WeightViewModel.TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: viewModel.selectedTimeRange) { _, _ in
                        viewModel.loadEntries()
                    }

                    // Chart
                    if let trend = viewModel.trend {
                        WeightChartView(trend: trend, unit: viewModel.weightUnit)
                            .frame(height: 250)
                            .padding(.horizontal)

                        // Insights section
                        WeightInsightsView(trend: trend, unit: viewModel.weightUnit)
                            .padding(.horizontal)

                        // Daily log
                        WeightLogListView(
                            entries: viewModel.entries,
                            unit: viewModel.weightUnit,
                            onDelete: { viewModel.deleteWeight(id: $0) }
                        )
                        .padding(.horizontal)
                    } else {
                        ContentUnavailableView(
                            "No Weight Data",
                            systemImage: "scalemass",
                            description: Text("Log your first weight or connect Apple Health to get started.")
                        )
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Weight")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddWeight = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddWeight) {
                WeightEntryView(unit: viewModel.weightUnit) { value in
                    viewModel.addWeight(value: value)
                }
            }
            .onAppear {
                viewModel.loadEntries()
            }
        }
    }
}
