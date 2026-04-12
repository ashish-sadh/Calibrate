import SwiftUI

struct LabReportDetailView: View {
    let report: LabReport
    @State private var results: [BiomarkerResult] = []
    @State private var showingDeleteAlert = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                reportHeader
                if results.isEmpty {
                    Text("No biomarkers extracted from this report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 40)
                } else {
                    summaryDonut
                    biomarkersByCategory
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Lab Report")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) { showingDeleteAlert = true } label: {
                    Image(systemName: "trash").foregroundStyle(Theme.surplus)
                }
            }
        }
        .alert("Delete Report?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) { deleteReport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this lab report and all associated biomarker values.")
        }
        .onAppear { loadResults() }
    }

    // MARK: - Header

    private var reportHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.labName ?? "Lab Report")
                        .font(.headline)
                    Text(report.displayDate)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider().overlay(Color.white.opacity(0.05))

            HStack {
                Label("\(report.markerCount) biomarkers scanned", systemImage: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let name = report.labName {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .card()
    }

    // MARK: - Summary

    private var statusCounts: (optimal: Int, sufficient: Int, outOfRange: Int) {
        var o = 0, s = 0, r = 0
        for result in results {
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

    private var summaryDonut: some View {
        let counts = statusCounts

        return HStack(spacing: 20) {
            DonutRing(optimal: counts.optimal, sufficient: counts.sufficient, outOfRange: counts.outOfRange)
                .frame(width: 80, height: 80)

            VStack(alignment: .leading, spacing: 6) {
                summaryRow(icon: "checkmark.circle.fill", label: "Optimal", count: counts.optimal, color: Theme.deficit)
                summaryRow(icon: "circle.fill", label: "Sufficient", count: counts.sufficient, color: Theme.fatYellow)
                summaryRow(icon: "exclamationmark.triangle.fill", label: "Out of Range", count: counts.outOfRange, color: Theme.stepsOrange)
            }
            Spacer()
        }
        .card()
    }

    private func summaryRow(icon: String, label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .font(.subheadline.weight(.bold).monospacedDigit())
        }
    }

    // MARK: - Results by Category

    private var groupedByCategory: [(category: String, items: [(BiomarkerResult, BiomarkerDefinition)])] {
        let mapped = results.compactMap { result -> (BiomarkerResult, BiomarkerDefinition)? in
            guard let def = BiomarkerKnowledgeBase.byId[result.biomarkerId] else { return nil }
            return (result, def)
        }

        var groups: [(String, [(BiomarkerResult, BiomarkerDefinition)])] = []
        for category in BiomarkerKnowledgeBase.categories {
            let items = mapped.filter { $0.1.category == category }
            if !items.isEmpty { groups.append((category, items)) }
        }
        return groups
    }

    private var biomarkersByCategory: some View {
        VStack(spacing: 14) {
            ForEach(groupedByCategory, id: \.category) { group in
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.category.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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

    // MARK: - Actions

    private func loadResults() {
        guard let id = report.id else { return }
        results = BiomarkerService.fetchBiomarkerResults(forReportId: id)
    }

    private func deleteReport() {
        guard let id = report.id else { return }
        if !report.fileDataHash.isEmpty {
            LabReportStorage.delete(hash: report.fileDataHash)
        }
        BiomarkerService.deleteLabReport(id: id)
        dismiss()
    }
}
