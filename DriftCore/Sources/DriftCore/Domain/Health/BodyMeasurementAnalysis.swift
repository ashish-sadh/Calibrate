import Foundation

/// Change analysis for body-circumference measurements. Pure and
/// cross-platform (testable without a device). Powers the "vs last / vs first"
/// deltas and the left/right symmetry read in the progress UI.
public enum BodyMeasurementAnalysis {

    public struct SiteDelta: Sendable, Equatable {
        public let site: MeasurementSite
        public let previousCm: Double
        public let currentCm: Double
        public let changeCm: Double   // current − previous
    }

    /// Per-site change between two measurement sets (only sites present in
    /// both). Sorted by display order so the UI is stable.
    public static func deltas(from previous: BodyMeasurement, to current: BodyMeasurement) -> [SiteDelta] {
        MeasurementSite.displayOrder.compactMap { site in
            guard let p = previous.value(for: site), let c = current.value(for: site) else { return nil }
            return SiteDelta(site: site, previousCm: p, currentCm: c, changeCm: c - p)
        }
    }

    public struct Symmetry: Sendable, Equatable {
        public let leftSite: MeasurementSite
        public let rightSite: MeasurementSite
        public let leftCm: Double
        public let rightCm: Double
        public var differenceCm: Double { abs(leftCm - rightCm) }
        /// The larger side, or nil when within noise (< 0.5 cm).
        public var largerSide: MeasurementSite? {
            if differenceCm < 0.5 { return nil }
            return leftCm > rightCm ? leftSite : rightSite
        }
    }

    /// Left/right imbalance for the paired sites present in a measurement.
    /// Returns one `Symmetry` per pair (left-keyed), largest imbalance first.
    public static func symmetry(in measurement: BodyMeasurement) -> [Symmetry] {
        let pairs: [(MeasurementSite, MeasurementSite)] = [
            (.leftBicep, .rightBicep), (.leftForearm, .rightForearm),
            (.leftThigh, .rightThigh), (.leftCalf, .rightCalf),
        ]
        return pairs.compactMap { (l, r) in
            guard let lv = measurement.value(for: l), let rv = measurement.value(for: r) else { return nil }
            return Symmetry(leftSite: l, rightSite: r, leftCm: lv, rightCm: rv)
        }
        .sorted { $0.differenceCm > $1.differenceCm }
    }

    /// A short human summary of the most notable changes between two sets,
    /// goal-agnostic (states direction, not judgment). e.g.
    /// "Waist −2.5 cm, chest +1.0 cm since your last check-in."
    /// `unit` controls display; values are stored in cm.
    public static func changeSummary(
        from previous: BodyMeasurement, to current: BodyMeasurement,
        inInches: Bool
    ) -> String? {
        let deltas = deltas(from: previous, to: current).filter { abs($0.changeCm) >= 0.5 }
        guard !deltas.isEmpty else { return nil }
        // The two biggest absolute moves lead.
        let top = deltas.sorted { abs($0.changeCm) > abs($1.changeCm) }.prefix(2)
        let parts = top.map { d -> String in
            let v = inInches ? d.changeCm / 2.54 : d.changeCm
            let u = inInches ? "in" : "cm"
            return "\(d.site.displayName) \(v >= 0 ? "+" : "−")\(fmt(abs(v))) \(u)"
        }
        return parts.joined(separator: ", ") + " since your last check-in."
    }

    static func fmt(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }

    // MARK: - Unit helpers

    public static func cm(fromInches inches: Double) -> Double { inches * 2.54 }
    public static func inches(fromCm cm: Double) -> Double { cm / 2.54 }
}
