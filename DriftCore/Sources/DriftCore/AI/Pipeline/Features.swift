import Foundation

/// Compile-time feature flags for experimental AI-pipeline behavior.
/// Flip to false to disable a flagged behavior without removing code.
enum Features {

    /// Retry intent classification once with a "be literal" hint when the
    /// first extraction returns no tool call or incomplete params for one
    /// of the top-5 tools (log_food, edit_meal, log_weight, mark_supplement,
    /// food_info). Catches tail-distribution phrasings the gold set misses.
    /// Adds one extra LLM call ONLY on the retry path; successful first
    /// extractions are unaffected. #240.
    static let autoRetryOnEmpty = true

    /// Two-stage classifier experiment (#163/#451): Stage A routes to domain,
    /// Stage B extracts tool+params within that domain. Off by default — only
    /// ship if MultiStageEval shows ≥+2% accuracy with no latency regression.
    static let multiStageClassifier = false
}
