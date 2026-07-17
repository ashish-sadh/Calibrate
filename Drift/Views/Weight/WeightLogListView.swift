import SwiftUI
import DriftCore

struct WeightLogListView: View {
    let entries: [WeightEntry]
    let unit: WeightUnit
    let onDelete: (Int64) -> Void
    var onEdit: ((WeightEntry) -> Void)? = nil
    var isLosing: Bool = true

    private func changeColor(_ change: Double) -> Color {
        let isDecrease = change < -0.01
        let isIncrease = change > 0.01
        if isLosing {
            return isDecrease ? Theme.deficit : isIncrease ? Theme.surplus : .secondary
        } else {
            return isIncrease ? Theme.deficit : isDecrease ? Theme.surplus : .secondary
        }
    }

    private var monthGroups: [MonthGroup] {
        let calendar = Calendar.current
        var groups: [String: (title: String, entries: [WeightEntry])] = [:]

        for entry in entries {
            guard let date = DateFormatters.dateOnly.date(from: entry.date) else { continue }
            let key = String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
            let title = DateFormatters.monthYear.string(from: date)
            groups[key, default: (title, [])].entries.append(entry)
        }

        return groups.map { MonthGroup(id: $0.key, title: $0.value.title, entries: $0.value.entries) }
            .sorted { $0.id > $1.id }
    }

    /// Predecessor (next-older) entry for each entry id, precomputed once per
    /// render. Rows used to each scan the global `entries` array with
    /// `firstIndex` → O(n²) for the whole list; this is O(n). (#950)
    private var predecessorByID: [Int64: WeightEntry] {
        var map: [Int64: WeightEntry] = [:]
        map.reserveCapacity(entries.count)
        for i in entries.indices where i + 1 < entries.count {
            if let id = entries[i].id { map[id] = entries[i + 1] }
        }
        return map
    }

    var body: some View {
        let predecessors = predecessorByID
        VStack(alignment: .leading, spacing: 16) {
            ForEach(monthGroups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    // Month header with average
                    HStack {
                        Text(group.title)
                            .font(.headline)
                        Spacer()
                        let sorted = group.entries.map(\.weightKg).sorted()
                        let median = sorted.isEmpty ? 0 : sorted[sorted.count / 2]
                        Text("~\(String(format: "%.1f", unit.convert(fromKg: median))) \(unit.displayName)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .padding(.bottom, 8)

                    // Entries — LazyVStack so long histories don't build every
                    // row up front. (#950)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                            entryRow(entry: entry, predecessor: entry.id.flatMap { predecessors[$0] })

                            if index < group.entries.count - 1 {
                                Divider().overlay(Theme.separator)
                            }
                        }
                    }
                    .card()
                }
            }
        }
    }

    private func entryRow(entry: WeightEntry, predecessor: WeightEntry?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%.1f", unit.convert(fromKg: entry.weightKg))) \(unit.displayName)")
                    .font(.body.weight(.semibold).monospacedDigit())
                Text(formatDate(entry.date))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            // Change vs previous entry (skip if gap > 90 days — misleading with old data)
            if let prev = predecessor {
                let daysBetween = abs(Calendar.current.dateComponents([.day],
                    from: DateFormatters.dateOnly.date(from: prev.date) ?? Date(),
                    to: DateFormatters.dateOnly.date(from: entry.date) ?? Date()).day ?? 0)
                if daysBetween <= 90 {
                    let change = unit.convert(fromKg: entry.weightKg - prev.weightKg)
                    // "No Change" band (±0.05) must render fully neutral — the
                    // arrow/color thresholds were tighter (±0.01), so a −0.04
                    // row showed a red ↘ beside "No Change" (field 2026-07-17).
                    let isFlat = abs(change) < 0.05
                    HStack(spacing: 4) {
                        Image(systemName: isFlat ? "arrow.right" : change < 0 ? "arrow.down.right" : "arrow.up.right")
                            .font(.caption2)
                        if isFlat {
                            Text("No Change")
                                .font(.caption)
                        } else {
                            Text("\(change >= 0 ? "+" : "")\(String(format: "%.1f", change)) \(unit.displayName)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .foregroundStyle(isFlat ? Color.secondary : changeColor(change))
                }
            }

            if entry.syncedFromHk {
                Image(systemName: "heart.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.heartRed.opacity(0.5))
            }
        }
        .padding(.vertical, 10)
        .contextMenu {
            if let onEdit {
                Button {
                    onEdit(entry)
                } label: {
                    Label("Edit Weight", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                if let id = entry.id { onDelete(id) }
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        }
    }

    private func formatDate(_ s: String) -> String {
        guard let d = DateFormatters.dateOnly.date(from: s) else { return s }
        return DateFormatters.dayDisplay.string(from: d)
    }
}

private struct MonthGroup: Identifiable {
    let id: String
    let title: String
    let entries: [WeightEntry]
}
