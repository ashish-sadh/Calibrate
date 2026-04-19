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
    @State private var editingEntry: WeightEntry?
    @AppStorage("drift_dismissed_outlier") private var dismissedOutlierDate = ""

    var body: some View {
        NavigationStack {
            if viewModel.entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        timeRangeBar

                        // Chart — hero element
                        WeightChartView(trend: viewModel.trend, unit: viewModel.weightUnit, granularity: viewModel.granularity, rawEntries: viewModel.entries)
                            .frame(height: 260)

                        // Big change banner
                        bigChangeBanner

                        // Compact metrics + weight changes
                        if let fullTrend = viewModel.fullTrend {
                            WeightInsightsView(trend: fullTrend, unit: viewModel.weightUnit, entries: viewModel.allEntries, isLosing: viewModel.isLosing,
                                              onAddWeight: { showingAddWeight = true },
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
                .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddWeight = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Add weight")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .sheet(isPresented: $showingAddWeight, onDismiss: {
            viewModel.loadEntries()
        }) {
            let latestComp = WeightServiceAPI.latestBodyComposition()
            WeightEntryView(
                unit: viewModel.weightUnit,
                lastBodyFat: latestComp?.bodyFatPct,
                lastBMI: latestComp?.bmi,
                lastWater: latestComp?.waterPct,
                onSave: { value, date in
                    viewModel.addWeight(value: value, date: date)
                },
                onSaveBodyComp: { comp in
                    var entry = comp
                    WeightServiceAPI.saveBodyComposition(&entry)
                    viewModel.loadEntries()
                }
            )
        }
        .sheet(isPresented: $showingAddBodyComp) {
            let latestComp = WeightServiceAPI.latestBodyComposition()
            WeightEntryView(
                unit: viewModel.weightUnit,
                lastBodyFat: latestComp?.bodyFatPct,
                lastBMI: latestComp?.bmi,
                lastWater: latestComp?.waterPct,
                onSave: { value, date in
                    viewModel.addWeight(value: value, date: date)
                },
                onSaveBodyComp: { comp in
                    var entry = comp
                    WeightServiceAPI.saveBodyComposition(&entry)
                    viewModel.loadEntries()
                }
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
        .sheet(item: $editingEntry) { entry in
            WeightEntryView(unit: viewModel.weightUnit, initialWeight: entry.weightKg, initialDate: entry.date) { value, date in
                viewModel.addWeight(value: value, date: date)
            }
        }
    }

    // MARK: - Big Change Banner

    @ViewBuilder
    private var bigChangeBanner: some View {
        let entries = viewModel.allEntries
        if entries.count >= 2 {
            let latest = entries[0]
            let previous = entries[1]
            let change = latest.weightKg - previous.weightKg
            let pctChange = abs(change) / previous.weightKg
            if pctChange > 0.10 && dismissedOutlierDate != latest.date {
                let unit = viewModel.weightUnit
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.fatYellow)
                        Text("Big change: \(String(format: "%.1f", unit.convert(fromKg: previous.weightKg))) → \(String(format: "%.1f", unit.convert(fromKg: latest.weightKg))) \(unit.displayName)")
                            .font(.caption.weight(.medium))
                    }
                    HStack(spacing: 12) {
                        Button {
                            dismissedOutlierDate = latest.date
                        } label: {
                            Text("That's correct").font(.caption2.weight(.medium))
                        }.buttonStyle(.bordered).tint(Theme.deficit)

                        Button {
                            editingEntry = latest
                        } label: {
                            Text("Edit").font(.caption2.weight(.medium))
                        }.buttonStyle(.bordered)

                        Button {
                            if let id = latest.id { viewModel.deleteWeight(id: id) }
                        } label: {
                            Text("Remove").font(.caption2.weight(.medium))
                        }.buttonStyle(.bordered).tint(Theme.surplus)
                    }
                }
                .padding(12)
                .background(Theme.fatYellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
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
            .accessibilityLabel(viewModel.granularity == .daily ? "Granularity: Daily" : "Granularity: Weekly")
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
                    onEdit: { editingEntry = $0 },
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
