import SwiftUI

struct WeightLogListView: View {
    let entries: [WeightEntry]
    let unit: WeightUnit
    let onDelete: (Int64) -> Void
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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(monthGroups) { group in
                VStack(alignment: .leading, spacing: 0) {
                    // Month header with average
                    HStack {
                        Text(group.title)
                            .font(.headline)
                        Spacer()
                        let avg = group.entries.isEmpty ? 0 : group.entries.map(\.weightKg).reduce(0, +) / Double(group.entries.count)
                        Text("avg \(String(format: "%.1f", unit.convert(fromKg: avg))) \(unit.displayName)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 8)

                    // Entries
                    VStack(spacing: 0) {
                        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                            entryRow(entry: entry, index: index, allEntries: entries)

                            if index < group.entries.count - 1 {
                                Divider().overlay(Color.white.opacity(0.05))
                            }
                        }
                    }
                    .card()
                }
            }
        }
    }

    private func entryRow(entry: WeightEntry, index: Int, allEntries: [WeightEntry]) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(String(format: "%.1f", unit.convert(fromKg: entry.weightKg))) \(unit.displayName)")
                    .font(.body.weight(.semibold).monospacedDigit())
                Text(formatDate(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Change vs previous entry (skip if gap > 90 days — misleading with old data)
            if let globalIdx = allEntries.firstIndex(where: { $0.id == entry.id }),
               globalIdx < allEntries.count - 1 {
                let prev = allEntries[globalIdx + 1]
                let daysBetween = abs(Calendar.current.dateComponents([.day],
                    from: DateFormatters.dateOnly.date(from: prev.date) ?? Date(),
                    to: DateFormatters.dateOnly.date(from: entry.date) ?? Date()).day ?? 0)
                if daysBetween <= 90 {
                    let change = unit.convert(fromKg: entry.weightKg - prev.weightKg)
                    HStack(spacing: 4) {
                        Image(systemName: change < -0.01 ? "arrow.down.right" : change > 0.01 ? "arrow.up.right" : "arrow.right")
                            .font(.caption2)
                        if abs(change) < 0.05 {
                            Text("No Change")
                                .font(.caption)
                        } else {
                            Text("\(change >= 0 ? "+" : "")\(String(format: "%.1f", change)) \(unit.displayName)")
                                .font(.caption.monospacedDigit())
                        }
                    }
                    .foregroundStyle(changeColor(change))
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
            Button(role: .destructive) {
                if let id = entry.id { onDelete(id) }
            } label: {
                Label("Delete Entry", systemImage: "trash")
            }
        }
    }

    private func formatDate(_ s: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let d = f.date(from: s) else { return s }
        return DateFormatters.dayDisplay.string(from: d)
    }
}

private struct MonthGroup: Identifiable {
    let id: String
    let title: String
    let entries: [WeightEntry]
}
