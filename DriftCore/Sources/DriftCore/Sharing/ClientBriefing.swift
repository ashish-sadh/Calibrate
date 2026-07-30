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
    /// Strength records — the best set per main lift with its date, drawn
    /// from the FULL local workout history (not just the sessions explicitly
    /// shared), which is why it earns its own bit.
    public static let strength = BriefingSharingLevel(rawValue: 1 << 5)

    public static let none: BriefingSharingLevel = []

    /// Every category a client can opt into, so UI can say "4 of 6" without
    /// hardcoding a count that silently goes stale the next time a bit is added.
    public static let allCategories: [BriefingSharingLevel] =
        [.history, .sleep, .nutrition, .weight, .bodyComp, .strength]

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
        if contains(.bodyComp) { out.append("Body composition") }
        if contains(.strength) { out.append("Training detail (best sets & recovery)") }
        return out
    }
}

/// One muscle group's recovery state, as the CLIENT's app computed it.
///
/// The status is resolved on the client and shipped as a value, not
/// recomputed coach-side, because the thresholds are LEARNED per person:
/// `MuscleSoreness` tunes each group's recovery estimate from the client's
/// own "still sore?" answers. A coach recomputing from days-since would show
/// a different colour than the client sees for the same body — and the mirror
/// principle says both sides read one truth.
public struct MuscleRecoveryPoint: Codable, Sendable, Equatable, Identifiable {
    public enum Status: String, Codable, Sendable {
        case recovering, moderate, recovered, untrained
    }

    public var group: String
    public var status: Status
    /// Days since the group was last trained; nil when never (or beyond the
    /// history window), which is what `.untrained` means.
    public var daysSince: Int?

    public var id: String { group }

    public init(group: String, status: Status, daysSince: Int? = nil) {
        self.group = group
        self.status = status
        self.daysSince = daysSince
    }

    /// "2d" / "today" / "—" — a coach scans six of these at once, so it has
    /// to read in one glance.
    public var shortAge: String {
        guard let daysSince else { return "—" }
        return daysSince == 0 ? "today" : "\(daysSince)d"
    }

    var payload: [String: Any] {
        var dict: [String: Any] = ["group": group, "status": status.rawValue]
        if let daysSince { dict["days_since"] = daysSince }
        return dict
    }

    static func decode(_ any: Any?) -> [MuscleRecoveryPoint]? {
        guard let rows = any as? [[String: Any]] else { return nil }
        let points = rows.compactMap { row -> MuscleRecoveryPoint? in
            guard let group = row["group"] as? String,
                  let raw = row["status"] as? String,
                  let status = Status(rawValue: raw) else { return nil }
            let days = (row["days_since"] as? Int)
                ?? BriefingMetrics.double(row["days_since"]).map(Int.init)
            return MuscleRecoveryPoint(group: group, status: status, daysSince: days)
        }
        return points.isEmpty ? nil : points
    }
}

/// A stall worth a coach's attention. Derived entirely from data the client
/// already shares — each alert is emitted only when ITS source category is
/// opted into, so a plateau never reveals a category the client withheld.
///
/// Deliberately a small closed set rather than free text: a coach scanning
/// five clients needs a shape they recognise, and free strings can't be
/// tested or translated.
public struct PlateauAlert: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// A lift trained repeatedly with no new best.
        case strength
        /// Weight flat while the client is trying to move it.
        case weight
    }

    public var kind: Kind
    /// The lift's name for `.strength`; empty for `.weight`.
    public var subject: String
    /// Sessions (strength) or weeks (weight) the stall has run for.
    public var span: Int

    public var id: String { "\(kind.rawValue)-\(subject)" }

    public init(kind: Kind, subject: String, span: Int) {
        self.kind = kind
        self.subject = subject
        self.span = span
    }

    /// One line, phrased as the observation — never as an instruction. The
    /// coach decides what to change; the app's job is to surface the stall.
    public var text: String {
        switch kind {
        case .strength:
            return "\(subject): \(span) sessions without a new best"
        case .weight:
            return "Weight flat \(span) weeks while working toward a target"
        }
    }

    var payload: [String: Any] {
        ["kind": kind.rawValue, "subject": subject, "span": span]
    }

    static func decode(_ any: Any?) -> [PlateauAlert]? {
        guard let rows = any as? [[String: Any]] else { return nil }
        let alerts = rows.compactMap { row -> PlateauAlert? in
            guard let raw = row["kind"] as? String, let kind = Kind(rawValue: raw) else { return nil }
            let span = (row["span"] as? Int)
                ?? BriefingMetrics.double(row["span"]).map(Int.init) ?? 0
            return PlateauAlert(kind: kind, subject: (row["subject"] as? String) ?? "", span: span)
        }
        return alerts.isEmpty ? nil : alerts
    }
}

/// One point in a weekly-average trend: the week's start date and its value.
///
/// WEEKLY, not daily, and that is a consent decision rather than a display
/// one (operator ruling 2026-07-29): the sharing toggles promise "averages
/// over a window", so a per-day series would widen what the client agreed to.
/// A weekly average honours the promise and still draws a real trend.
public struct WeeklyPoint: Codable, Sendable, Equatable {
    /// yyyy-MM-dd of the week's first day.
    public var weekStart: String
    public var value: Double

    public init(weekStart: String, value: Double) {
        self.weekStart = weekStart
        self.value = value
    }

    var payload: [String: Any] { ["week": weekStart, "value": value] }

    static func decode(_ any: Any?) -> [WeeklyPoint]? {
        guard let rows = any as? [[String: Any]] else { return nil }
        let points = rows.compactMap { row -> WeeklyPoint? in
            guard let week = row["week"] as? String,
                  let value = BriefingMetrics.double(row["value"]) else { return nil }
            return WeeklyPoint(weekStart: week, value: value)
        }
        return points.isEmpty ? nil : points
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
    // Regional fat distribution from the same scan — what lets a coach see
    // WHERE the fat sits, not just how much. Within `.bodyComp`'s plain
    // meaning, and the toggle label names it (2026-07-29 operator ask for
    // DEXA diagrams). Still summary-only: three percentages, never the scan.
    public var trunkFatPct: Double?
    public var armsFatPct: Double?
    public var legsFatPct: Double?
    // Weekly-average TRENDS (operator ask: "I wish they can see weight trend
    // and average sleep trend etc too"). Each rides its existing category
    // bit — weight series under .weight, sleep under .sleep, calories under
    // .nutrition — because a weekly average is exactly what those toggles
    // already promise.
    public var weightSeries: [WeeklyPoint]?
    public var sleepSeries: [WeeklyPoint]?
    public var caloriesSeries: [WeeklyPoint]?
    /// Days food was logged in the window, so "didn't log Tuesday" is
    /// distinguishable from "ate nothing Tuesday" — the averages alone hide
    /// which one happened (operator: "calories, whether logged or not").
    public var daysLogged: Int?
    /// Best set per main lift (the `.strength` opt-in).
    public var records: [PersonalRecord]?
    /// Stalls worth attention. Each element is gated by the category it came
    /// from, so this never leaks a withheld one.
    public var plateaus: [PlateauAlert]?
    /// Per-muscle recovery, as the client's own app coloured it (the
    /// `.strength` opt-in — same source and sensitivity as the records).
    public var recovery: [MuscleRecoveryPoint]?

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
        // Adherence, not content: how many days were logged at all. Without
        // it a coach can't tell a light week from an unlogged one.
        if let logged = daysLogged {
            out.append(("Days logged", "\(logged)/\(windowDays)"))
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

    /// One trend per shared category, ready to plot. A series of fewer than
    /// two points is dropped — a one-point "trend" is a number pretending to
    /// be a direction.
    public var trends: [Trend] {
        var out: [Trend] = []
        if let series = weightSeries, series.count >= 2 {
            out.append(Trend(label: "Weight", unit: "lb", points: series, decimals: 1))
        }
        if let series = sleepSeries, series.count >= 2 {
            out.append(Trend(label: "Sleep", unit: "h", points: series, decimals: 1))
        }
        if let series = caloriesSeries, series.count >= 2 {
            out.append(Trend(label: "Calories", unit: "", points: series, decimals: 0))
        }
        return out
    }

    /// A plottable weekly trend plus the labels a compact chart needs.
    public struct Trend: Sendable, Equatable, Identifiable {
        public var label: String
        public var unit: String
        public var points: [WeeklyPoint]
        public var decimals: Int

        public var id: String { label }
        public var values: [Double] { points.map(\.value) }

        /// Net change first-to-last — the number a coach reads before the shape.
        public var change: Double { (values.last ?? 0) - (values.first ?? 0) }

        public func format(_ value: Double) -> String {
            let text = String(format: "%.\(decimals)f", value)
            return unit.isEmpty ? text : "\(text) \(unit)"
        }

        public var changeText: String {
            let sign = change > 0 ? "+" : ""
            return sign + format(change)
        }

        /// Weeks covered, for "over 8 weeks" copy.
        public var weeks: Int { points.count }
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
        if let value = trunkFatPct { dict["trunk_fat_pct"] = value }
        if let value = armsFatPct { dict["arms_fat_pct"] = value }
        if let value = legsFatPct { dict["legs_fat_pct"] = value }
        if let series = weightSeries { dict["weight_series"] = series.map(\.payload) }
        if let series = sleepSeries { dict["sleep_series"] = series.map(\.payload) }
        if let series = caloriesSeries { dict["calories_series"] = series.map(\.payload) }
        if let value = daysLogged { dict["days_logged"] = value }
        if let records, !records.isEmpty {
            dict["records"] = records.map { record in
                ["exercise": record.exercise, "weight_lbs": record.weightLbs,
                 "reps": record.reps, "one_rm": record.estimated1RM, "date": record.date,
                 "sessions_since_pr": record.sessionsSincePR]
            }
        }
        if let plateaus, !plateaus.isEmpty { dict["plateaus"] = plateaus.map(\.payload) }
        if let recovery, !recovery.isEmpty { dict["recovery"] = recovery.map(\.payload) }
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
        metrics.trunkFatPct = double(dict["trunk_fat_pct"])
        metrics.armsFatPct = double(dict["arms_fat_pct"])
        metrics.legsFatPct = double(dict["legs_fat_pct"])
        metrics.weightSeries = WeeklyPoint.decode(dict["weight_series"])
        metrics.sleepSeries = WeeklyPoint.decode(dict["sleep_series"])
        metrics.caloriesSeries = WeeklyPoint.decode(dict["calories_series"])
        metrics.daysLogged = (dict["days_logged"] as? Int)
            ?? double(dict["days_logged"]).map(Int.init)
        if let rows = dict["records"] as? [[String: Any]] {
            let records = rows.compactMap { row -> PersonalRecord? in
                guard let exercise = row["exercise"] as? String,
                      let weight = double(row["weight_lbs"]),
                      let oneRM = double(row["one_rm"]) else { return nil }
                let reps = (row["reps"] as? Int) ?? double(row["reps"]).map(Int.init) ?? 0
                let since = (row["sessions_since_pr"] as? Int)
                    ?? double(row["sessions_since_pr"]).map(Int.init) ?? 0
                return PersonalRecord(exercise: exercise, weightLbs: weight, reps: reps,
                                      estimated1RM: oneRM, date: (row["date"] as? String) ?? "",
                                      sessionsSincePR: since)
            }
            metrics.records = records.isEmpty ? nil : records
        }
        metrics.plateaus = PlateauAlert.decode(dict["plateaus"])
        metrics.recovery = MuscleRecoveryPoint.decode(dict["recovery"])
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
            && metrics.trends.isEmpty && (metrics.records?.isEmpty ?? true)
            && (metrics.plateaus?.isEmpty ?? true)
    }
}
