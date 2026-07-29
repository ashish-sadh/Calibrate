import Foundation

/// What a client chooses to let a coach see beyond the workouts themselves.
///
/// Phase 1 sharing moved ONLY live workouts and templates — no weight, sleep,
/// food or health data. Widening that is a real privacy decision, not a feature
/// flag, so it is expressed as separate opt-ins rather than one "share
/// everything" switch: "my coach sees my protein" and "my coach sees my sleep"
/// are different choices and a person may want exactly one of them.
///
/// Everything here is an AVERAGE over a window. A coach needs the trend to
/// coach; the meal-by-meal diary is nobody else's business.
public struct BriefingSharingLevel: OptionSet, Codable, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// The Coach Me intake summary + note history (injuries, pain, goals).
    public static let history  = BriefingSharingLevel(rawValue: 1 << 0)
    /// Average sleep hours.
    public static let sleep    = BriefingSharingLevel(rawValue: 1 << 1)
    /// Average calories and protein against target.
    public static let nutrition = BriefingSharingLevel(rawValue: 1 << 2)
    /// Weight trend (direction and change over the window, not every weigh-in).
    public static let weight   = BriefingSharingLevel(rawValue: 1 << 3)
    /// Body composition from DEXA scans — latest body fat % and lean mass,
    /// with the change since the previous scan. Scan-summary numbers only,
    /// never the scan document. Own bit per the decisions.md rule: every
    /// widening of what crosses to a coach gets its own opt-in.
    public static let bodyComp = BriefingSharingLevel(rawValue: 1 << 4)

    public static let none: BriefingSharingLevel = []

    /// Per-coach preference. Defaults to nothing shared — a coach connection is
    /// consent to see workouts, not a standing grant over health data.
    public static func stored(for coachID: String) -> BriefingSharingLevel {
        let raw = DriftPlatform.keyValueStore.string(forKey: key(coachID))
        return BriefingSharingLevel(rawValue: raw.flatMap(Int.init) ?? 0)
    }

    public func store(for coachID: String) {
        DriftPlatform.keyValueStore.set(String(rawValue), forKey: Self.key(coachID))
    }

    static func key(_ coachID: String) -> String { "drift_briefing_share_\(coachID)" }

    /// Human-readable for the confirmation UI — people should be able to read
    /// back exactly what they agreed to.
    public var descriptions: [String] {
        var out: [String] = []
        if contains(.history) { out.append("Training history & injuries") }
        if contains(.sleep) { out.append("Average sleep") }
        if contains(.nutrition) { out.append("Average calories & protein") }
        if contains(.weight) { out.append("Weight trend") }
        return out
    }
}

/// The aggregates a coach sees. Every field optional: absent means "not
/// shared", which is deliberately distinct from zero — a coach reading
/// "0g protein" would draw the opposite conclusion from "not shared".
public struct BriefingMetrics: Codable, Sendable, Equatable {
    public var windowDays: Int = 7
    public var avgSleepHours: Double?
    public var avgCalories: Double?
    public var avgProteinG: Double?
    public var proteinTargetG: Double?
    public var weightChangeLbs: Double?
    /// Sessions completed in the window — the adherence number a coach checks
    /// first, and the one that makes the rest worth reading.
    public var workoutsCompleted: Int?
    // Body composition (the .bodyComp opt-in): latest DEXA scan's headline
    // numbers + change since the previous scan. Summary values only — the
    // scan itself never crosses.
    public var bodyFatPct: Double?
    public var bodyFatDeltaPct: Double?
    public var leanMassLbs: Double?
    public var leanMassDeltaLbs: Double?
    /// yyyy-MM-dd of the scan the numbers come from, so a coach knows how
    /// fresh the picture is.
    public var scanDate: String?

    public init() {}

    /// Compact display lines. Nil fields simply don't appear.
    public var lines: [(label: String, value: String)] {
        var out: [(String, String)] = []
        if let workouts = workoutsCompleted {
            out.append(("Workouts", "\(workouts) in \(windowDays)d"))
        }
        if let sleep = avgSleepHours {
            out.append(("Avg sleep", String(format: "%.1f h", sleep)))
        }
        if let protein = avgProteinG {
            let target = proteinTargetG.map { String(format: " / %.0f g", $0) } ?? " g"
            out.append(("Avg protein", String(format: "%.0f", protein) + target))
        }
        if let calories = avgCalories {
            out.append(("Avg calories", String(format: "%.0f", calories)))
        }
        if let change = weightChangeLbs {
            let sign = change > 0 ? "+" : ""
            out.append(("Weight", String(format: "\(sign)%.1f lb / \(windowDays)d", change)))
        }
        if let fat = bodyFatPct {
            let delta = bodyFatDeltaPct.map {
                String(format: " (\($0 > 0 ? "+" : "")%.1f)", $0)
            } ?? ""
            out.append(("Body fat", String(format: "%.1f%%", fat) + delta))
        }
        if let lean = leanMassLbs {
            let delta = leanMassDeltaLbs.map {
                String(format: " (\($0 > 0 ? "+" : "")%.1f)", $0)
            } ?? ""
            out.append(("Lean mass", String(format: "%.1f lb", lean) + delta))
        }
        if let scan = scanDate {
            out.append(("DEXA scan", scan))
        }
        return out
    }

    /// JSON for the `metrics` column. Only shared fields are emitted, so the
    /// wire payload itself carries no trace of a category the user withheld —
    /// the filtering happens before the network, not on read.
    public var payload: [String: Any] {
        var dict: [String: Any] = ["window_days": windowDays]
        if let value = avgSleepHours { dict["avg_sleep_hours"] = value }
        if let value = avgCalories { dict["avg_calories"] = value }
        if let value = avgProteinG { dict["avg_protein_g"] = value }
        if let value = proteinTargetG { dict["protein_target_g"] = value }
        if let value = weightChangeLbs { dict["weight_change_lbs"] = value }
        if let value = workoutsCompleted { dict["workouts_completed"] = value }
        if let value = bodyFatPct { dict["body_fat_pct"] = value }
        if let value = bodyFatDeltaPct { dict["body_fat_delta_pct"] = value }
        if let value = leanMassLbs { dict["lean_mass_lbs"] = value }
        if let value = leanMassDeltaLbs { dict["lean_mass_delta_lbs"] = value }
        if let value = scanDate { dict["scan_date"] = value }
        return dict
    }

    public static func decode(_ dict: [String: Any]) -> BriefingMetrics {
        var metrics = BriefingMetrics()
        metrics.windowDays = (dict["window_days"] as? Int) ?? 7
        metrics.avgSleepHours = double(dict["avg_sleep_hours"])
        metrics.avgCalories = double(dict["avg_calories"])
        metrics.avgProteinG = double(dict["avg_protein_g"])
        metrics.proteinTargetG = double(dict["protein_target_g"])
        metrics.weightChangeLbs = double(dict["weight_change_lbs"])
        metrics.workoutsCompleted = (dict["workouts_completed"] as? Int)
            ?? double(dict["workouts_completed"]).map(Int.init)
        metrics.bodyFatPct = double(dict["body_fat_pct"])
        metrics.bodyFatDeltaPct = double(dict["body_fat_delta_pct"])
        metrics.leanMassLbs = double(dict["lean_mass_lbs"])
        metrics.leanMassDeltaLbs = double(dict["lean_mass_delta_lbs"])
        metrics.scanDate = dict["scan_date"] as? String
        return metrics
    }

    static func double(_ any: Any?) -> Double? {
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let value = any as? String { return Double(value) }
        return nil
    }
}

/// One client's briefing as the coach reads it.
public struct ClientBriefing: Sendable, Equatable, Identifiable {
    public var clientID: String
    public var summary: String
    public var notes: [CoachNotes.Note]
    public var metrics: BriefingMetrics
    public var updatedAt: String?

    public var id: String { clientID }

    public init(clientID: String, summary: String, notes: [CoachNotes.Note],
                metrics: BriefingMetrics, updatedAt: String? = nil) {
        self.clientID = clientID
        self.summary = summary
        self.notes = notes
        self.metrics = metrics
        self.updatedAt = updatedAt
    }

    /// Empty means there is genuinely nothing to show — used to decide between
    /// the coach card and a "nothing shared yet" hint.
    public var isEmpty: Bool {
        summary.isEmpty && notes.isEmpty && metrics.lines.isEmpty
    }
}
