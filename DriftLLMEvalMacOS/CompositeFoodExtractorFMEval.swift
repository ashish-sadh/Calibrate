import XCTest
import DriftCore
import Foundation

/// Tier-3 eval for the Apple Foundation Models composite-food extractor (#744 / design-666 QW2).
///
/// Mirrors the 30-row gold set from `CompositeFoodExtractorTests` (DriftCore Tier 0).
/// Two layers of assertion:
///
///   1. `goldSetRegressionFloor` — always runs. Pins the *current* FM-build
///      quality so a regression is loud. Floors are deliberately ~10pp below
///      measured to avoid flapping CI on per-run jitter.
///
///   2. `goldSetCutoverGate` — env-gated by `DRIFT_FM_EVAL_GATE_STRICT=1`.
///      Enforces the design-666 QW2 acceptance criteria (≥95% overall, ≥98%
///      on bare-juxtaposition / regional-connector FM-win rows). Run before
///      flipping the flag-on cutover; gate stays skipped in day-to-day CI
///      while the FM build closes the gap.
///
/// Both skip on macOS<26 because the FM `@Generable` schema is OS-gated —
/// without skip, the .unavailable error path would fire 30 times.
///
/// Run: xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
///      -only-testing:'DriftLLMEvalMacOS/CompositeFoodExtractorFMEval'
final class CompositeFoodExtractorFMEval: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try LLMEvalGate.requireLLM()  // report as skipped, never false-green
    }


    // MARK: - Gold set (mirrors DriftCore CompositeFoodExtractorTests)

    private struct Row {
        let input: String
        let target: [String]
        /// True for rows the regex misses or gets wrong — the FM-win surface that
        /// must hit the tighter ≥98% bar.
        let isFMWin: Bool
    }

    /// 30-row gold set. Kept in sync manually with the DriftCore Tier-0 gold set
    /// in `CompositeFoodExtractorTests.swift`. Tier-0 row count test pins 30,
    /// regex-baseline test pins what each row's regex output is — so divergence
    /// between this duplicate and the source is loud, not silent.
    private static let goldSet: [Row] = [
        // 1-12: connector-with — regex matches today, FM must match too
        .init(input: "coffee with milk",            target: ["coffee", "milk"], isFMWin: false),
        .init(input: "oatmeal with honey",          target: ["oatmeal", "honey"], isFMWin: false),
        .init(input: "toast with butter",           target: ["toast", "butter"], isFMWin: false),
        .init(input: "rice with dal",               target: ["rice", "dal"], isFMWin: false),
        .init(input: "chicken with vegetables",     target: ["chicken", "vegetables"], isFMWin: false),
        .init(input: "protein shake plus banana",   target: ["protein shake", "banana"], isFMWin: false),
        .init(input: "eggs plus toast",             target: ["eggs", "toast"], isFMWin: false),
        .init(input: "sandwich alongside soup",     target: ["sandwich", "soup"], isFMWin: false),
        .init(input: "salad alongside chicken",     target: ["salad", "chicken"], isFMWin: false),
        .init(input: "chicken served with rice",    target: ["chicken", "rice"], isFMWin: false),
        .init(input: "dal served with roti",        target: ["dal", "roti"], isFMWin: false),
        .init(input: "biryani with raita",          target: ["biryani", "raita"], isFMWin: false),
        // 13-18: multi-additive
        .init(input: "oatmeal with milk and honey",  target: ["oatmeal", "milk", "honey"], isFMWin: false),
        .init(input: "rice with dal and vegetables", target: ["rice", "dal", "vegetables"], isFMWin: false),
        .init(input: "toast with butter and jam",    target: ["toast", "butter", "jam"], isFMWin: false),
        .init(input: "biryani with raita and salad", target: ["biryani", "raita", "salad"], isFMWin: false),
        .init(input: "chai with toast and butter",   target: ["chai", "toast", "butter"], isFMWin: false),
        .init(input: "paratha with curd and pickle", target: ["paratha", "curd", "pickle"], isFMWin: false),
        // 19-22: verb prefix
        .init(input: "drank coffee with milk",      target: ["coffee", "milk"], isFMWin: false),
        .init(input: "just had oatmeal with honey", target: ["oatmeal", "honey"], isFMWin: false),
        .init(input: "i ate rice with dal",         target: ["rice", "dal"], isFMWin: false),
        .init(input: "had biryani with raita",      target: ["biryani", "raita"], isFMWin: false),
        // 23-25: meal suffix stripping
        .init(input: "coffee with milk for breakfast", target: ["coffee", "milk"], isFMWin: false),
        .init(input: "dal with rice for lunch",        target: ["dal", "rice"], isFMWin: false),
        .init(input: "biryani with raita for dinner",  target: ["biryani", "raita"], isFMWin: false),
        // 26-28: bare-juxtaposition Indian compounds — regex misses, FM-win
        .init(input: "dal chawal",   target: ["dal", "chawal"], isFMWin: true),
        .init(input: "idli sambar",  target: ["idli", "sambar"], isFMWin: true),
        .init(input: "rajma chawal", target: ["rajma", "chawal"], isFMWin: true),
        // 29-30: regional / verb-ending connectors — regex splits at wrong place, FM-win
        .init(input: "chicken biryani garnished with cilantro",
              target: ["chicken biryani", "cilantro"], isFMWin: true),
        .init(input: "toast topped with butter",
              target: ["toast", "butter"], isFMWin: true),
    ]

    // MARK: - Helpers

    /// Lowercased component-name list out of an FM extraction. Whitespace
    /// trimmed so trivial spacing drift doesn't tank parity numbers.
    private func extractedNames(_ entry: FMCompositeFoodEntry) -> [String] {
        entry.components.map {
            $0.foodName.lowercased().trimmingCharacters(in: .whitespaces)
        }
    }

    /// True when the FM extraction matches the target component list (case- and
    /// whitespace-insensitive). Order matters: the gold set lists the main item
    /// first and the prompt asks the model to preserve user-mentioned order.
    private func matches(_ entry: FMCompositeFoodEntry, target: [String]) -> Bool {
        extractedNames(entry) == target.map { $0.lowercased() }
    }

    private func skipUnlessFMAvailable() throws {
        if #available(macOS 26, iOS 26, *) { return }
        throw XCTSkip("FoundationModels @Generable schema requires macOS 26 / iOS 26 — host is older")
    }

    // MARK: - Gold-set parity

    /// Computed accuracy report for the full gold set. Shared by the always-on
    /// regression-floor test and the env-gated cutover gate so both speak the
    /// same numbers.
    private struct ParityReport {
        let hits: Int
        let total: Int
        let fmWinHits: Int
        let fmWinTotal: Int
        let misses: [(input: String, expected: [String], got: [String]?, reason: String)]

        var accuracy: Double { Double(hits) / Double(total) }
        var fmWinAccuracy: Double { fmWinTotal > 0 ? Double(fmWinHits) / Double(fmWinTotal) : 1.0 }

        var description: String {
            """

            Composite-food FM extractor parity:
              overall:  \(hits)/\(total) = \(String(format: "%.1f%%", accuracy * 100))
              fm-win:   \(fmWinHits)/\(fmWinTotal) = \(String(format: "%.1f%%", fmWinAccuracy * 100))
              misses (\(misses.count)):
            \(misses.map { "  - '\($0.input)' expected \($0.expected), got \($0.got ?? []) [\($0.reason)]" }.joined(separator: "\n"))
            """
        }
    }

    private func runGoldSet() async throws -> ParityReport {
        var hits = 0
        var fmWinHits = 0
        var fmWinTotal = 0
        var misses: [(input: String, expected: [String], got: [String]?, reason: String)] = []

        for row in Self.goldSet {
            if row.isFMWin { fmWinTotal += 1 }
            do {
                let entry = try await CompositeFoodExtractor.extract(text: row.input)
                if matches(entry, target: row.target) {
                    hits += 1
                    if row.isFMWin { fmWinHits += 1 }
                } else {
                    misses.append((row.input, row.target, extractedNames(entry), "mismatch"))
                }
            } catch FMCompositeFoodExtractorError.notComposite {
                misses.append((row.input, row.target, nil, "notComposite"))
            } catch FMCompositeFoodExtractorError.bounded(let n) {
                misses.append((row.input, row.target, nil, "bounded(\(n))"))
            } catch FMCompositeFoodExtractorError.unavailable {
                throw XCTSkip("FoundationModels unavailable at runtime — \(row.input)")
            } catch FMCompositeFoodExtractorError.sessionFailed(let msg) {
                misses.append((row.input, row.target, nil, "sessionFailed: \(msg)"))
            } catch {
                misses.append((row.input, row.target, nil, "error: \(error)"))
            }
        }

        return ParityReport(
            hits: hits, total: Self.goldSet.count,
            fmWinHits: fmWinHits, fmWinTotal: fmWinTotal,
            misses: misses
        )
    }

    /// Always-on regression floor. Locks the current FM-extractor quality so a
    /// drop is loud — but does NOT enforce the cutover-gate thresholds because
    /// today's FM build only reaches ~90% overall / ~40% on FM-win rows
    /// (bare-juxtaposition Indian compounds like "dal chawal" come back as
    /// notComposite). The strict gate lives in the env-gated test below.
    func testCompositeFoodExtractor_goldSetRegressionFloor() async throws {
        try skipUnlessFMAvailable()
        let report = try await runGoldSet()
        print(report.description)

        // Floors are calibrated to "current FM build − 10pp" so noise doesn't
        // flap CI. When a future model bump exceeds these, raise the floor.
        XCTAssertGreaterThanOrEqual(report.accuracy, 0.80,
            "Composite-food FM extractor regressed below the 80% floor.\(report.description)")
        XCTAssertGreaterThanOrEqual(report.fmWinAccuracy, 0.30,
            "Composite-food FM extractor regressed below the 30% FM-win floor.\(report.description)")
    }

    /// Cutover-gate: enforces the ≥95% overall / ≥98% FM-win thresholds the
    /// design-666 QW2 plan requires before flipping the flag-on cutover.
    /// Env-gated so day-to-day CI / preflight stays green while the FM build
    /// closes the gap; flip the env var in the preflight script when ready.
    /// Set `DRIFT_FM_EVAL_GATE_STRICT=1` to enforce.
    func testCompositeFoodExtractor_goldSetCutoverGate() async throws {
        try skipUnlessFMAvailable()
        guard ProcessInfo.processInfo.environment["DRIFT_FM_EVAL_GATE_STRICT"] == "1" else {
            throw XCTSkip("Set DRIFT_FM_EVAL_GATE_STRICT=1 to enforce the FM-extractor cutover gate")
        }
        let report = try await runGoldSet()
        print(report.description)

        XCTAssertGreaterThanOrEqual(report.accuracy, 0.95,
            "Composite-food FM extractor below 95% gold-set parity gate — cannot flip flag-on cutover.\(report.description)")
        XCTAssertGreaterThanOrEqual(report.fmWinAccuracy, 0.98,
            "Composite-food FM extractor below 98% bar on FM-win (regex-miss/wrong) rows. These are the cases the migration exists to fix — failing them defeats the point.\(report.description)")
    }

    // MARK: - Single-component (non-composite) behavior

    func testCompositeFoodExtractor_singleFoodReturnsNotComposite() async throws {
        try skipUnlessFMAvailable()

        do {
            _ = try await CompositeFoodExtractor.extract(text: "biryani")
            XCTFail("Expected .notComposite for a single-food input; got a successful extraction")
        } catch FMCompositeFoodExtractorError.notComposite {
            // Expected: single food → caller falls back to the regex path which
            // also returns nil, so log_food gets a single intent rather than a
            // composite. This is the "do nothing harmful" branch.
        } catch FMCompositeFoodExtractorError.unavailable {
            throw XCTSkip("FoundationModels unavailable at runtime")
        } catch {
            XCTFail("Expected .notComposite, got \(error)")
        }
    }

    // MARK: - Bounded-output guard

    func testCompositeFoodExtractor_doesNotExplodeIngredientWords() async throws {
        try skipUnlessFMAvailable()

        // "chicken biryani" must remain one component, not be split into
        // [chicken, biryani] — the prompt forbids ingredient-word splitting.
        // If the model still splits, the result either passes (single
        // composite of chicken+biryani, would-be FM-win row) or fails bounds.
        // Either is acceptable; the failure mode this guards against is
        // ".tooMany(9)"-style hallucinations where the model lists ingredient
        // words like "chicken, rice, spices, oil, ...".
        do {
            _ = try await CompositeFoodExtractor.extract(text: "chicken biryani")
            // Either notComposite (1 component) or a 2-component split — both fine.
        } catch FMCompositeFoodExtractorError.notComposite {
            // Expected for the "kept as one" interpretation.
        } catch FMCompositeFoodExtractorError.bounded(let n) {
            XCTFail("'chicken biryani' produced \(n) components — ingredient hallucination guard failed")
        } catch FMCompositeFoodExtractorError.unavailable {
            throw XCTSkip("FoundationModels unavailable at runtime")
        } catch {
            XCTFail("Unexpected error for 'chicken biryani': \(error)")
        }
    }
}
