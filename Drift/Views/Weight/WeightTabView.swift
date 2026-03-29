import SwiftUI
import Charts

struct WeightTabView: View {
    @Binding var syncComplete: Bool
    @State private var viewModel = WeightViewModel()
    @State private var showingAddWeight = false
    @State private var selectedSection = 0 // 0=chart, 1=insights, 2=log

    var body: some View {
        NavigationStack {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        // Time range + granularity
                        timeRangeBar

                        // Chart
                        WeightChartView(trend: viewModel.trend, unit: viewModel.weightUnit, granularity: viewModel.granularity)
                            .frame(height: 240)

                        // Weekly/Monthly averages
                        averagesSection

                        // Insights (MacroFactor style)
                        if let trend = viewModel.trend {
                            WeightInsightsView(trend: trend, unit: viewModel.weightUnit)
                        }

                        // Monthly grouped log
                        WeightLogListView(
                            entries: viewModel.entries,
                            unit: viewModel.weightUnit,
                            onDelete: { viewModel.deleteWeight(id: $0) }
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Theme.background)
        .navigationTitle("Weight")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddWeight = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingAddWeight) {
            WeightEntryView(unit: viewModel.weightUnit) { viewModel.addWeight(value: $0) }
        }
        .onAppear { viewModel.loadEntries() }
        .onChange(of: syncComplete) { _, done in
            if done { viewModel.loadEntries() }
        }
    }

    // MARK: - Time Range Bar

    private var timeRangeBar: some View {
        HStack(spacing: 0) {
            // Time range picker
            HStack(spacing: 0) {
                ForEach(WeightViewModel.TimeRange.allCases, id: \.self) { range in
                    Button {
                        viewModel.selectedTimeRange = range
                        viewModel.loadEntries()
                    } label: {
                        Text(range.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewModel.selectedTimeRange == range ? Theme.accent.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(viewModel.selectedTimeRange == range ? .white : .secondary)
                    }
                }
            }

            Spacer()

            // Granularity toggle
            Menu {
                Button { viewModel.granularity = .daily } label: {
                    Label("Daily", systemImage: viewModel.granularity == .daily ? "checkmark" : "")
                }
                Button { viewModel.granularity = .weekly } label: {
                    Label("Weekly", systemImage: viewModel.granularity == .weekly ? "checkmark" : "")
                }
            } label: {
                Text(viewModel.granularity == .daily ? "D" : "W")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Averages

    private var averagesSection: some View {
        let weeklyAvgs = viewModel.weeklyAverages
        let monthlyAvg = viewModel.currentMonthAverage

        return VStack(alignment: .leading, spacing: 10) {
            Text("Averages")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                if let thisWeek = weeklyAvgs.first {
                    averageCard(
                        title: "This Week",
                        value: String(format: "%.1f", viewModel.weightUnit.convert(fromKg: thisWeek.average)),
                        unit: viewModel.weightUnit.displayName,
                        detail: "\(thisWeek.count) weigh-ins"
                    )
                }

                if let lastWeek = weeklyAvgs.dropFirst().first {
                    let change = weeklyAvgs.first.map { $0.average - lastWeek.average }
                    averageCard(
                        title: "Last Week",
                        value: String(format: "%.1f", viewModel.weightUnit.convert(fromKg: lastWeek.average)),
                        unit: viewModel.weightUnit.displayName,
                        detail: change.map { c in
                            let d = viewModel.weightUnit.convert(fromKg: c)
                            return "\(d >= 0 ? "+" : "")\(String(format: "%.1f", d)) vs this week"
                        } ?? ""
                    )
                }

                if let monthly = monthlyAvg {
                    averageCard(
                        title: DateFormatters.monthYear.string(from: Date()),
                        value: String(format: "%.1f", viewModel.weightUnit.convert(fromKg: monthly.average)),
                        unit: viewModel.weightUnit.displayName,
                        detail: "\(monthly.count) weigh-ins"
                    )
                }
            }
        }
    }

    private func averageCard(title: String, value: String, unit: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "scalemass")
                .font(.system(size: 48))
                .foregroundStyle(Theme.accent.opacity(0.5))
            Text("No Weight Data")
                .font(.headline)
            Text("Log your first weight or sync from Apple Health.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Sync from Apple Health") {
                Task {
                    _ = try? await HealthKitService.shared.syncWeight()
                    viewModel.loadEntries()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Button("Log Weight Manually") { showingAddWeight = true }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
