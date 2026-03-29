import SwiftUI

struct WeightLogListView: View {
    let entries: [WeightEntry]
    let unit: WeightUnit
    let onDelete: (Int64) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight Log")
                .font(.headline)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(String(format: "%.1f", unit.convert(fromKg: entry.weightKg))) \(unit.displayName)")
                            .font(.body.bold().monospacedDigit())
                        Text(formatDate(entry.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Day-over-day change
                    if index < entries.count - 1 {
                        let previous = entries[index + 1] // entries are desc
                        let change = entry.weightKg - previous.weightKg
                        let displayChange = unit.convert(fromKg: change)

                        HStack(spacing: 4) {
                            Image(systemName: change < -0.01 ? "arrow.down.right" : change > 0.01 ? "arrow.up.right" : "arrow.right")
                                .font(.caption)
                            Text("\(displayChange >= 0 ? "+" : "")\(String(format: "%.1f", displayChange)) \(unit.displayName)")
                                .font(.caption.monospacedDigit())
                        }
                        .foregroundStyle(change < -0.01 ? .green : change > 0.01 ? .red : .secondary)
                    } else {
                        Text("--")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // Source badge
                    if entry.syncedFromHk {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.6))
                    }
                }
                .padding(.vertical, 6)
                .swipeActions(edge: .trailing) {
                    if let id = entry.id {
                        Button(role: .destructive) {
                            onDelete(id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }

                if index < entries.count - 1 {
                    Divider()
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = formatter.date(from: dateString) else { return dateString }
        return DateFormatters.dayDisplay.string(from: date)
    }
}
