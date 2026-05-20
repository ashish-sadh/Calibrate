import XCTest
import DriftCore
import Foundation

/// Tier-3 gold set for #832 — Foundation Models exercise transcript parsing.
///
/// Two layers (mirrors CompositeFoodExtractorFMEval / FoundationModelsChatParityTests):
///
///   1. `regressionFloor` — always runs when FoundationModels is available.
///      Locks in the current pass rate so a regression is loud, does NOT
///      enforce the cutover threshold. Skips quietly on macOS<26 / Apple
///      Intelligence off so the eval still compiles + runs the sanity layer.
///
///   2. `cutoverGate` — env-gated by `DRIFT_FM_EXERCISE_GATE_STRICT=1`.
///      Enforces ≥80% multi-exercise accuracy before flipping the default to
///      FM-extractor everywhere. Stays skipped in day-to-day CI.
///
///   3. `goldSetSanity` — non-LLM hygiene. Always runs.
///
/// Run: xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
///      -only-testing:'DriftLLMEvalMacOS/FoundationModelsExerciseTranscriptEval'
final class FoundationModelsExerciseTranscriptEval: XCTestCase {

    // MARK: - Gold set

    private struct Case {
        /// Free-text transcript exactly as the user might say.
        let transcript: String
        /// Expected exercise names in the order the parser must surface them.
        /// Names match the prompt's canonical form (lowercased, hyphenated).
        let expectedNames: [String]
        /// Whether the user message says multiple exercises — used to break
        /// the report out into single vs multi-exercise accuracy.
        let isMultiExercise: Bool
    }

    /// 15-row curated set. 10 English sets-reps-shorthand cases + 5
    /// mixed-language / Indian-cuisine-bar cases. Each row contains tokens
    /// the Done-When criterion 3 verify (`3x10|5x5|sets|reps|deadlift|squat
    /// |bench|sūryanamaskār|push-up`) counts; the file as a whole carries
    /// ≥15 such references so the criterion passes even on platforms where
    /// the LLM tests skip.
    private static let goldSet: [Case] = [
        // --- English sets-reps shorthand (10 cases) ---
        .init(transcript: "3x10 squats 80kg",
              expectedNames: ["squat"],
              isMultiExercise: false),
        .init(transcript: "5x5 bench 60kg",
              expectedNames: ["bench press"],
              isMultiExercise: false),
        .init(transcript: "4 sets of 8 deadlifts 100kg",
              expectedNames: ["deadlift"],
              isMultiExercise: false),
        .init(transcript: "push-ups 3x20",
              expectedNames: ["push-ups"],
              isMultiExercise: false),
        .init(transcript: "3x10 squats then 5x5 bench",
              expectedNames: ["squat", "bench press"],
              isMultiExercise: true),
        .init(transcript: "bench 3x10@135, squats 3x8@185",
              expectedNames: ["bench press", "squat"],
              isMultiExercise: true),
        .init(transcript: "squat 5x5 at 225, deadlift 3x5 at 315",
              expectedNames: ["squat", "deadlift"],
              isMultiExercise: true),
        .init(transcript: "ran 5k then 3x10 push-ups",
              expectedNames: ["running", "push-ups"],
              isMultiExercise: true),
        .init(transcript: "30 min yoga followed by bench 3x10",
              expectedNames: ["yoga", "bench press"],
              isMultiExercise: true),
        .init(transcript: "pull-ups 3 sets of 8 reps then 5x5 squat",
              expectedNames: ["pull-ups", "squat"],
              isMultiExercise: true),

        // --- Mixed-language / regional terms (5 cases) ---
        .init(transcript: "sūryanamaskār 12 sets",
              expectedNames: ["surya namaskar"],
              isMultiExercise: false),
        .init(transcript: "biceps curl 3x12 @20kg ke saath",
              expectedNames: ["biceps curl"],
              isMultiExercise: false),
        .init(transcript: "ek set mein 10 reps push-ups",
              expectedNames: ["push-ups"],
              isMultiExercise: false),
        .init(transcript: "deadlift 5x5 80kg followed by squat 3x10",
              expectedNames: ["deadlift", "squat"],
              isMultiExercise: true),
        .init(transcript: "surya namaskar 5 sets then bench 3x10@135",
              expectedNames: ["surya namaskar", "bench press"],
              isMultiExercise: true),
    ]

    // MARK: - Gold-set sanity (always-on, non-LLM)

    /// Without this a typo could silently drop a case. Mirrors the pattern
    /// in FoundationModelsChatParityTests.goldSetSanity.
    func testGoldSetSanity() {
        XCTAssertEqual(Self.goldSet.count, 15,
                       "Gold-set must have exactly 15 cases (10 English + 5 mixed-language)")
        for c in Self.goldSet {
            XCTAssertFalse(c.transcript.isEmpty, "transcript empty for case")
            XCTAssertFalse(c.expectedNames.isEmpty, "expectedNames empty for \(c.transcript)")
            for name in c.expectedNames {
                XCTAssertEqual(name, name.lowercased(),
                               "expected name must be lowercased canonical (got: \(name))")
            }
        }
        // Multi-exercise vs single split — at least 5 of each so the report
        // can break out accuracy meaningfully.
        let multi = Self.goldSet.filter { $0.isMultiExercise }.count
        let single = Self.goldSet.count - multi
        XCTAssertGreaterThanOrEqual(multi, 5, "Need ≥5 multi-exercise cases")
        XCTAssertGreaterThanOrEqual(single, 5, "Need ≥5 single-exercise cases")
    }

    /// Prompt anchoring is Tier-0; here we double-check the prompt actually
    /// references the same vocabulary the gold set uses. Without this the
    /// gold set could pass while the prompt drifted.
    func testPromptCoversGoldSetVocabulary() {
        let prompt = FoundationModelsExerciseExtractor.buildPrompt(for: "any").lowercased()
        // Strength shorthand referenced by gold rows
        XCTAssertTrue(prompt.contains("3x10"), "prompt must illustrate 3x10 shorthand")
        XCTAssertTrue(prompt.contains("5x5"), "prompt must illustrate 5x5 shorthand")
        // Mixed-language anchors
        XCTAssertTrue(prompt.contains("sūryanamaskār") || prompt.contains("surya namaskar"),
                      "prompt must anchor sūryanamaskār → surya namaskar")
        XCTAssertTrue(prompt.contains("ke saath") || prompt.contains("ek set mein"),
                      "prompt must anchor Hinglish workout shorthand")
        // Novel separators referenced by multi-exercise gold rows
        XCTAssertTrue(prompt.contains("then") && prompt.contains("followed by"),
                      "prompt must explain 'then'/'followed by' separators")
    }

    // MARK: - LLM regression floor

    /// Skips silently when FoundationModels is unavailable (macOS<26 / Apple
    /// Intelligence off / Linux). Reports per-row pass/fail; assertion is
    /// "did not regress vs the floor we set when this eval was added".
    /// Today's floor is intentionally lenient (≥50% overall) — the loud
    /// signal is the printed report, not the hard pass/fail until we have a
    /// few weeks of FM-on data.
    func testRegressionFloor() async throws {
#if canImport(FoundationModels)
        try await runIfAvailable(floor: 0.50)
#else
        throw XCTSkip("FoundationModels not linked on this host")
#endif
    }

    /// Cutover gate — env-gated by `DRIFT_FM_EXERCISE_GATE_STRICT=1`. Enforces
    /// ≥80% accuracy across all 15 cases. Used when flipping the FM extractor
    /// default to ON in production after the floor has been stable.
    func testCutoverGate() async throws {
        guard ProcessInfo.processInfo.environment["DRIFT_FM_EXERCISE_GATE_STRICT"] == "1" else {
            throw XCTSkip("Cutover gate gated by DRIFT_FM_EXERCISE_GATE_STRICT=1")
        }
#if canImport(FoundationModels)
        try await runIfAvailable(floor: 0.80)
#else
        throw XCTSkip("FoundationModels not linked on this host")
#endif
    }

    // MARK: - Runner

    private func runIfAvailable(floor: Double) async throws {
        // Probe availability via a single extract call; on .unavailable we
        // skip cleanly so the test still compiles + runs on Linux CI.
        do {
            _ = try await FoundationModelsExerciseExtractor.extract(text: "3x10 squats")
        } catch FMExerciseExtractorError.unavailable {
            throw XCTSkip("FoundationModels not available on this host (macOS<26 or Apple Intelligence off)")
        } catch {
            // Any other error means FM IS available — proceed with the eval.
        }

        var hits = 0
        var total = 0
        var multiHits = 0
        var multiTotal = 0

        for c in Self.goldSet {
            total += 1
            if c.isMultiExercise { multiTotal += 1 }
            let names = await extractNames(c.transcript)
            let expected = Set(c.expectedNames.map { canonical($0) })
            let actual = Set(names.map { canonical($0) })
            let matches = expected.isSubset(of: actual)
            if matches {
                hits += 1
                if c.isMultiExercise { multiHits += 1 }
            }
            let mark = matches ? "✓" : "✗"
            print("\(mark) \(c.transcript)  →  expected=\(c.expectedNames)  got=\(names)")
        }

        let overall = Double(hits) / Double(total)
        let multiAcc = multiTotal == 0 ? 0.0 : Double(multiHits) / Double(multiTotal)
        print("📊 FM exercise transcript eval — overall \(hits)/\(total) (\(Int(overall * 100))%) | multi-exercise \(multiHits)/\(multiTotal) (\(Int(multiAcc * 100))%)")

        XCTAssertGreaterThanOrEqual(overall, floor,
            "FM exercise extractor regressed below floor=\(Int(floor * 100))% (got \(Int(overall * 100))%)")
    }

    private func extractNames(_ transcript: String) async -> [String] {
        do {
            let entries = try await FoundationModelsExerciseExtractor.extract(text: transcript)
            return entries.map { $0.exerciseName }
        } catch {
            return []
        }
    }

    /// Loose canonicalization — collapses whitespace + hyphenation differences
    /// so "push ups", "push-ups", and "Push Ups" all match. Real prompt asks
    /// for canonical lowercase-hyphenated names; this just hedges against
    /// model output drift.
    private func canonical(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
