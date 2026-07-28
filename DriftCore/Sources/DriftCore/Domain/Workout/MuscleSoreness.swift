import Foundation

/// Learned per-muscle-group recovery times, fed by subtle "Still sore in
/// legs?" check-ins on the Muscle Recovery card (operator request
/// 2026-07-13: "some signals about whether someone is still sore instead
/// of default algo… subtle, not too in-face… and learn from it how long
/// it takes to recover").
///
/// Model: each group carries a recovery estimate in hours (default 72h —
/// chosen so the untouched defaults reproduce the previous hardcoded
/// day-threshold coloring exactly: day 0-1 recovering, day 2 moderate,
/// day 3+ recovered). A yes/no answer at `t` hours since training is a
/// boundary observation:
///
///   still sore at t  → recovery ≥ t: pull the estimate toward t + 12h
///                       when that exceeds it
///   not sore at t    → recovery ≤ t: pull the estimate toward t when t
///                       is below it
///
/// Updates blend at 0.35 so one odd answer can't whipsaw the estimate;
/// values clamp to [24h, 144h].
///
/// Ask policy: at most ONE question per calendar day across all groups,
/// only for a group inside its ambiguity window (0.5×–1.5× the current
/// estimate — that's where an answer is informative), and never the same
/// group twice within 3 days. Ties go to the group closest to its
/// estimated boundary.
public enum MuscleSoreness {

    public struct State: Codable, Sendable, Equatable {
        /// Group → learned recovery hours. Missing group = default.
        public var learnedHours: [String: Double]
        /// yyyy-MM-dd of the last day ANY question was shown.
        public var lastAskedDay: String?
        /// Group → yyyy-MM-dd it was last asked about.
        public var lastAskedDayByGroup: [String: String]

        public init(learnedHours: [String: Double] = [:],
                    lastAskedDay: String? = nil,
                    lastAskedDayByGroup: [String: String] = [:]) {
            self.learnedHours = learnedHours
            self.lastAskedDay = lastAskedDay
            self.lastAskedDayByGroup = lastAskedDayByGroup
        }
    }

    public enum Status: Sendable, Equatable {
        case recovered, moderate, recovering
    }

    public static let defaultRecoveryHours = 72.0
    static let minRecoveryHours = 24.0
    static let maxRecoveryHours = 144.0
    static let learningRate = 0.35
    /// "Still sore" pushes the estimate past the observation by this much —
    /// the user is telling us recovery isn't done yet, not where it ends.
    static let soreOvershootHours = 12.0

    public static func recoveryHours(for group: String, state: State) -> Double {
        state.learnedHours[group] ?? defaultRecoveryHours
    }

    /// Recovery status for a group trained `hoursSince` hours ago.
    /// (Untrained/stale handling stays with the caller — this only grades
    /// groups that were actually trained recently.)
    public static func status(hoursSince: Double, recoveryHours: Double) -> Status {
        if hoursSince < recoveryHours * 0.5 { return .recovering }
        if hoursSince < recoveryHours { return .moderate }
        return .recovered
    }

    /// The single group worth asking about today, or nil. `hoursSinceByGroup`
    /// should only contain recently-trained groups.
    public static func questionCandidate(
        hoursSinceByGroup: [String: Double],
        state: State,
        today: String
    ) -> String? {
        guard state.lastAskedDay != today else { return nil }
        let candidates = hoursSinceByGroup.compactMap { (group, hours) -> (group: String, distance: Double)? in
            let estimate = recoveryHours(for: group, state: state)
            guard hours >= estimate * 0.5, hours <= estimate * 1.5 else { return nil }
            if let asked = state.lastAskedDayByGroup[group],
               let askedDate = DateFormatters.dateOnly.date(from: asked),
               let todayDate = DateFormatters.dateOnly.date(from: today),
               todayDate.timeIntervalSince(askedDate) < 3 * 86_400 {
                return nil
            }
            return (group, abs(hours - estimate))
        }
        return candidates.min { $0.distance < $1.distance }?.group
    }

    /// Record an answer and update the learned estimate.
    public static func applyResponse(
        group: String,
        stillSore: Bool,
        hoursSince: Double,
        today: String,
        state: inout State
    ) {
        let current = recoveryHours(for: group, state: state)
        let target: Double
        if stillSore {
            target = max(current, hoursSince + soreOvershootHours)
        } else {
            target = min(current, hoursSince)
        }
        let updated = current + learningRate * (target - current)
        state.learnedHours[group] = min(maxRecoveryHours, max(minRecoveryHours, updated))
        state.lastAskedDay = today
        state.lastAskedDayByGroup[group] = today
    }

    /// Mark a question as shown-and-dismissed without an answer so the same
    /// prompt doesn't nag again the same day.
    public static func markAsked(group: String, today: String, state: inout State) {
        state.lastAskedDay = today
        state.lastAskedDayByGroup[group] = today
    }

    // MARK: - Persistence

    private static let stateKey = "drift_muscle_soreness_state"

    public static func loadState() -> State {
        guard let data = DriftPlatform.keyValueStore.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return State() }
        return state
    }

    public static func saveState(_ state: State) {
        if let data = try? JSONEncoder().encode(state) {
            DriftPlatform.keyValueStore.set(data, forKey: stateKey)
        }
    }
}
