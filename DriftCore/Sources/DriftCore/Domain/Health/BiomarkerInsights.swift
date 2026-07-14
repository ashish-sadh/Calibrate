import Foundation

/// Personalized biomarker narrative + trajectory + multi-marker pattern
/// detection. Pure and cross-platform so it's fully testable without a device
/// (2026-07-14). Replaces the three fixed status strings that were the entire
/// generated narrative before — those described only the latest value's band
/// and said nothing about direction, rate of change, crossing a threshold, or
/// how co-occurring markers combine into a recognizable pattern.
///
/// Nothing here invents medical advice beyond the hand-authored catalog copy;
/// it activates that knowledge against the user's actual numbers.
public enum BiomarkerInsights {

    // MARK: - Per-marker trend

    public enum Direction: String, Sendable, Equatable { case rising, falling, stable }

    public struct Trend: Sendable, Equatable {
        public let biomarkerId: String
        public let direction: Direction
        /// Signed change latest − earliest, in the normalized unit.
        public let absoluteChange: Double
        /// Percent change vs the earliest reading (nil if earliest ≈ 0).
        public let percentChange: Double?
        public let firstValue: Double
        public let latestValue: Double
        public let readingCount: Int
        public let latestStatus: BiomarkerStatus
        public let previousStatus: BiomarkerStatus?
        /// Set when the marker is IN range but the trajectory is carrying it
        /// toward the nearer out-of-range edge — the early-warning the old UI
        /// never gave.
        public let approachingEdge: Bool
        /// One human sentence describing the trajectory.
        public let narrative: String
    }

    /// `results` may be in any order; they're sorted by report date ascending
    /// internally. Returns nil for < 2 readings (nothing to trend). Values are
    /// the normalized values so units are consistent.
    public static func trend(
        biomarkerId: String,
        results: [(date: Date, value: Double)],
        definition: BiomarkerDefinition
    ) -> Trend? {
        let sorted = results.sorted { $0.date < $1.date }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return nil }

        let change = last.value - first.value
        let pct: Double? = abs(first.value) > 1e-6 ? (change / first.value) * 100 : nil
        // "Meaningful" move: > 3% of the reading OR crosses a status boundary.
        // Below that it's stable — lab-to-lab assay noise is ~2-5%.
        let latestStatus = definition.status(for: last.value)
        let prevStatus = sorted.count >= 2 ? definition.status(for: sorted[sorted.count - 2].value) : nil
        let firstStatus = definition.status(for: first.value)
        let crossed = latestStatus != firstStatus
        let relMove = abs(first.value) > 1e-6 ? abs(change) / abs(first.value) : abs(change)

        let direction: Direction
        if !crossed && relMove < 0.03 {
            direction = .stable
        } else {
            direction = change > 0 ? .rising : .falling
        }

        let approaching = Self.isApproachingEdge(
            latest: last.value, direction: direction, definition: definition, status: latestStatus)

        let narrative = Self.trendNarrative(
            def: definition, direction: direction, first: first.value, last: last.value,
            pct: pct, count: sorted.count, latestStatus: latestStatus,
            firstStatus: firstStatus, approaching: approaching)

        return Trend(
            biomarkerId: biomarkerId, direction: direction, absoluteChange: change,
            percentChange: pct, firstValue: first.value, latestValue: last.value,
            readingCount: sorted.count, latestStatus: latestStatus, previousStatus: prevStatus,
            approachingEdge: approaching, narrative: narrative)
    }

    /// In range now, but the trend is carrying the value toward the nearest
    /// out-of-range boundary and it's within 15% of that boundary's span.
    static func isApproachingEdge(
        latest: Double, direction: Direction, definition: BiomarkerDefinition, status: BiomarkerStatus
    ) -> Bool {
        guard status != .outOfRange else { return false }
        let span = definition.absoluteHigh - definition.absoluteLow
        guard span > 0 else { return false }
        let margin = span * 0.15
        if direction == .rising {
            // Nearest upper edge is sufficientHigh (or optimalHigh if still optimal).
            let edge = status == .optimal ? definition.optimalHigh : definition.sufficientHigh
            return latest >= edge - margin && latest < edge
        }
        if direction == .falling {
            let edge = status == .optimal ? definition.optimalLow : definition.sufficientLow
            return latest <= edge + margin && latest > edge
        }
        return false
    }

    private static func trendNarrative(
        def: BiomarkerDefinition, direction: Direction, first: Double, last: Double,
        pct: Double?, count: Int, latestStatus: BiomarkerStatus, firstStatus: BiomarkerStatus,
        approaching: Bool
    ) -> String {
        let unit = def.unit
        let f = fmt(first), l = fmt(last)
        let span = count == 2 ? "your last 2 readings" : "your last \(count) readings"

        if direction == .stable {
            return "\(def.name) has held around \(l) \(unit) across \(span)."
        }

        let verb = direction == .rising ? "rose" : "fell"
        var s = "\(def.name) \(verb) from \(f) to \(l) \(unit) over \(span)"
        if let pct, abs(pct) >= 3 {
            s += " (\(pct >= 0 ? "+" : "")\(Int(pct.rounded()))%)"
        }
        s += "."

        // Status transition is the most actionable part.
        if latestStatus != firstStatus {
            switch latestStatus {
            case .optimal:
                s += " It's now in the optimal range — keep it up."
            case .sufficient:
                s += firstStatus == .optimal
                    ? " It's slipped out of the optimal range."
                    : " It's moved into the sufficient range."
            case .outOfRange:
                s += " It's now outside the healthy range."
            }
        } else if approaching {
            let edgeWord = direction == .rising ? "upper" : "lower"
            s += " Still in range, but trending toward the \(edgeWord) limit."
        }
        return s
    }

    // MARK: - Report-over-report delta

    public struct MarkerDelta: Sendable, Equatable {
        public let biomarkerId: String
        public let name: String
        public let previous: Double
        public let current: Double
        public let change: Double
        public let unit: String
        public let currentStatus: BiomarkerStatus
        public let improved: Bool?   // nil when we can't tell direction-of-good
    }

    /// Compare the latest report's markers against the previous report. Only
    /// markers present in both are returned. `improved` uses the catalog bands:
    /// moving toward the optimal midpoint is an improvement.
    public static func reportDeltas(
        current: [(biomarkerId: String, value: Double)],
        previous: [(biomarkerId: String, value: Double)]
    ) -> [MarkerDelta] {
        let prevByID = Dictionary(previous.map { ($0.biomarkerId, $0.value) }, uniquingKeysWith: { a, _ in a })
        var out: [MarkerDelta] = []
        for c in current {
            guard let prev = prevByID[c.biomarkerId], let def = BiomarkerKnowledgeBase.byId[c.biomarkerId] else { continue }
            let change = c.value - prev
            guard abs(change) > 1e-9 else { continue }
            let mid = (def.optimalLow + def.optimalHigh) / 2
            let improved = abs(c.value - mid) < abs(prev - mid)
            out.append(MarkerDelta(
                biomarkerId: c.biomarkerId, name: def.name, previous: prev, current: c.value,
                change: change, unit: def.unit, currentStatus: def.status(for: c.value),
                improved: improved))
        }
        // Largest relative moves first.
        return out.sorted { abs($0.change / max(abs($0.previous), 1)) > abs($1.change / max(abs($1.previous), 1)) }
    }

    // MARK: - Multi-marker patterns

    public struct Pattern: Sendable, Equatable {
        public let id: String
        public let title: String
        public let detail: String
        public let markerIds: [String]
        public let severity: Severity
        public enum Severity: String, Sendable, Equatable { case watch, concern }
    }

    /// Activate recognizable multi-marker patterns against the user's latest
    /// values. Each rule needs its constituent markers present; a rule fires
    /// only when the actual values match the pattern. This is the synthesis the
    /// old tab never did — the knowledge lived in the catalog `relationships`
    /// text but was never checked against co-occurring numbers.
    public static func patterns(latest: [String: Double]) -> [Pattern] {
        func status(_ id: String) -> BiomarkerStatus? {
            guard let v = latest[id], let def = BiomarkerKnowledgeBase.byId[id] else { return nil }
            return def.status(for: v)
        }
        func val(_ id: String) -> Double? { latest[id] }

        var out: [Pattern] = []

        // Iron-deficiency (early): low ferritin is the earliest signal; low MCV
        // and/or high RDW corroborate microcytic iron-deficiency.
        if let ferritin = val("ferritin"), ferritin < 30 {
            var markers = ["ferritin"]
            var corroborating = 0
            if let mcv = val("mcv"), mcv < 80 { markers.append("mcv"); corroborating += 1 }
            if let rdw = val("rdw"), rdw > 14.5 { markers.append("rdw"); corroborating += 1 }
            if let hgb = val("hemoglobin"), let def = BiomarkerKnowledgeBase.byId["hemoglobin"],
               def.status(for: hgb) == .outOfRange { markers.append("hemoglobin"); corroborating += 1 }
            let detail = corroborating > 0
                ? "Low ferritin with \(corroborating > 1 ? "several" : "another") supporting marker suggests iron-deficiency. Ferritin drops before hemoglobin does, so this can appear before anemia."
                : "Ferritin is low — the earliest sign of iron depletion, often before hemoglobin falls. Consider iron intake and, in menstruating users, cycle-related loss."
            out.append(Pattern(id: "iron_deficiency", title: "Iron-deficiency pattern",
                               detail: detail, markerIds: markers,
                               severity: corroborating > 0 ? .concern : .watch))
        }

        // Metabolic syndrome / insulin resistance: high triglycerides + low HDL
        // is the classic dyslipidemia; high fasting glucose / HbA1c strengthens it.
        if let tg = val("triglycerides"), let hdl = val("hdl_cholesterol"), tg > 150, hdl < 45 {
            var markers = ["triglycerides", "hdl_cholesterol"]
            var extra = ""
            if let a1c = val("hba1c"), a1c >= 5.7 { markers.append("hba1c"); extra = " HbA1c is in the pre-diabetic range too." }
            else if let g = val("glucose"), g >= 100 { markers.append("glucose"); extra = " Fasting glucose is elevated too." }
            out.append(Pattern(id: "metabolic_syndrome", title: "Metabolic pattern",
                               detail: "High triglycerides with low HDL is the classic insulin-resistance lipid signature — usually driven by refined carbs, alcohol, and visceral fat.\(extra)",
                               markerIds: markers, severity: extra.isEmpty ? .watch : .concern))
        }

        // Atherogenic lipids: high LDL or ApoB with high non-HDL.
        if let ldl = val("ldl_cholesterol"), ldl >= 130 {
            var markers = ["ldl_cholesterol"]
            if let apob = val("apolipoprotein_b"), apob >= 100 { markers.append("apolipoprotein_b") }
            out.append(Pattern(id: "atherogenic_lipids", title: "Elevated LDL",
                               detail: markers.contains("apolipoprotein_b")
                                ? "LDL and ApoB are both elevated — ApoB counts atherogenic particles directly and confirms raised cardiovascular risk."
                                : "LDL is elevated. If available, ApoB gives a more precise particle count for cardiovascular risk.",
                               markerIds: markers, severity: ldl >= 160 ? .concern : .watch))
        }

        // Subclinical hypothyroid: high TSH with normal/low free T4.
        if let tsh = val("thyroid_tsh"), tsh > 4.5 {
            var markers = ["thyroid_tsh"]
            var detail = "TSH is above range."
            if let ft4 = val("free_t4"), let def = BiomarkerKnowledgeBase.byId["free_t4"] {
                markers.append("free_t4")
                detail = def.status(for: ft4) == .outOfRange
                    ? "High TSH with low free T4 fits overt hypothyroidism."
                    : "High TSH with a normal free T4 fits subclinical hypothyroidism — worth rechecking."
            }
            out.append(Pattern(id: "hypothyroid", title: "Thyroid pattern",
                               detail: detail, markerIds: markers, severity: .watch))
        }

        // Inflammation: high hs-CRP and/or high ESR.
        let crpHigh = (val("hs_crp").map { $0 > 3 } ?? false)
        let esrHigh: Bool = {
            guard let esr = val("esr"), let def = BiomarkerKnowledgeBase.byId["esr"] else { return false }
            return def.status(for: esr) == .outOfRange
        }()
        if crpHigh || esrHigh {
            var markers: [String] = []
            if crpHigh { markers.append("hs_crp") }
            if esrHigh { markers.append("esr") }
            out.append(Pattern(id: "inflammation", title: "Inflammation signal",
                               detail: "\(crpHigh && esrHigh ? "Both hs-CRP and ESR are" : (crpHigh ? "hs-CRP is" : "ESR is")) elevated — a non-specific sign of inflammation. Look for a driver (infection, visceral fat, poor sleep) and recheck.",
                               markerIds: markers, severity: .watch))
        }

        return out
    }

    // MARK: - Helpers

    static func fmt(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: v < 10 ? "%.2f" : "%.1f", v)
    }
}
