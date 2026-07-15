import Foundation

/// Domain buckets for the clarify-vs-proceed decision. One tool maps to
/// exactly one domain — the domain decides how hard we lean against asking
/// the user to disambiguate.
///
/// Reason for bucketing by domain rather than per-tool: users perceive
/// "food/weight/workout/supplement/meta" as one surface each, so false
/// clarifies in a domain feel the same regardless of which tool routed.
/// Bucketing also keeps the policy table small enough to reason about at
/// review time.
public enum IntentDomain: String, Sendable, CaseIterable {
    /// log_food, food_info, edit_meal, delete_food, copy_yesterday, explain_calories
    case food
    /// log_weight, weight_info, set_goal
    case weight
    /// start_workout, log_activity, exercise_info, sleep_recovery
    case exercise
    /// mark_supplement, supplements
    case supplements
    /// body_comp, glucose, biomarkers, cross_domain_insight, cross_domain_pattern_detector,
    /// goal_weight_eta — read-only data queries, never ambiguous
    case data
    /// navigate_to — screen name is context-sensitive ("sleep tab" vs "sleep data")
    case meta
    /// fallback for unknown tools
    case other

    /// Map a tool name to its domain. Keep in sync with the tool list in
    /// `IntentClassifier.systemPrompt`.
    public static func of(tool: String) -> IntentDomain {
        let name = tool.replacingOccurrences(of: "()", with: "").lowercased()
        switch name {
        case "log_food", "food_info", "edit_meal", "delete_food",
             "copy_yesterday", "explain_calories":
            return .food
        case "log_weight", "weight_info", "set_goal":
            return .weight
        case "start_workout", "log_activity", "exercise_info", "sleep_recovery":
            return .exercise
        case "mark_supplement", "supplements":
            return .supplements
        case "body_comp", "glucose", "biomarkers", "cross_domain_insight",
             "cross_domain_pattern_detector", "goal_weight_eta",
             "supplement_insight", "food_timing_insight", "sleep_food_correlation":
            return .data
        case "navigate_to":
            return .meta
        default:
            return .other
        }
    }
}

/// Domain-aware policy for "ask the user to disambiguate, or proceed with the
/// classified tool call?" — called once per LLM-classified intent inside
/// `AIToolAgent.runInner`.
///
/// The classifier emits a *string* confidence (`high`/`medium`/`low`, default
/// `high`). The old gate was: clarify iff `confidence == "low"` AND params
/// incomplete. That single rule under-clarified meta (`navigate_to "show me
/// my chart"` is screen-ambiguous even at `high` confidence) and
/// over-clarified food (`"chicken rice"` with a name should proceed even when
/// the LLM emits `medium`).
///
/// This struct encodes the domain-specific tradeoffs as a small truth table
/// so future drift is visible to tests rather than buried inline.
public enum IntentThresholds {

    /// Confidence label emitted by the classifier, normalized. Any unknown
    /// value is treated as `high` — matches the default path in
    /// `IntentClassifier.parseResponse`.
    public enum Confidence: String, Sendable {
        case high, medium, low

        public static func parse(_ raw: String) -> Confidence {
            switch raw.lowercased() {
            case "low":    return .low
            case "medium": return .medium
            default:       return .high
            }
        }
    }

    /// Decision returned by `shouldClarify`. Semantics:
    /// - `.proceed`: hand off to the tool; no clarification UI.
    /// - `.clarify`: route to `ClarificationBuilder.buildOptions`. If the
    ///   builder declines (no concrete alternatives), caller falls through
    ///   to proceed — matches the pre-existing fallback behavior.
    public enum Decision: Equatable, Sendable { case proceed, clarify }

    /// False-confirm sensitivity tier for write tools. Encodes the cost
    /// asymmetry between asking a redundant clarifier vs silently committing
    /// the wrong data. Read-only tools never reach this branch — they're
    /// routed via `IntentDomain.data` or via the param-complete path.
    ///
    /// - `.low`: false-confirm is cheap and recoverable. The user can undo a
    ///   misclassified food log with one tap, and the cost of a redundant
    ///   "what did you have?" is high friction during a frequent, fast
    ///   workflow. Bias: PROCEED. Applies to log_food and log_activity.
    /// - `.high`: false-confirm corrupts the data model in a way that's
    ///   either hard to notice or hard to repair. Bias: CLARIFY earlier (at
    ///   medium + incomplete params, not just low). Applies to log_weight,
    ///   set_goal (weight unit ambiguity = 60% mass swing — wrong kg/lbs
    ///   poisons trend chart, ETA prediction, calorie target), and
    ///   mark_supplement (medical-adherence accuracy beats friction).
    public enum FalseConfirmSensitivity: String, Sendable {
        case low, high

        /// Tools where the cost of a silent miscoding outweighs the friction
        /// of an extra question. Keep this list short and explicit — the
        /// default is `.low` so adding a tool to the prompt doesn't
        /// accidentally inherit a stricter policy.
        public static func of(tool: String) -> FalseConfirmSensitivity {
            switch tool {
            case "log_weight", "set_goal", "mark_supplement", "log_medication":
                return .high
            default:
                return .low
            }
        }
    }

    /// The single decision function. Pure, `nonisolated`, and small enough
    /// to unit-test exhaustively.
    ///
    /// Per-domain calibration captures **false-clarify cost vs false-confirm
    /// cost** asymmetry. Three buckets matter here:
    ///
    /// 1. **High false-clarify cost, low false-confirm cost** (food, exercise,
    ///    read tools): user is in a fast workflow; an extra "what did you
    ///    mean?" prompt costs more than a wrong tool call they can redo.
    ///    Threshold: clarify only on `low + incomplete`. Existing behavior.
    /// 2. **High false-confirm cost, moderate false-clarify cost** (log_weight,
    ///    set_goal, mark_supplement, log_medication): a silent miscoding
    ///    corrupts the trend chart or medical-adherence log. Threshold:
    ///    clarify on `medium + incomplete` AND `low + incomplete`. Note that
    ///    `hasCompleteParams` for these tools requires unit/name explicitly,
    ///    so "I weigh 165" with unit known still proceeds at medium.
    /// 3. **High false-confirm cost on screen routing** (navigate_to): "show
    ///    me my chart" could mean body_comp, weight, calories, glucose.
    ///    Demand `high` confidence; otherwise clarify. Existing behavior.
    ///
    /// Truth table (rows = sensitivity bucket, columns = confidence × complete-params):
    ///
    /// | bucket                              | high/any | med+complete | med+incomplete | low+complete | low+incomplete |
    /// |-------------------------------------|----------|--------------|----------------|--------------|----------------|
    /// | food/exercise/other (low FC-sens)   | proceed  | proceed      | proceed        | proceed      | clarify        |
    /// | weight/supplements WRITE (high FC)  | proceed  | proceed      | **clarify**    | proceed      | clarify        |
    /// | weight/supplements READ             | proceed  | proceed      | proceed        | proceed      | clarify        |
    /// | data                                | proceed  | proceed      | proceed        | proceed      | proceed        |
    /// | meta (navigate_to)                  | proceed  | clarify      | clarify        | clarify      | clarify        |
    ///
    /// The asymmetric cell (**clarify** at medium+incomplete for high-FC tools)
    /// is the per-domain calibration this function adds over the legacy
    /// symmetric rule. Test drift here is intentional — any change should
    /// surface in `IntentConfidenceCalibrationTests`.
    public nonisolated static func shouldClarify(
        tool: String,
        confidence: String,
        hasCompleteParams: Bool
    ) -> Decision {
        let domain = IntentDomain.of(tool: tool)
        let conf = Confidence.parse(confidence)
        switch domain {
        case .data:
            return .proceed
        case .meta:
            return conf == .high ? .proceed : .clarify
        case .food, .weight, .exercise, .supplements, .other:
            // Low + incomplete is always a clarify across writeable domains.
            if conf == .low && !hasCompleteParams { return .clarify }
            // Asymmetric tightening: high-sensitivity write tools also
            // clarify on medium + incomplete because a silent miscoded log
            // (wrong unit, wrong supplement) corrupts data downstream. See
            // `FalseConfirmSensitivity` rationale.
            if conf == .medium && !hasCompleteParams
                && FalseConfirmSensitivity.of(tool: tool) == .high {
                return .clarify
            }
            return .proceed
        }
    }
}
