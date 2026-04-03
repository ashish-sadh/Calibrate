import SwiftUI
import Charts

struct WeightTabView: View {
    @Binding var syncComplete: Bool
    @Binding var selectedTab: Int
    @State private var viewModel = WeightViewModel()
    @State private var showingAddWeight = false
    @State private var showLog = false

    var body: some View {
        NavigationStack {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        timeRangeBar

                        // Chart — hero element (no card background, floats on page)
                        WeightChartView(trend: viewModel.trend, unit: viewModel.weightUnit, granularity: viewModel.granularity)
                            .frame(height: 240)

                        // Compact metrics + weight changes
                        if let fullTrend = viewModel.fullTrend {
                            WeightInsightsView(trend: fullTrend, unit: viewModel.weightUnit, isLosing: viewModel.isLosing)
                        }

                        // Collapsible history log
                        logSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { selectedTab = 0 } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddWeight = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingAddWeight) {
            WeightEntryView(unit: viewModel.weightUnit) { value, date in viewModel.addWeight(value: value, date: date) }
        }
        .onAppear { viewModel.loadEntries() }
        .task {
            #if !targetEnvironment(simulator)
            let _ = try? await HealthKitService.shared.syncWeight()
            viewModel.loadEntries()
            #endif
        }
        .onChange(of: syncComplete) { _, done in
            if done { viewModel.loadEntries() }
        }
    }

    // MARK: - Time Range Bar

    private var timeRangeBar: some View {
        HStack(spacing: 0) {
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

    // MARK: - Collapsible Log

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLog.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text("History")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(viewModel.allEntries.count) entries")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.accent)
                        .rotationEffect(.degrees(showLog ? 0 : -90))
                }
                .card()
            }
            .buttonStyle(.plain)

            if showLog {
                WeightLogListView(
                    entries: viewModel.allEntries,
                    unit: viewModel.weightUnit,
                    onDelete: { viewModel.deleteWeight(id: $0) },
                    isLosing: viewModel.isLosing
                )
                .transition(.opacity)
            }
        }
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
