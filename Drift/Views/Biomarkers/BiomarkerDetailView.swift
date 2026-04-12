import SwiftUI
import Charts

struct BiomarkerDetailView: View {
    let definition: BiomarkerDefinition
    @State private var results: [BiomarkerResult] = []
    @State private var reportDates: [Int64: String] = [:]
    @State private var expandedSections: Set<String> = []

    private var latestResult: BiomarkerResult? { results.last }
    private var latestStatus: BiomarkerStatus? {
        guard let r = latestResult else { return nil }
        return definition.status(for: r.normalizedValue)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerSection
                if let result = latestResult {
                    statusCard(result: result)
                }
                if !results.isEmpty {
                    latestValueSection
                    trendChart
                    allRecordingsButton
                }
                impactSection
                knowledgeSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(statusGradientBackground)
        .navigationTitle("Biomarker Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { loadResults() }
    }

    // MARK: - Gradient Background

    private var statusGradientBackground: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if let status = latestStatus {
                LinearGradient(
                    colors: [statusTintColor(status).opacity(0.15), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(definition.name)
                .font(.title2.weight(.bold))

            Text(definition.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Category tags
            FlowLayout(spacing: 6) {
                ForEach(definition.impactCategories, id: \.self) { cat in
                    Text(cat)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.cardBackgroundElevated, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1), lineWidth: 1))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Status Card

    private func statusCard(result: BiomarkerResult) -> some View {
        let status = definition.status(for: result.normalizedValue)
        let interpretation = statusInterpretation(status: status)

        return VStack(alignment: .leading, spacing: 6) {
            Text(interpretation)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(statusTintColor(status).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Latest Value

    private var latestValueSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LATEST")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatValue(latestResult?.normalizedValue ?? 0))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                Text(definition.unit)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Trend Chart

    private var trendChart: some View {
        let data = chartData

        return VStack(alignment: .leading, spacing: 8) {
            // Legend
            HStack(spacing: 10) {
                chartLegendItem("Out of Range", color: Theme.stepsOrange, dashed: true)
                chartLegendItem("Sufficient", color: Theme.fatYellow, dashed: true)
                chartLegendItem("Optimal", color: Theme.deficit, dashed: true)
            }

            Chart {
                // Zone backgrounds: optimal (green), sufficient (yellow), out of range (implicit)
                RectangleMark(yStart: .value("", definition.optimalLow), yEnd: .value("", definition.optimalHigh))
                    .foregroundStyle(Theme.deficit.opacity(0.08))
                // Sufficient zone below optimal
                if definition.sufficientLow < definition.optimalLow {
                    RectangleMark(yStart: .value("", definition.sufficientLow), yEnd: .value("", definition.optimalLow))
                        .foregroundStyle(Theme.fatYellow.opacity(0.06))
                }
                // Sufficient zone above optimal
                if definition.sufficientHigh > definition.optimalHigh {
                    RectangleMark(yStart: .value("", definition.optimalHigh), yEnd: .value("", definition.sufficientHigh))
                        .foregroundStyle(Theme.fatYellow.opacity(0.06))
                }

                // Threshold lines with annotations showing the range values
                RuleMark(y: .value("", definition.optimalLow))
                    .foregroundStyle(Theme.deficit.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .leading, spacing: 2) {
                        Text(formatValue(definition.optimalLow))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.deficit)
                    }
                RuleMark(y: .value("", definition.optimalHigh))
                    .foregroundStyle(Theme.deficit.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .leading, spacing: 2) {
                        Text(formatValue(definition.optimalHigh))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.deficit)
                    }
                // Sufficient threshold line (if different from optimal)
                if definition.sufficientHigh > definition.optimalHigh {
                    RuleMark(y: .value("", definition.sufficientHigh))
                        .foregroundStyle(Theme.fatYellow.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 5]))
                        .annotation(position: .leading, spacing: 2) {
                            Text(formatValue(definition.sufficientHigh))
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.fatYellow)
                        }
                }

                // Data line + points
                ForEach(data.indices, id: \.self) { i in
                    LineMark(
                        x: .value("Date", data[i].date),
                        y: .value("Value", data[i].value)
                    )
                    .foregroundStyle(.white.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("Date", data[i].date),
                        y: .value("Value", data[i].value)
                    )
                    .foregroundStyle(.white)
                    .symbolSize(40)
                    .annotation(position: .top, spacing: 4) {
                        Text(formatValue(data[i].value))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
            }
            .chartYScale(domain: chartYRange)
            .chartYAxis {
                AxisMarks(values: chartYAxisValues) { mark in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3)).foregroundStyle(.secondary.opacity(0.3))
                    AxisValueLabel().foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks { mark in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day()).foregroundStyle(.secondary)
                }
            }
            .frame(height: 220)
        }
        .card()
    }

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    private var chartData: [ChartPoint] {
        let iso = ISO8601DateFormatter()
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"

        return results.compactMap { result in
            let dateStr = reportDates[result.reportId] ?? ""
            let date = dateFmt.date(from: dateStr) ?? iso.date(from: result.createdAt) ?? Date()
            return ChartPoint(date: date, value: result.normalizedValue)
        }.sorted { $0.date < $1.date }
    }

    private var chartYRange: ClosedRange<Double> {
        let values = results.map(\.normalizedValue)
        let allValues = values + [definition.optimalLow, definition.optimalHigh, definition.sufficientHigh]
        let lo = max(0, (allValues.min() ?? 0) * 0.8)
        let hi = (allValues.max() ?? 100) * 1.2
        return lo...hi
    }

    /// Y-axis tick marks include the threshold values so users can see exact boundaries.
    private var chartYAxisValues: [Double] {
        var values: Set<Double> = [definition.optimalLow, definition.optimalHigh]
        if definition.sufficientHigh > definition.optimalHigh {
            values.insert(definition.sufficientHigh)
        }
        if definition.sufficientLow < definition.optimalLow {
            values.insert(definition.sufficientLow)
        }
        return values.sorted()
    }

    private func chartLegendItem(_ label: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 3) {
            Rectangle()
                .fill(color)
                .frame(width: 12, height: 2)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - All Recordings

    private var allRecordingsButton: some View {
        VStack(spacing: 0) {
            ForEach(results.reversed(), id: \.id) { result in
                let dateStr = reportDates[result.reportId] ?? ""
                let status = definition.status(for: result.normalizedValue)

                HStack {
                    Image(systemName: status.iconName)
                        .font(.caption)
                        .foregroundStyle(statusTintColor(status))
                    Text(formatDisplayDate(dateStr))
                        .font(.subheadline)
                    Spacer()
                    Text(formatValue(result.normalizedValue))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                    Text(result.normalizedUnit)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 8)

                if result.id != results.first?.id {
                    Divider().overlay(Color.white.opacity(0.05))
                }
            }
        }
        .card()
    }

    // MARK: - Impact Section

    private var impactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IMPACT ON HEALTHSPAN")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(definition.whyItMatters)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if !definition.impactCategories.isEmpty {
                Text("IMPACTED CATEGORIES")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)

                FlowLayout(spacing: 6) {
                    ForEach(definition.impactCategories, id: \.self) { cat in
                        Text(cat.uppercased())
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Knowledge Base Accordions

    private var knowledgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Learn about \(definition.name)")
                .font(.headline)
                .padding(.top, 4)

            accordionItem(
                title: "What is \(definition.name)?",
                key: "what",
                content: definition.description
            )
            accordionItem(
                title: "Why it matters",
                key: "why",
                content: definition.whyItMatters
            )
            accordionItem(
                title: "Relationship to other biomarkers",
                key: "rel",
                content: definition.relationships
            )
            accordionItem(
                title: "How to improve",
                key: "improve",
                content: definition.howToImprove
            )
            accordionItem(
                title: "Impact on your health",
                key: "metrics",
                content: definition.healthMetrics
            )
        }
        .card()
    }

    private func accordionItem(title: String, key: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if expandedSections.contains(key) {
                        expandedSections.remove(key)
                    } else {
                        expandedSections.insert(key)
                    }
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: expandedSections.contains(key) ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            if expandedSections.contains(key) {
                Text(content)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }

            Divider().overlay(Color.white.opacity(0.05))
        }
    }

    // MARK: - Helpers

    private func statusInterpretation(status: BiomarkerStatus) -> String {
        let name = definition.name
        switch status {
        case .optimal:
            return "\(name) is in the optimal range, supporting excellent health and performance."
        case .sufficient:
            return "\(name) is in a sufficient range but could be optimized further for peak performance and longevity."
        case .outOfRange:
            return "\(name) is outside the healthy range. Consider lifestyle changes and consult a healthcare provider."
        }
    }

    private func statusTintColor(_ status: BiomarkerStatus) -> Color {
        switch status {
        case .optimal: Theme.deficit
        case .sufficient: Theme.fatYellow
        case .outOfRange: Theme.stepsOrange
        }
    }

    private func formatValue(_ value: Double) -> String {
        value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func formatDisplayDate(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3 else { return dateStr }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let m = Int(parts[1]) ?? 0
        let d = Int(parts[2]) ?? 0
        guard m > 0, m <= 12 else { return dateStr }
        return "\(months[m]) \(d), \(parts[0])"
    }

    private func loadResults() {
        results = BiomarkerService.fetchBiomarkerResults(forBiomarkerId: definition.id)
        // Load report dates for each result
        for result in results {
            if reportDates[result.reportId] == nil {
                reportDates[result.reportId] = BiomarkerService.fetchReportDate(forId: result.reportId)
            }
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            if index < result.positions.count {
                subview.place(at: CGPoint(
                    x: bounds.minX + result.positions[index].x,
                    y: bounds.minY + result.positions[index].y
                ), proposal: .unspecified)
            }
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return LayoutResult(
            positions: positions,
            size: CGSize(width: maxX, height: y + rowHeight)
        )
    }
}
