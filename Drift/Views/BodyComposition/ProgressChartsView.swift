import SwiftUI
import Charts
import DriftCore

/// Measurement + weight trends over time. One line chart per tracked site plus
/// weight, each with its first→latest change — the "am I actually moving"
/// payoff of logging measurements.
struct ProgressChartsView: View {
    let entries: [ProgressEntry]
    let weightByDate: [String: Double]

    @Environment(\.dismiss) private var dismiss
    private var inInches: Bool { Preferences.weightUnit == .lbs }

    private struct Series: Identifiable {
        let id: String
        let title: String
        let unit: String
        let points: [(date: Date, value: Double)]
        var first: Double { points.first?.value ?? 0 }
        var last: Double { points.last?.value ?? 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    insightsSection
                    if let w = weightSeries { chartCard(w, lowerBetter: nil) }
                    ForEach(measurementSeries) { s in
                        chartCard(s, lowerBetter: s.id == MeasurementSite.waist.rawValue)
                    }
                    if weightSeries == nil && measurementSeries.isEmpty && insights.isEmpty {
                        Text("Log measurements on at least two dates to see trends.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center).padding(.top, 40)
                    }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    // MARK: - Insights (intelligent comparisons)

    /// The latest and the previous measurement sets, for movers/symmetry/ratios.
    private var latestMeasurement: BodyMeasurement? {
        entries.first(where: { $0.measurement?.isEmpty == false })?.measurement
    }
    private var previousMeasurement: BodyMeasurement? {
        entries.filter { $0.measurement?.isEmpty == false }.dropFirst().first?.measurement
    }

    private var insights: [(icon: String, text: String)] {
        var out: [(String, String)] = []
        if let latest = latestMeasurement {
            for r in BodyMeasurementAnalysis.ratios(in: latest) {
                out.append(("circle.grid.cross", "\(r.title) \(String(format: "%.2f", r.value)) — \(r.interpretation)"))
            }
            for s in BodyMeasurementAnalysis.symmetry(in: latest) where s.largerSide != nil {
                let diff = inInches ? s.differenceCm / 2.54 : s.differenceCm
                let u = inInches ? "in" : "cm"
                out.append(("arrow.left.and.right", "\(s.largerSide!.displayName) is \(String(format: "%.1f", diff)) \(u) larger than the other side"))
            }
        }
        if let latest = latestMeasurement, let prev = previousMeasurement {
            let movers = BodyMeasurementAnalysis.biggestMovers(from: prev, to: latest)
            if let top = movers.first {
                let v = inInches ? top.changeCm / 2.54 : top.changeCm
                let u = inInches ? "in" : "cm"
                out.append(("bolt.fill", "Biggest change: \(top.site.displayName) \(v >= 0 ? "+" : "−")\(String(format: "%.1f", abs(v))) \(u) (\(top.percentChange >= 0 ? "+" : "")\(Int(top.percentChange.rounded()))%)"))
            }
        }
        return out.map { (icon: $0.0, text: $0.1) }
    }

    @ViewBuilder
    private var insightsSection: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("INSIGHTS").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                ForEach(Array(insights.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: item.icon).font(.caption).foregroundStyle(Theme.accent).frame(width: 16)
                        Text(item.text).font(.caption).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
        }
    }

    // MARK: - Chart card

    private func chartCard(_ s: Series, lowerBetter: Bool?) -> some View {
        let change = s.last - s.first
        let changeColor: Color = {
            guard let lowerBetter, abs(change) > 0.05 else { return Theme.textSecondary }
            let good = lowerBetter ? change < 0 : change > 0
            return good ? Theme.deficit : Theme.surplus
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(s.title).font(.subheadline.weight(.semibold))
                Spacer()
                if s.points.count >= 2 {
                    Text("\(change >= 0 ? "+" : "−")\(fmt(abs(change))) \(s.unit)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(changeColor)
                }
            }
            Chart(s.points, id: \.date) { p in
                LineMark(x: .value("Date", p.date), y: .value(s.title, p.value))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", p.date), y: .value(s.title, p.value))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(28)
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(height: 130)
        }
        .padding(12)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.radiusControl))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.separator, lineWidth: 0.5))
    }

    // MARK: - Series builders

    private static let iso: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    private var weightSeries: Series? {
        let pts = weightByDate.compactMap { (date, kg) -> (Date, Double)? in
            guard let d = Self.iso.date(from: date) else { return nil }
            return (d, inInches ? kg * 2.20462 : kg)
        }.sorted { $0.0 < $1.0 }
        guard pts.count >= 2 else { return nil }
        return Series(id: "weight", title: "Weight", unit: Preferences.weightUnit.displayName,
                      points: pts.map { (date: $0.0, value: $0.1) })
    }

    /// One series per site that has ≥2 readings, in display order.
    private var measurementSeries: [Series] {
        let unit = inInches ? "in" : "cm"
        return MeasurementSite.displayOrder.compactMap { site in
            let pts = entries.compactMap { e -> (Date, Double)? in
                guard let cm = e.measurement?.value(for: site), let d = Self.iso.date(from: e.date) else { return nil }
                return (d, inInches ? cm / 2.54 : cm)
            }.sorted { $0.0 < $1.0 }
            guard pts.count >= 2 else { return nil }
            return Series(id: site.rawValue, title: site.displayName, unit: unit,
                          points: pts.map { (date: $0.0, value: $0.1) })
        }
    }

    private func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}
