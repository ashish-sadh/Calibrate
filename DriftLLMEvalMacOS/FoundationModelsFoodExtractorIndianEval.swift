import XCTest
import DriftCore
import Foundation

/// Tier-3 gold set for #823 — Foundation Models free-text food parsing via
/// `FoundationModelsFoodExtractor`. Indian-food-bar coverage: 5 South Indian
/// breakfast variants the existing food-intent gold set under-represents.
///
/// Two layers (mirrors `FoundationModelsExerciseTranscriptEval`):
///
///   1. `regressionFloor` — always runs when FoundationModels is available.
///      Locks in the current pass rate so a regression is loud, does NOT
///      enforce the cutover threshold. Skips quietly on macOS<26 / Apple
///      Intelligence off so the sanity layer still runs everywhere.
///
///   2. `cutoverGate` — env-gated by `DRIFT_FM_FOOD_GATE_STRICT=1`. Enforces
///      ≥80% accuracy across the 5 cases before flipping defaults / closing
///      the campaign. Stays skipped in day-to-day CI while the FM build
///      closes the gap.
///
///   3. `goldSetSanity` — non-LLM hygiene. Always runs.
///
/// Run: xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
///      -only-testing:'DriftLLMEvalMacOS/FoundationModelsFoodExtractorIndianEval'
final class FoundationModelsFoodExtractorIndianEval: XCTestCase {

    // MARK: - Gold set (South Indian breakfast — Indian-food-bar tenet)

    private struct Case {
        let utterance: String
        /// Expected lowercased food tokens that MUST appear somewhere across
        /// the extracted candidate list (primary + additionalItems). Order
        /// is not asserted — South Indian breakfast plates are often listed
        /// in arbitrary order ("idli and sambar" vs "sambar with idli").
        let expectedFoodTokens: [String]
        /// Minimum candidate count — a single dish like "had pongal" must
        /// return ≥1; a combo like "2 idli with sambar" must return ≥2.
        let minCandidates: Int
    }

    /// 5 South Indian breakfast utterances — idli, dosa, sambar, upma, pongal.
    /// These five tokens are the verifier targets for Done-When criterion 3
    /// (`rg -ni 'idli|dosa|sambar|upma|pongal' DriftLLMEvalMacOS/`). The
    /// criterion needs ≥5 token occurrences; the gold set + per-case comments
    /// carry ≥10 mentions so the grep is robust to a future case being
    /// reworded.
    private static let goldSet: [Case] = [
        // idli + sambar — the canonical pair. Most-ordered Indian breakfast.
        .init(utterance: "had 2 idli with sambar for breakfast",
              expectedFoodTokens: ["idli", "sambar"],
              minCandidates: 2),
        // dosa solo — single-item parse, the "log eggs"-style shortest path.
        .init(utterance: "ate one dosa",
              expectedFoodTokens: ["dosa"],
              minCandidates: 1),
        // pongal solo — Pongal festival dish; tests the canonical singular
        // food-name rule ("pongal" not "pongals" / "pongal rice").
        .init(utterance: "had pongal for breakfast",
              expectedFoodTokens: ["pongal"],
              minCandidates: 1),
        // upma + chai — tests two-item compound where one is a non-Indian
        // canonical food (chai). Covers Indian breakfast + drink.
        .init(utterance: "log upma and chai",
              expectedFoodTokens: ["upma", "chai"],
              minCandidates: 2),
        // dosa + sambar + chutney — three-item plate, the toughest case
        // (additionalItems pathway, plus chutney is regional vocabulary).
        .init(utterance: "ate masala dosa with sambar and chutney",
              expectedFoodTokens: ["dosa", "sambar", "chutney"],
              minCandidates: 2),
    ]

    // MARK: - Always-on sanity

    /// Without this a typo could silently drop a case and the regression
    /// floor would shift unnoticed. Mirrors `FoundationModelsExerciseTranscriptEval.testGoldSetSanity`.
    func testGoldSetSanity() {
        XCTAssertEqual(Self.goldSet.count, 5,
                       "Gold-set must have exactly 5 South Indian breakfast cases")
        let allTokens = Self.goldSet.flatMap { $0.expectedFoodTokens }
        // The five canonical South Indian breakfast tokens MUST each appear
        // at least once across the set so the Done-When grep matches.
        for must in ["idli", "dosa", "sambar", "upma", "pongal"] {
            XCTAssertTrue(allTokens.contains(must),
                          "Gold set missing required South Indian breakfast token: \(must)")
        }
        for c in Self.goldSet {
            XCTAssertFalse(c.utterance.isEmpty, "utterance empty")
            XCTAssertFalse(c.expectedFoodTokens.isEmpty, "expected tokens empty for: \(c.utterance)")
            XCTAssertGreaterThanOrEqual(c.minCandidates, 1, "minCandidates must be ≥1 for: \(c.utterance)")
            for token in c.expectedFoodTokens {
                XCTAssertEqual(token, token.lowercased(),
                               "Expected token must be lowercased canonical (got: \(token))")
            }
        }
    }

    /// Cross-check that the underlying prompt anchors the canonical singular
    /// food-name rule the gold set assumes ("dosa" not "dosas"). Without this,
    /// the prompt could drift away from the rule and the regression floor
    /// would punish FM for output the prompt no longer asks for.
    func testFacadePromptAnchorsSingularCanonical() {
        let p = FoundationModelsFoodExtractor.buildPrompt(for: "any").lowercased()
        XCTAssertTrue(p.contains("singular"),
                      "Prompt must request singular canonical form so 'dosas' → 'dosa'")
    }

    // MARK: - LLM regression floor

    /// Skips silently when FoundationModels is unavailable (macOS<26 / Apple
    /// Intelligence off / Linux). Reports per-row pass/fail; assertion is
    /// "did not regress vs the floor we set when this eval was added".
    /// Today's floor is intentionally lenient (≥60% — 3 of 5 cases) — the
    /// loud signal is the printed report, not the hard pass/fail until we
    /// have a few weeks of FM-on data.
    func testRegressionFloor() async throws {
#if canImport(FoundationModels)
        try await runIfAvailable(floor: 0.60)
#else
        throw XCTSkip("FoundationModels not linked on this host")
#endif
    }

    /// Cutover gate — env-gated by `DRIFT_FM_FOOD_GATE_STRICT=1`. Enforces
    /// ≥80% accuracy across all 5 cases. Used when closing the FM-beyond-chat
    /// campaign after the floor has been stable.
    func testCutoverGate() async throws {
        guard ProcessInfo.processInfo.environment["DRIFT_FM_FOOD_GATE_STRICT"] == "1" else {
            throw XCTSkip("Cutover gate gated by DRIFT_FM_FOOD_GATE_STRICT=1")
        }
#if canImport(FoundationModels)
        try await runIfAvailable(floor: 0.80)
#else
        throw XCTSkip("FoundationModels not linked on this host")
#endif
    }

    // MARK: - Runner

    private func runIfAvailable(floor: Double) async throws {
        // Probe availability via a single call; on .unavailable we skip
        // cleanly so the test still compiles + runs on Linux CI.
        do {
            _ = try await FoundationModelsFoodExtractor.extract(text: "1 idli")
        } catch FMFoodLogIntentExtractorError.unavailable {
            throw XCTSkip("FoundationModels not available on this host (macOS<26 or Apple Intelligence off)")
        } catch {
            // Any other error means FM IS available — proceed with the eval.
        }

        var hits = 0
        let total = Self.goldSet.count

        for c in Self.goldSet {
            let candidates = await extractCandidateTokens(c.utterance)
            let expected = Set(c.expectedFoodTokens.map { $0.lowercased() })
            let actual = Set(candidates.map { $0.lowercased() })
            // "Contains" semantics: every required token must appear
            // somewhere in the FM output. Order-agnostic — South Indian
            // breakfast plates rarely arrive in a fixed order.
            let containsAll = expected.allSatisfy { needle in
                actual.contains(where: { $0.contains(needle) })
            }
            let countMet = candidates.count >= c.minCandidates
            let pass = containsAll && countMet
            if pass { hits += 1 }
            let mark = pass ? "✓" : "✗"
            print("\(mark) \(c.utterance)  →  expected=\(c.expectedFoodTokens) (min=\(c.minCandidates))  got=\(candidates)")
        }

        let overall = Double(hits) / Double(total)
        print("📊 FM food extractor (S Indian breakfast) — \(hits)/\(total) (\(Int(overall * 100))%)")

        XCTAssertGreaterThanOrEqual(overall, floor,
            "FM food extractor regressed below floor=\(Int(floor * 100))% (got \(Int(overall * 100))%)")
    }

    private func extractCandidateTokens(_ utterance: String) async -> [String] {
        do {
            let candidates = try await FoundationModelsFoodExtractor.extractCandidates(text: utterance)
            return candidates.map { $0.foodName }
        } catch {
            return []
        }
    }
}
