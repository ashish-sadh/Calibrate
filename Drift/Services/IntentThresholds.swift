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
enum IntentDomain: String, Sendable, CaseIterable {
    /// log_food, food_info, edit_meal, delete_food, copy_yesterday, explain_calories
    case food
    /// log_weight, weight_info, set_goal
    case weight
    /// start_workout, log_activity, exercise_info, sleep_recovery
    case exercise
    /// mark_supplement, supplements
    case supplements
    /// body_comp, glucose, biomarkers, cross_domain_insight, weight_trend_prediction — read-only
    /// data queries, never ambiguous
    case data
    /// navigate_to — screen name is context-sensitive ("sleep tab" vs "sleep data")
    case meta
    /// fallback for unknown tools
    case other

    /// Map a tool name to its domain. Keep in sync with the tool list in
    /// `IntentClassifier.systemPrompt`.
    static func of(tool: String) -> IntentDomain {
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
        case "body_comp", "glucose", "biomarkers", "cross_domain_insight", "weight_trend_prediction":
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
enum IntentThresholds {

    /// Confidence label emitted by the classifier, normalized. Any unknown
    /// value is treated as `high` — matches the default path in
    /// `IntentClassifier.parseResponse`.
    enum Confidence: String, Sendable {
        case high, medium, low

        static func parse(_ raw: String) -> Confidence {
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
    enum Decision: Equatable, Sendable { case proceed, clarify }

    /// The single decision function. Pure, `nonisolated`, and small enough
    /// to unit-test exhaustively.
    ///
    /// Truth table (rows = domain, columns = confidence × complete-params):
    ///
    /// | domain       | high/any | medium+complete | medium+incomplete | low+complete | low+incomplete |
    /// |--------------|----------|-----------------|-------------------|--------------|----------------|
    /// | food         | proceed  | proceed         | proceed           | proceed      | clarify        |
    /// | weight       | proceed  | proceed         | proceed           | proceed      | clarify        |
    /// | exercise     | proceed  | proceed         | proceed           | proceed      | clarify        |
    /// | supplements  | proceed  | proceed         | proceed           | proceed      | clarify        |
    /// | data         | proceed  | proceed         | proceed           | proceed      | proceed        |
    /// | meta         | proceed  | clarify         | clarify           | clarify      | clarify        |
    /// | other        | proceed  | proceed         | proceed           | proceed      | clarify        |
    ///
    /// Rationales:
    /// - **food**: "chicken rice", "biryani 1 plate" — extractor emits
    ///   `medium` frequently but name+quantity is enough to proceed. Gold-set
    ///   failure: bare-food log ("had biryani") clarifying when the
    ///   extractor produced `{name:biryani}`. Proceed on medium; clarify only
    ///   when low AND incomplete.
    /// - **weight/exercise/supplements**: current behavior — clarify only on
    ///   low + incomplete. Preserves pass-through for "I weigh 165",
    ///   "did yoga 30 min", "took vitamin d".
    /// - **data**: body_comp/glucose/biomarkers take no required params;
    ///   clarification has nothing to disambiguate. Always proceed.
    /// - **meta**: navigate_to is *the* case the task calls out — "show me
    ///   my chart" routes to `navigate_to(screen:"weight")` at `medium`
    ///   confidence, but the user might have meant "show my body comp" or
    ///   "show calories today". Demand `high` to proceed; otherwise clarify.
    ///   Sensitivity: downgrading this to `proceed on medium` breaks the
    ///   dedicated meta test in `IntentConfidenceCalibrationTests`.
    nonisolated static func shouldClarify(
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
            if conf == .low && !hasCompleteParams { return .clarify }
            return .proceed
        }
    }
}
