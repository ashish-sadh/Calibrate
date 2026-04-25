import SwiftUI
import DriftCore
import Charts

struct BiomarkersTabView: View {
    @State private var reports: [LabReport] = []
    @State private var latestResults: [BiomarkerResult] = []
    @State private var searchText = ""
    @State private var selectedFilter: BiomarkerStatus?
    @State private var showingUpload = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if latestResults.isEmpty {
                    emptyState
                } else {
                    donutSummary
                    reportsList
                    searchBar
                    filterChips
                    biomarkerList
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Biomarkers")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingUpload = true } label: {
                    Image(systemName: "doc.badge.plus").foregroundStyle(Theme.accent)
                }
            }
        }
        .sheet(isPresented: $showingUpload) {
            LabReportUploadView { reload() }
        }
        .onAppear { AIScreenTracker.shared.currentScreen = .biomarkers; reload() }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cross.case.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent.opacity(0.5))
            Text("No Lab Reports")
                .font(.headline)
            Text("Upload a lab report (PDF or photo) to track your blood biomarkers over time.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingUpload = true
            } label: {
                Label("Upload Lab Report", systemImage: "doc.badge.plus")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Donut Summary

    private var statusCounts: (optimal: Int, sufficient: Int, outOfRange: Int) {
        var o = 0, s = 0, r = 0
        for result in latestResults {
            if let def = BiomarkerKnowledgeBase.byId[result.biomarkerId] {
                switch def.status(for: result.normalizedValue) {
                case .optimal: o += 1
                case .sufficient: s += 1
                case .outOfRange: r += 1
                }
            }
        }
        return (o, s, r)
    }

    private var donutSummary: some View {
        let counts = statusCounts
        let total = counts.optimal + counts.sufficient + counts.outOfRange

        return VStack(spacing: 12) {
            ZStack {
                // Donut ring
                DonutRing(
                    optimal: counts.optimal,
                    sufficient: counts.sufficient,
                    outOfRange: counts.outOfRange
                )
                .frame(width: 160, height: 160)

                // Center label
                VStack(spacing: 2) {
                    Text("\(total)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                    Text("BIOMARKERS")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            // Legend
            HStack(spacing: 16) {
                legendItem(icon: "checkmark.circle.fill", label: "Optimal", count: counts.optimal, color: Theme.deficit)
                legendItem(icon: "circle.fill", label: "Sufficient", count: counts.sufficient, color: Theme.fatYellow)
                legendItem(icon: "exclamationmark.triangle.fill", label: "Out of Range", count: counts.outOfRange, color: Theme.stepsOrange)
            }

            if let latest = reports.first {
                Text("Last updated: \(latest.displayDate)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .card()
    }

    private func legendItem(icon: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.caption2.weight(.bold))
        }
    }

    // MARK: - Reports List

    private var reportsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LAB REPORTS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(reports) { report in
                NavigationLink {
                    LabReportDetailView(report: report)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(report.labName ?? "Lab Report")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("\(report.displayDate) · \(report.markerCount) biomarkers")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)

                if report.id != reports.last?.id {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
        .card()
    }

    // MARK: - Search & Filter

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            TextField("Search for Vitamin D, Cortisol, etc.", text: $searchText)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            filterChip("All", selected: selectedFilter == nil) { selectedFilter = nil }
            filterChip("Out of Range", selected: selectedFilter == .outOfRange) {
                selectedFilter = selectedFilter == .outOfRange ? nil : .outOfRange
            }
            filterChip("Sufficient", selected: selectedFilter == .sufficient) {
                selectedFilter = selectedFilter == .sufficient ? nil : .sufficient
            }
            filterChip("Optimal", selected: selectedFilter == .optimal) {
                selectedFilter = selectedFilter == .optimal ? nil : .optimal
            }
            Spacer()
        }
    }

    private func filterChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Theme.accent.opacity(0.3) : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(selected ? .white : .secondary)
        }
    }

    // MARK: - Biomarker List

    private var filteredResults: [(BiomarkerResult, BiomarkerDefinition)] {
        latestResults.compactMap { result in
            guard let def = BiomarkerKnowledgeBase.byId[result.biomarkerId] else { return nil }

            // Search filter
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                guard def.name.lowercased().contains(q) || def.category.lowercased().contains(q) else { return nil }
            }

            // Status filter
            if let filter = selectedFilter {
                guard def.status(for: result.normalizedValue) == filter else { return nil }
            }

            return (result, def)
        }
    }

    /// Results grouped by status, with out-of-range first.
    private var groupedResults: [(status: BiomarkerStatus, items: [(BiomarkerResult, BiomarkerDefinition)])] {
        let filtered = filteredResults
        var groups: [(BiomarkerStatus, [(BiomarkerResult, BiomarkerDefinition)])] = []
        for status in [BiomarkerStatus.outOfRange, .sufficient, .optimal] {
            let items = filtered.filter { $0.1.status(for: $0.0.normalizedValue) == status }
            if !items.isEmpty { groups.append((status, items)) }
        }
        return groups
    }

    private var biomarkerList: some View {
        VStack(spacing: 14) {
            ForEach(groupedResults, id: \.status) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(group.status.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(statusColor(group.status))
                        Spacer()
                        Text("\(group.items.count) Biomarkers")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 8)

                    ForEach(group.items, id: \.0.biomarkerId) { result, def in
                        NavigationLink {
                            BiomarkerDetailView(definition: def)
                        } label: {
                            BiomarkerRow(result: result, definition: def)
                        }
                        .buttonStyle(.plain)

                        if result.biomarkerId != group.items.last?.0.biomarkerId {
                            Divider().overlay(Color.white.opacity(0.05))
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: - Helpers

    private func statusColor(_ status: BiomarkerStatus) -> Color {
        switch status {
        case .optimal: Theme.deficit
        case .sufficient: Theme.fatYellow
        case .outOfRange: Theme.stepsOrange
        }
    }

    private func reload() {
        reports = BiomarkerService.fetchLabReports()
        latestResults = BiomarkerService.fetchLatestBiomarkerResults()
    }
}

// MARK: - Donut Ring

struct DonutRing: View {
    let optimal: Int
    let sufficient: Int
    let outOfRange: Int

    private var total: Double { Double(optimal + sufficient + outOfRange) }

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 8
            let lineWidth: CGFloat = 16

            guard total > 0 else { return }

            let segments: [(Double, Color)] = [
                (Double(optimal), Theme.deficit),
                (Double(sufficient), Theme.fatYellow),
                (Double(outOfRange), Theme.stepsOrange),
            ]

            var startAngle = Angle.degrees(-90)
            for (value, color) in segments {
                guard value > 0 else { continue }
                let sweep = Angle.degrees(360 * value / total)
                var path = Path()
                path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + sweep, clockwise: false)
                context.stroke(path, with: .color(color), lineWidth: lineWidth)
                startAngle = startAngle + sweep
            }
        }
    }
}

// MARK: - Biomarker Row

struct BiomarkerRow: View {
    let result: BiomarkerResult
    let definition: BiomarkerDefinition

    private var status: BiomarkerStatus { definition.status(for: result.normalizedValue) }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(definition.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text(formatValue(result.normalizedValue))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                Text(result.normalizedUnit)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                // Status badge
                HStack(spacing: 3) {
                    Image(systemName: status.iconName)
                        .font(.caption2)
                    Text(status.label)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(statusColor)
                Spacer()
                // AI-parsed badge — shown when Gemma extracted this value (not regex)
                if result.isAIParsed {
                    HStack(spacing: 2) {
                        Image(systemName: "cpu")
                            .font(.system(size: 8))
                        Text("AI")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(Theme.surplus.opacity(0.7))
                }
            }

            // Range bar
            RangeBar(definition: definition, value: result.normalizedValue)
                .frame(height: 4)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }

    private var statusColor: Color {
        switch status {
        case .optimal: Theme.deficit
        case .sufficient: Theme.fatYellow
        case .outOfRange: Theme.stepsOrange
        }
    }

    private func formatValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

// MARK: - Range Bar

struct RangeBar: View {
    let definition: BiomarkerDefinition
    let value: Double

    private var range: Double { definition.absoluteHigh - definition.absoluteLow }

    var body: some View {
        GeometryReader { geo in
            if range > 0 {
                let w = geo.size.width
                let optStart = CGFloat((definition.optimalLow - definition.absoluteLow) / range) * w
                let optEnd = CGFloat((definition.optimalHigh - definition.absoluteLow) / range) * w
                let sufStart = CGFloat((definition.sufficientLow - definition.absoluteLow) / range) * w
                let sufEnd = CGFloat((definition.sufficientHigh - definition.absoluteLow) / range) * w
                let pos = CGFloat(definition.normalizedPosition(for: value)) * w

                ZStack(alignment: .leading) {
                    // Background bar
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.stepsOrange.opacity(0.3))

                    // Sufficient zone
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.fatYellow.opacity(0.4))
                        .frame(width: max(0, sufEnd - sufStart))
                        .offset(x: sufStart)

                    // Optimal zone
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.deficit.opacity(0.5))
                        .frame(width: max(0, optEnd - optStart))
                        .offset(x: optStart)

                    // Value marker
                    Circle()
                        .fill(.white)
                        .frame(width: 8, height: 8)
                        .offset(x: max(0, min(w - 8, pos - 4)))
                }
            }
        }
    }
}
