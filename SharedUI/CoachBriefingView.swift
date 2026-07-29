import SwiftUI
import DriftCore

/// THE mirror view (#1156): one component renders a `ClientBriefing`
/// everywhere it appears. The coach's client page shows it from the fetched
/// row; the client's sharing card shows it built from LOCAL data — "this is
/// exactly what your coach sees", byte for byte, because it IS the same view.
/// Consent you can see, not a checkbox you trust.
///
/// Presentation only: no loading, no network, no tap handling — hosts own
/// all of that.
struct CoachBriefingView: View {
    let briefing: ClientBriefing
    /// Shown when the briefing is empty — the two hosts phrase it differently
    /// ("nothing shared yet" vs "turn on a toggle to see a preview").
    var emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if briefing.isEmpty {
                Text(emptyText)
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            } else {
                if !briefing.metrics.lines.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(briefing.metrics.lines, id: \.label) { line in
                            HStack {
                                Text(line.label).font(.caption).foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(line.value).font(.caption.weight(.semibold))
                            }
                        }
                    }
                }

                if !briefing.summary.isEmpty {
                    Text(briefing.summary)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                        .padding(.top, 2)
                }

                // Newest first — a six-month-old sore shoulder is history,
                // last week's is a training constraint.
                ForEach(briefing.notes.suffix(6).reversed(), id: \.id) { note in
                    HStack(alignment: .top, spacing: 6) {
                        Text(note.date).font(.caption2).foregroundStyle(Theme.textTertiary)
                        Text(note.text).font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
