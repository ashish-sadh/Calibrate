import Foundation
import XCTest

/// Tier-3 gate for LLM-backed eval suites (2026-07-30).
///
/// The DriftLLMEvalMacOS scheme doubles as two tiers:
///   - Default run (no flag): ONLY the deterministic suites execute — the
///     fast always-on gate (~1 min). LLM-backed suites report as skipped.
///   - `DRIFT_LLM_EVAL=1`: the real-model Tier-3 suites run too. Budget
///     1–3 h wall time (ComposedFoodEval alone is ~17 min).
///
/// Shell env vars do NOT reach the macOS test host (Xcode 13+), so the flag
/// must be passed as a BUILD SETTING that the scheme forwards via
/// `$(DRIFT_LLM_EVAL)` (see project.yml scheme environmentVariables):
///
///     xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' DRIFT_LLM_EVAL=1
///
/// Two call sites per gated suite, both required:
///   - `guard LLMEvalGate.enabled else { return }` first thing in
///     `class func setUp()` — prevents the multi-minute model load.
///   - `try LLMEvalGate.requireLLM()` in `setUpWithError()` — makes every
///     test report as SKIPPED instead of silently passing with a nil backend.
enum LLMEvalGate {
    static var enabled: Bool {
        ProcessInfo.processInfo.environment["DRIFT_LLM_EVAL"] == "1"
    }

    static func requireLLM() throws {
        guard enabled else {
            throw XCTSkip("Tier-3 LLM eval — pass DRIFT_LLM_EVAL=1 as a build setting to run")
        }
    }
}
