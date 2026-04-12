import SwiftUI
import Charts

struct SupplementsTabView: View {
    @State private var viewModel = SupplementViewModel()
    @State private var showingAdd = false
    @State private var showingEditSupp = false
    @State private var editSupp: Supplement?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // Status + streak
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.takenCount)/\(viewModel.totalCount)")
                                .font(.title.weight(.bold).monospacedDigit())
                                .foregroundStyle(viewModel.takenCount == viewModel.totalCount && viewModel.totalCount > 0 ? Theme.deficit : .primary)
                            Text("taken today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(viewModel.currentStreak)")
                                .font(.title.weight(.bold).monospacedDigit())
                                .foregroundStyle(viewModel.currentStreak > 0 ? Theme.accent : .secondary)
                            Text("day streak")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .card()

                    // Consistency heatmap (60 days)
                    if !viewModel.consistencyData.isEmpty {
                        consistencyGraph
                    }

                    // "Same as yesterday" — when nothing taken today but yesterday had logs
                    if viewModel.takenCount == 0 && viewModel.yesterdayHadSupplements {
                        Button {
                            viewModel.copyYesterday()
                        } label: {
                            Label("Same as yesterday", systemImage: "doc.on.doc")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.bordered).tint(Theme.accent)
                    }

                    // Checklist (only render card if supplements exist)
                    if !viewModel.supplements.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.supplements.enumerated()), id: \.element.id) { index, supplement in
                            Button {
                                if let id = supplement.id { viewModel.toggleTaken(supplementId: id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: viewModel.isTaken(supplement.id ?? 0) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(viewModel.isTaken(supplement.id ?? 0) ? Theme.deficit : .secondary)
                                        .accessibilityHidden(true)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(supplement.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if !supplement.dosageDisplay.isEmpty {
                                            Text(supplement.dosageDisplay)
                                                .font(.caption).foregroundStyle(.tertiary)
                                        }
                                    }

                                    Spacer()

                                    // Delete button
                                    if let id = supplement.id {
                                        Button {
                                            SupplementService.deleteSupplement(id: id)
                                            viewModel.loadSupplements()
                                        } label: {
                                            Image(systemName: "xmark.circle.fill").font(.caption2).foregroundStyle(.tertiary)
                                        }.buttonStyle(.plain)
                                    }

                                    if viewModel.isTaken(supplement.id ?? 0),
                                       let log = viewModel.todayLogs[supplement.id ?? 0],
                                       let takenAt = log.takenAt {
                                        Text(formatTime(takenAt))
                                            .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(supplement.name)\(supplement.dosageDisplay.isEmpty ? "" : ", \(supplement.dosageDisplay)"), \(viewModel.isTaken(supplement.id ?? 0) ? "taken" : "not taken")")
                            .accessibilityHint("Double tap to toggle")
                            .contextMenu {
                                if let id = supplement.id {
                                    Button {
                                        editSupp = supplement
                                        showingEditSupp = true
                                    } label: { Label("Edit", systemImage: "pencil") }
                                    Button(role: .destructive) {
                                        SupplementService.deleteSupplement(id: id)
                                        viewModel.loadSupplements()
                                    } label: { Label("Delete", systemImage: "trash") }
                                }
                            }

                            if index < viewModel.supplements.count - 1 {
                                Divider().overlay(Color.white.opacity(0.05))
                            }
                        }
                    }
                    .card()
                    } // end if supplements not empty

                    if viewModel.supplements.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "pill")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.accent.opacity(0.5))
                            Text("No supplements yet")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
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
            .sheet(isPresented: $showingEditSupp) {
                if let supp = editSupp {
                    EditSupplementSheet(supplement: supp) {
                        viewModel.loadSupplements()
                    }
                }
            }
            .onAppear {
                AIScreenTracker.shared.currentScreen = .supplements
                viewModel.loadSupplements()
            }
        }
    }

    // MARK: - Consistency Graph

    private var consistencyGraph: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Consistency")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(viewModel.thirtyDayAverage * 100))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(viewModel.thirtyDayAverage > 0.8 ? Theme.deficit : viewModel.thirtyDayAverage > 0.5 ? Theme.fatYellow : Theme.surplus)
                Text("last 30d")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            // GitHub-style heatmap grid (60 days, 7 rows)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 10)

            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(viewModel.consistencyData) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(colorForRatio(day.ratio))
                        .frame(height: 16)
                        .overlay {
                            if Calendar.current.isDateInToday(day.date) {
                                RoundedRectangle(cornerRadius: 3)
                                    .strokeBorder(Theme.accent, lineWidth: 1.5)
                            }
                        }
                }
            }

            // Legend
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(.tertiary)
                ForEach([0.0, 0.33, 0.66, 1.0], id: \.self) { ratio in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForRatio(ratio))
                        .frame(width: 12, height: 12)
                }
                Text("All").font(.caption2).foregroundStyle(.tertiary)
                Spacer()

                // Month labels
                if let first = viewModel.consistencyData.first, let last = viewModel.consistencyData.last {
                    Text("\(DateFormatters.shortDisplay.string(from: first.date)) – \(DateFormatters.shortDisplay.string(from: last.date))")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }

            // Bar chart: daily completion rate over last 30 days
            let last30 = viewModel.consistencyData.suffix(30)
            Chart {
                ForEach(Array(last30)) { day in
                    BarMark(
                        x: .value("", day.date),
                        y: .value("", day.ratio)
                    )
                    .foregroundStyle(colorForRatio(day.ratio))
                    .cornerRadius(2)
                }
            }
            .chartYScale(domain: 0...1)
            .chartYAxis {
                AxisMarks(values: [0, 0.5, 1]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.2))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v * 100))%").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 80)
        }
        .card()
    }

    private func colorForRatio(_ ratio: Double) -> Color {
        switch ratio {
        case 0: Theme.cardBackgroundElevated
        case ..<0.34: Theme.surplus.opacity(0.5)
        case ..<0.67: Theme.fatYellow.opacity(0.6)
        case ..<1.0: Theme.deficit.opacity(0.6)
        default: Theme.deficit // 100%
        }
    }

    private func formatTime(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}

// MARK: - Edit Supplement Sheet

private struct EditSupplementSheet: View {
    let supplement: Supplement
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var dosage: String
    @State private var unit: String
    @State private var dailyDoses: Int

    init(supplement: Supplement, onSave: @escaping () -> Void) {
        self.supplement = supplement; self.onSave = onSave
        _name = State(initialValue: supplement.name)
        _dosage = State(initialValue: supplement.dosage ?? "")
        _unit = State(initialValue: supplement.unit ?? "")
        _dailyDoses = State(initialValue: supplement.dailyDoses)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Supplement") { TextField("Name", text: $name) }
                Section("Dosage") {
                    HStack {
                        TextField("Amount", text: $dosage).keyboardType(.decimalPad).frame(width: 80)
                        TextField("Unit (g, mg, ml...)", text: $unit)
                    }
                    Stepper("Daily doses: \(dailyDoses)", value: $dailyDoses, in: 1...5)
                }
            }
            .navigationTitle("Edit Supplement").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let id = supplement.id {
                            SupplementService.updateSupplement(
                                id: id, name: name,
                                dosage: dosage.isEmpty ? nil : dosage,
                                unit: unit.isEmpty ? nil : unit,
                                dailyDoses: dailyDoses)
                        }
                        onSave(); dismiss()
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}
