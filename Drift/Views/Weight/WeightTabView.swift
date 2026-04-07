import SwiftUI
import Charts

struct WeightTabView: View {
    @Binding var syncComplete: Bool
    @Binding var selectedTab: Int
    @State private var viewModel = WeightViewModel()
    @State private var showingAddWeight = false
    @State private var showingAddBodyComp = false
    @State private var showLog = false
    @State private var showMilestone = false

    var body: some View {
        NavigationStack {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        timeRangeBar

                        // Chart — hero element
                        WeightChartView(trend: viewModel.trend, unit: viewModel.weightUnit, granularity: viewModel.granularity)
                            .frame(height: 260)

                        // Compact metrics + weight changes
                        if let fullTrend = viewModel.fullTrend {
                            WeightInsightsView(trend: fullTrend, unit: viewModel.weightUnit, entries: viewModel.allEntries, isLosing: viewModel.isLosing,
                                              onAddBodyComp: { showingAddBodyComp = true })
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
            WeightEntryView(unit: viewModel.weightUnit) { value, date in
                viewModel.addWeight(value: value, date: date)
            }
        }
        .sheet(isPresented: $showingAddBodyComp) {
            BodyCompEntryView(
                unit: viewModel.weightUnit,
                onSave: { weight, comp, date in
                    if let w = weight {
                        viewModel.addWeight(value: w, date: date)
                    }
                    if comp.hasData {
                        var entry = comp
                        try? AppDatabase.shared.saveBodyComposition(&entry)
                    }
                    viewModel.loadEntries()
                },
                lastBodyFat: (try? AppDatabase.shared.fetchLatestBodyComposition())?.bodyFatPct,
                lastBMI: (try? AppDatabase.shared.fetchLatestBodyComposition())?.bmi,
                lastWater: (try? AppDatabase.shared.fetchLatestBodyComposition())?.waterPct
            )
        }
        .onChange(of: viewModel.milestoneMessage) { _, message in
            if message != nil {
                showMilestone = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.5)) { showMilestone = false }
                    viewModel.milestoneMessage = nil
                }
            }
        }
        .overlay {
            if showMilestone, let msg = viewModel.milestoneMessage {
                VStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.title2).foregroundStyle(Theme.fatYellow)
                    Text(msg)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 28).padding(.vertical, 16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: Theme.accent.opacity(0.3), radius: 20)
                .scaleEffect(showMilestone ? 1.0 : 0.8)
                .opacity(showMilestone ? 1.0 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: showMilestone)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear { AIScreenTracker.shared.currentScreen = .weight; viewModel.loadEntries() }
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
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "scalemass.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent.opacity(0.4))

            VStack(spacing: 6) {
                Text("Track Your Weight")
                    .font(.title3.weight(.semibold))
                Text("Log your first weigh-in or sync from Apple Health to start tracking your progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            VStack(spacing: 10) {
                Button {
                    Task {
                        _ = try? await HealthKitService.shared.syncWeight()
                        viewModel.loadEntries()
                    }
                } label: {
                    Label("Sync from Apple Health", systemImage: "heart.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button { showingAddWeight = true } label: {
                    Label("Log Weight Manually", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)

            Spacer()
        }
        .padding(.horizontal, 32)
    }
}
