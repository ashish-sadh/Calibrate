import SwiftUI
import DriftCore
#if !os(Android)
// Swift Charts is absent on SkipUI — the adherence plot falls back to
// SupplementAdherenceBars below (skip_fuse_is_the_availability_tree).
import Charts
#endif

struct SupplementsTabView: View {
    @State var viewModel = SupplementViewModel()
    @State var showingAdd = false
    @State var showingEditSupp = false
    @State var editSupp: Supplement?

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
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(viewModel.currentStreak)")
                                .font(.title.weight(.bold).monospacedDigit())
                                .foregroundStyle(viewModel.currentStreak > 0 ? Theme.accent : .secondary)
                            Text("day streak")
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
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
                            // Unmapped in skip-ui's native set, so raw it drew the
                            // warning triangle; sym() already carries the duplicate
                            // → arrow.clockwise.circle mapping.
                            Label("Same as yesterday", systemImage: sym("doc.on.doc"))
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
                                    #if os(Android)
                                    // "circle" is deliberately unmapped in sym() — Material
                                    // has no outline circle and a checkmark fallback reads as
                                    // the OPPOSITE state — so an un-taken row drew the warning
                                    // triangle. Third call site of the same trap after
                                    // ActiveWorkoutView's set-done toggle and the exercise
                                    // picker's row selection; same fix, draw the real ring.
                                    if viewModel.isTaken(supplement.id ?? 0) {
                                        Image(systemName: sym("checkmark.circle.fill"))
                                            .font(.title3)
                                            .foregroundStyle(Theme.deficit)
                                            .accessibilityHidden(true)
                                    } else {
                                        // `.stroke` not `.strokeBorder` — SkipUI's
                                        // strokeBorder overload set is ambiguous here.
                                        Circle()
                                            .stroke(Color.secondary, lineWidth: 1.5)
                                            .frame(width: 21, height: 21)
                                    }
                                    #else
                                    Image(systemName: viewModel.isTaken(supplement.id ?? 0) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(viewModel.isTaken(supplement.id ?? 0) ? Theme.deficit : .secondary)
                                        .accessibilityHidden(true)
                                    #endif

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(supplement.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        if !supplement.dosageDisplay.isEmpty {
                                            Text(supplement.dosageDisplay)
                                                .font(.caption).foregroundStyle(Theme.textTertiary)
                                        }
                                    }

                                    Spacer()

                                    // Delete button
                                    if let id = supplement.id {
                                        Button {
                                            SupplementService.deleteSupplement(id: id)
                                            viewModel.loadSupplements()
                                        } label: {
                                            // Unmapped on Android without sym(): this was the
                                            // only ⊗ in the codebase bypassing it, and it drew
                                            // Material's "missing icon" placeholder. The map
                                            // already has xmark.circle.fill → xmark and passes
                                            // through on Darwin (FoodTabView:1093 idiom).
                                            Image(systemName: sym("xmark.circle.fill")).font(.caption2).foregroundStyle(Theme.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                        // A caption2 glyph dumps as a 21dp node on Fuse — under
                                        // the touch floor — and a nested .plain Button inside
                                        // the row Button carries no hit shape of its own, so
                                        // the tap landed on the row and toggled instead of
                                        // deleting (#1174 recipe,
                                        // harness_dead_synthetic_tap_means_contentshape).
                                        // Android-gated: un-gated it would shift iOS row
                                        // geometry.
                                        #if os(Android)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                        #endif
                                        .accessibilityLabel(Text("Delete \(supplement.name)"))
                                    }

                                    if viewModel.isTaken(supplement.id ?? 0),
                                       let log = viewModel.todayLogs[supplement.id ?? 0],
                                       let takenAt = log.takenAt {
                                        Text(formatTime(takenAt))
                                            .font(.caption2.monospacedDigit()).foregroundStyle(Theme.textTertiary)
                                    }
                                }
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("\(supplement.name)\(supplement.dosageDisplay.isEmpty ? "" : ", \(supplement.dosageDisplay)"), \(viewModel.isTaken(supplement.id ?? 0) ? "taken" : "not taken")"))
                            // accessibilityHint is unavailable on SkipUI — the
                            // label above already says taken/not taken.
                            #if !os(Android)
                            .accessibilityHint(Text("Double tap to toggle"))
                            #endif
                            // contextMenu is gated off on Android — it steals
                            // focus and its builder is EAGER on Fuse
                            // (skipui_interaction_api_traps). The row's own
                            // ⊗ button is the delete path there; edit arrives
                            // with the Android edit sheet.
                            #if !os(Android)
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
                            #endif

                            if index < viewModel.supplements.count - 1 {
                                Divider().overlay(Theme.separator)
                            }
                        }
                    }
                    .card()
                    } // end if supplements not empty

                    if viewModel.supplements.isEmpty {
                        VStack(spacing: 12) {
                            #if os(Android)
                            // "pill" is unmapped in skip-ui's Material set and
                            // rendered the warning triangle here (verified on
                            // the emulator). A capsule on the diagonal IS the
                            // glyph — no Path needed.
                            Capsule()
                                .fill(Theme.accent.opacity(0.5))
                                .frame(width: 46, height: 22)
                                .rotationEffect(.degrees(-45))
                                .frame(height: 46)
                            #else
                            Image(systemName: "pill")
                                .font(.system(size: Theme.FontSize.display2))
                                .foregroundStyle(Theme.accent.opacity(0.5))
                            #endif
                            Text("No supplements yet")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            Button { showingAdd = true } label: {
                                Label("Add Supplement", systemImage: "plus.circle.fill")
                                    .font(.caption)
                            }.buttonStyle(.bordered).tint(Theme.accent)
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
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    }
                    .accessibilityLabel(Text("Add supplement"))
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
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("\(Int(viewModel.thirtyDayAverage * 100))%")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(viewModel.thirtyDayAverage > 0.8 ? Theme.deficit : viewModel.thirtyDayAverage > 0.5 ? Theme.fatYellow : Theme.surplus)
                Text("last 30d")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
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
                Text("Less").font(.caption2).foregroundStyle(Theme.textTertiary)
                ForEach([0.0, 0.33, 0.66, 1.0], id: \.self) { ratio in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForRatio(ratio))
                        .frame(width: 12, height: 12)
                }
                Text("All").font(.caption2).foregroundStyle(Theme.textTertiary)
                Spacer()

                // Month labels
                if let first = viewModel.consistencyData.first, let last = viewModel.consistencyData.last {
                    Text("\(DateFormatters.shortDisplay.string(from: first.date)) – \(DateFormatters.shortDisplay.string(from: last.date))")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }

            // Bar chart: daily completion rate over last 30 days
            let last30 = viewModel.consistencyData.suffix(30)
            #if os(Android)
            // Swift Charts does not exist on SkipUI
            // (skip_fuse_is_the_availability_tree) — same constraint that made
            // WeightChartAndroid a Path chart. Bars are plain capsules in an
            // HStack, which needs no Canvas and no GeometryReader-per-frame.
            SupplementAdherenceBars(days: Array(last30))
            #else
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
                            Text("\(Int(v * 100))%").font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 80)
            #endif
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
        guard let d = DateFormatters.iso8601.date(from: iso) else { return "" }
        return DateFormatters.shortTime.string(from: d)
    }
}

// MARK: - Edit Supplement Sheet

/// Internal, not private — Skip cannot bridge private views to Android.
struct EditSupplementSheet: View {
    let supplement: Supplement
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    @State var name: String
    @State var dosage: String
    @State var unit: String
    @State var dailyDoses: Int

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

/// Android's stand-in for the Swift Charts adherence plot: Charts is absent on
/// SkipUI (skip_fuse_is_the_availability_tree), so daily completion is drawn as
/// plain capsules in an HStack — no Canvas, no per-frame GeometryReader. Keeps
/// the iOS gridline reading (0 / 50 / 100%) as a labelled backdrop.
struct SupplementAdherenceBars: View {
    let days: [SupplementViewModel.DayConsistency]

    private static let plotHeight: CGFloat = 80

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ZStack(alignment: .bottom) {
                // Gridlines at 0 / 50 / 100% so a half-height bar is readable
                // without an axis renderer.
                VStack(spacing: 0) {
                    gridline
                    Spacer()
                    gridline
                    Spacer()
                    gridline
                }
                .frame(height: Self.plotHeight)

                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(days) { day in
                        Capsule()
                            .fill(barColor(day.ratio))
                            // Zero-adherence days keep a 2pt stub so the day
                            // still reads as "logged nothing", not "no data".
                            .frame(height: max(2, Self.plotHeight * day.ratio))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: Self.plotHeight)
            }
            VStack(alignment: .trailing) {
                Text("100%")
                Spacer()
                Text("50%")
                Spacer()
                Text("0%")
            }
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .frame(height: Self.plotHeight)
        }
    }

    private var gridline: some View {
        Rectangle().fill(Theme.separator.opacity(0.6)).frame(height: 0.5)
    }

    /// Mirrors `SupplementsTabView.colorForRatio` — kept local rather than
    /// hoisted because the two live in one file and the tenet is three
    /// similar lines before extracting.
    private func barColor(_ ratio: Double) -> Color {
        switch ratio {
        case 0: return Theme.cardBackgroundElevated
        case ..<0.34: return Theme.surplus.opacity(0.5)
        case ..<0.67: return Theme.fatYellow.opacity(0.6)
        case ..<1.0: return Theme.deficit.opacity(0.6)
        default: return Theme.deficit
        }
    }
}
