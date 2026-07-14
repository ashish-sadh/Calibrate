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

    // MARK: - Intelligent comparisons / ratios

    public struct Ratio: Sendable, Equatable {
        public let id: String
        public let title: String
        public let value: Double
        /// A short read on what the value means (goal-agnostic, factual).
        public let interpretation: String
    }

    /// Body-shape ratios derivable from a single measurement set. Waist-to-hip
    /// and waist-to-chest are the classic physique/health-risk indicators.
    public static func ratios(in m: BodyMeasurement) -> [Ratio] {
        var out: [Ratio] = []
        if let waist = m.value(for: .waist), let hips = m.value(for: .hips), hips > 0 {
            let whr = waist / hips
            let note: String
            if whr < 0.85 { note = "lower-risk range" }
            else if whr < 0.95 { note = "moderate range" }
            else { note = "higher cardio-metabolic risk range" }
            out.append(Ratio(id: "whr", title: "Waist-to-Hip", value: whr, interpretation: note))
        }
        if let waist = m.value(for: .waist), let chest = m.value(for: .chest), chest > 0 {
            let wcr = waist / chest
            // Lower waist-to-chest reads as a more V-taper physique.
            let note = wcr < 0.75 ? "strong V-taper" : (wcr < 0.85 ? "athletic taper" : "straighter torso")
            out.append(Ratio(id: "wcr", title: "Waist-to-Chest", value: wcr, interpretation: note))
        }
        return out
    }

    public struct Mover: Sendable, Equatable {
        public let site: MeasurementSite
        public let changeCm: Double
        public let percentChange: Double
    }

    /// The biggest relative movers between two sets — "what actually changed."
    /// Ranked by absolute percent change, largest first.
    public static func biggestMovers(from previous: BodyMeasurement, to current: BodyMeasurement, limit: Int = 3) -> [Mover] {
        deltas(from: previous, to: current)
            .filter { abs($0.changeCm) >= 0.5 && $0.previousCm > 0 }
            .map { Mover(site: $0.site, changeCm: $0.changeCm, percentChange: ($0.changeCm / $0.previousCm) * 100) }
            .sorted { abs($0.percentChange) > abs($1.percentChange) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Unit helpers

    public static func cm(fromInches inches: Double) -> Double { inches * 2.54 }
    public static func inches(fromCm cm: Double) -> Double { cm / 2.54 }

    // MARK: - Save-time measurement resolution (pure — the data-integrity core)

    /// Per-site input captured from the entry form.
    public struct FieldInput: Sendable {
        public let enteredText: String     // what's in the text field now
        public let loadedText: String?     // exact text shown at load (for drift avoidance)
        public let loadedCm: Double?       // original stored cm for this site
        public let ghostCm: Double?        // carried-forward value from a prior check-in
        public init(enteredText: String, loadedText: String?, loadedCm: Double?, ghostCm: Double?) {
            self.enteredText = enteredText; self.loadedText = loadedText
            self.loadedCm = loadedCm; self.ghostCm = ghostCm
        }
    }

    /// Resolve the per-site fields into the cm map to persist. The three rules
    /// that stop data corruption (2026-07-14 verifier findings):
    ///  1. An untouched field re-saves its ORIGINAL cm (no conversion drift).
    ///  2. A blank field adopts its ghost ONLY when the user logged at least one
    ///     measurement — so a photo-only / empty check-in never fabricates a
    ///     full measurement set copied from a previous date.
    ///  3. Anything the user typed is parsed and converted from the display unit.
    public static func resolveMeasurements(_ fields: [MeasurementSite: FieldInput], inInches: Bool) -> [String: Double] {
        let userLogged = fields.values.contains { !$0.enteredText.trimmingCharacters(in: .whitespaces).isEmpty }
        var out: [String: Double] = [:]
        for (site, f) in fields {
            let text = f.enteredText.trimmingCharacters(in: .whitespaces)
            if text.isEmpty {
                if userLogged, let ghost = f.ghostCm { out[site.rawValue] = ghost }
                continue
            }
            if text == f.loadedText, let original = f.loadedCm {
                out[site.rawValue] = original
                continue
            }
            // Plain numbers only (comma decimals accepted) — the unit comes
            // from the form's explicit cm⇄in option, not suffix parsing
            // (operator 2026-07-14: "give them options, no text parsing").
            let normalized = text.replacingOccurrences(of: ",", with: ".")
            guard let shown = Double(normalized), shown > 0 else { continue }
            out[site.rawValue] = inInches ? shown * 2.54 : shown
        }
        return out
    }
}
