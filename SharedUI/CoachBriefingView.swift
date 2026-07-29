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

                ForEach(briefing.metrics.trends) { trend in
                    trendRow(trend)
                }

                if let records = briefing.metrics.records, !records.isEmpty {
                    Divider().overlay(Theme.separatorFaint)
                    Text("BEST SETS").sectionHeading()
                    ForEach(records) { record in
                        HStack(spacing: 8) {
                            Text(record.exercise)
                                .font(.caption).foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(record.setDescription)
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            if !record.date.isEmpty {
                                Text(record.date)
                                    .font(.caption2).foregroundStyle(Theme.textTertiary)
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

    /// A weekly trend: the numbers first (a coach reads "−2.4 lb over 8
    /// weeks" before any shape), then a bar sparkline.
    ///
    /// BARS, not a Path line: bars are pure layout, so they measure correctly
    /// under Skip Fuse at any font scale and need no GeometryReader — which
    /// recomposes on every scroll frame on Fuse. The full Apple-Health-style
    /// line charts belong on the coach's dedicated client page (#1156 slice
    /// 2), not in a summary card.
    @ViewBuilder
    func trendRow(_ trend: BriefingMetrics.Trend) -> some View {
        let values = trend.values
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let span = high - low

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(trend.label).font(.caption).foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(trend.changeText)
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("over \(trend.weeks)w")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    // Flat series (span 0) would divide by zero — render those
                    // at a constant mid-height, which is honest: no movement.
                    let ratio = span > 0 ? (value - low) / span : 0.5
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Theme.chartTrend.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4 + 18 * ratio)
                }
            }
            .frame(height: 22)
            HStack {
                Text(trend.format(values.first ?? 0))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(trend.format(values.last ?? 0))
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
