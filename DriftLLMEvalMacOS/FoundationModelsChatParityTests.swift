import XCTest
import DriftCore
import Foundation

/// Tier-3 parity gate for the `.foundationModels` chat backend (#791 / Task 1 PR B).
///
/// Compares the candidate `FoundationModelsBackend` against the production
/// `LlamaCppBackend` Gemma baseline on a curated subset of the IntentRouting
/// gold set. Mirrors the design of `CompositeFoodExtractorFMEval` (#771):
///
///   1. `parityRegressionFloor` — always runs when FM + Gemma are both
///      available. Locks in current parity so a regression is loud, but does
///      NOT enforce the cutover threshold (we measure, not gate, until the
///      default flips). Today's FM build is expected to be below 95% — the
///      value is the printed report and the "loud on drop" check, not the
///      pass/fail bar.
///
///   2. `parityCutoverGate` — always MEASURES + emits the parity number (like
///      the regression floor); BLOCKS on the ≥95% overall / ≥98% critical bar
///      ONLY while Foundation Models is the active default backend. Per the
///      #872 NO-GO the default is the on-device llama.cpp/Gemma baseline, so
///      the gate measures every run but auto-passes — never a silent green-skip
///      into dormancy — and re-arms automatically the moment FM is re-promoted
///      to default (#874). The 95/98 thresholds stay the bar FM must re-clear.
///
///   3. `goldSetSanity` — non-LLM hygiene check on the gold-set shape itself.
///      Always runs; without it a typo could silently drop a critical case.
///
/// Both LLM tests skip on macOS<26 / Apple-Intelligence-off because
/// `SystemLanguageModel.default.isAvailable` returns false there.
///
/// Run: xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
///      -only-testing:'DriftLLMEvalMacOS/FoundationModelsChatParityTests'
final class FoundationModelsChatParityTests: XCTestCase {

    // MARK: - Gold set (curated subset of IntentRoutingEval)

    private struct Case {
        let query: String
        let expectedTool: String
        let history: String
        /// High-stakes routing categories — food log, weight log, multi-turn
        /// continuation. Failures here have the highest user-visible cost,
        /// so the cutover gate enforces a tighter parity bar (≥98%).
        let isCritical: Bool
    }

    /// 41-row curated set. Smaller than the full IntentRouting eval because
    /// each row runs TWO backends — we'd otherwise double the ~12-min eval
    /// budget. Coverage spans the categories most likely to diverge between
    /// a 2B llama.cpp model and Apple's much-larger Foundation Model.
    /// Multi-turn depth (12 non-empty-history cases) and Indian-first routing
    /// are deliberately over-weighted: epic #860 (FM chat reliability gate)
    /// found those are where FM ↔ Gemma attention diverges most.
    private static let goldSet: [Case] = [
        // --- Critical: food logging (explicit + implicit + Indian) ---
        .init(query: "log 2 eggs", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "I had biryani", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "ate dal and rice", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "had a protein shake", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "drank 2 cups of coffee", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "had dal chawal for lunch", expectedTool: "log_food", history: "", isCritical: true),
        // --- Critical: weight logging ---
        .init(query: "I weigh 75 kg", expectedTool: "log_weight", history: "", isCritical: true),
        .init(query: "logged 73.2 kg this morning", expectedTool: "log_weight", history: "", isCritical: true),
        // --- Critical: multi-turn continuation (context-dependent routing) ---
        .init(query: "also add toast",
              expectedTool: "log_food",
              history: "User: log 2 eggs\nAssistant: Logged 2 eggs (148 cal)",
              isCritical: true),
        .init(query: "rice and dal",
              expectedTool: "log_food",
              history: "Assistant: What did you have for lunch?",
              isCritical: true),
        // --- Info queries ---
        .init(query: "calories left", expectedTool: "food_info", history: "", isCritical: false),
        .init(query: "how much protein today", expectedTool: "food_info", history: "", isCritical: false),
        // --- Non-food domains ---
        .init(query: "how was my sleep last night", expectedTool: "sleep_recovery", history: "", isCritical: false),
        .init(query: "how's my body fat", expectedTool: "body_comp", history: "", isCritical: false),
        .init(query: "show my biomarkers", expectedTool: "biomarkers", history: "", isCritical: false),
        .init(query: "any glucose spikes", expectedTool: "glucose", history: "", isCritical: false),
        // --- Workout ---
        .init(query: "start push day", expectedTool: "start_workout", history: "", isCritical: false),
        .init(query: "did yoga for 30 minutes", expectedTool: "log_activity", history: "", isCritical: false),
        .init(query: "how much did I bench", expectedTool: "exercise_info", history: "", isCritical: false),
        // --- Supplements (mark vs status) ---
        .init(query: "took creatine", expectedTool: "mark_supplement", history: "", isCritical: false),
        .init(query: "did I take my vitamins", expectedTool: "supplements", history: "", isCritical: false),
        // --- Goal / delete / weight info ---
        .init(query: "set my goal to 150 lbs", expectedTool: "set_goal", history: "", isCritical: false),
        .init(query: "delete last entry", expectedTool: "delete_food", history: "", isCritical: false),
        .init(query: "what's my weight trend", expectedTool: "weight_info", history: "", isCritical: false),
        // --- Navigation ---
        .init(query: "go to food tab", expectedTool: "navigate_to", history: "", isCritical: false),

        // === Expanded multi-turn (epic #860) — 3+ turn chains, topic-switch,
        //     correction-after-N-turns, entry-reference resolution. This is the
        //     coverage gap the arc exists to close (only 2 two-turn cases before). ===
        // 3+ turn food chain — continuation after two prior log turns.
        .init(query: "and a banana",
              expectedTool: "log_food",
              history: "User: log 2 eggs\nAssistant: Logged 2 eggs (148 cal)\nUser: also some toast\nAssistant: Added 1 slice toast (75 cal)",
              isCritical: true),
        // 3+ turn Indian food chain — mixed-language continuation.
        .init(query: "and some curd on the side",
              expectedTool: "log_food",
              history: "User: had idli for breakfast\nAssistant: Logged 3 idli (158 cal)\nUser: with sambar\nAssistant: Added sambar (120 cal)",
              isCritical: true),
        // Topic-switch mid-conversation: food → weight.
        .init(query: "I weigh 74 kg today",
              expectedTool: "log_weight",
              history: "User: log dal and rice\nAssistant: Logged dal and rice (320 cal)\nUser: thanks",
              isCritical: true),
        // Topic-switch mid-conversation: food → sleep info (non-food domain).
        .init(query: "how was my sleep last night",
              expectedTool: "sleep_recovery",
              history: "User: had paneer tikka for dinner\nAssistant: Logged paneer tikka (290 cal)",
              isCritical: false),
        // Correction-after-N-turns: revise a logged food quantity (re-extract → log_food).
        .init(query: "actually make it 3 rotis",
              expectedTool: "log_food",
              history: "User: log 2 rotis\nAssistant: Logged 2 rotis (140 cal)\nUser: hmm",
              isCritical: true),
        // Correction-after-N-turns: revise a logged weight value (re-extract → log_weight).
        .init(query: "no wait it's 74.5",
              expectedTool: "log_weight",
              history: "User: I weigh 75 kg\nAssistant: Logged 75 kg\nUser: that's not right",
              isCritical: true),
        // Entry-reference resolution: "that" = the just-logged entry → delete.
        .init(query: "remove that",
              expectedTool: "delete_food",
              history: "User: log a samosa\nAssistant: Logged 1 samosa (260 cal)",
              isCritical: true),
        // Entry-reference resolution: "that" = the just-logged entry → info.
        .init(query: "how many calories was that",
              expectedTool: "food_info",
              history: "User: I had a masala dosa\nAssistant: Logged 1 masala dosa (168 cal)",
              isCritical: false),
        // Assistant-prompt → answer: bare food answer routes to log_food in context.
        .init(query: "chicken curry and 2 rotis",
              expectedTool: "log_food",
              history: "Assistant: What did you have for dinner?",
              isCritical: true),
        // Topic-switch: workout context → post-workout food log.
        .init(query: "had a protein shake after",
              expectedTool: "log_food",
              history: "User: start push day\nAssistant: Started push day workout\nUser: done with my sets",
              isCritical: true),

        // === Indian-first single-turn routing (tenet #4) — dishes/terms a 2B
        //     Gemma and a much-larger FM are most likely to route differently. ===
        .init(query: "had idli for breakfast", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "ate masala dosa", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "had paneer tikka and naan", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "drank a bowl of sambar", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "had rasam with rice", expectedTool: "log_food", history: "", isCritical: true),
        .init(query: "ate poha this morning", expectedTool: "log_food", history: "", isCritical: true),
    ]

    // MARK: - Backends (loaded once per class)

    nonisolated(unsafe) static var llamaCppBackend: LlamaCppBackend?
    nonisolated(unsafe) static var fmBackend: FoundationModelsBackend?

    static let gemmaPath = URL.homeDirectory.appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")

    override class func setUp() {
        super.setUp()
        // Llama.cpp Gemma baseline — parity has no meaning without the
        // baseline, so bail loud if the model file is missing.
        guard FileManager.default.fileExists(atPath: gemmaPath.path) else {
            fatalError("""
            ❌ Gemma 4 model not found at \(gemmaPath.path)
            Run: bash scripts/download-models.sh
            """)
        }
        let llama = LlamaCppBackend(modelPath: gemmaPath, threads: 6)
        try? llama.loadSync()
        guard llama.isLoaded else {
            fatalError("❌ Gemma 4 failed to load — check model file integrity")
        }
        llamaCppBackend = llama
        print("✅ Gemma 4 (llama.cpp) loaded as parity baseline")

        // FM backend — system-managed, no load step. The runtime
        // `isAvailableNow` flag decides whether the LLM tests skip;
        // we keep the instance around either way for a consistent report.
        fmBackend = FoundationModelsBackend()
        if FoundationModelsBackend.isAvailableNow {
            print("✅ FoundationModels available — parity test will run")
        } else {
            print("ℹ️ FoundationModels unavailable on this host (macOS<26 or Apple-Intelligence off) — parity test will skip")
        }
    }

    // MARK: - Helpers

    private func skipUnlessBothAvailable() throws {
        guard Self.llamaCppBackend != nil else {
            throw XCTSkip("LlamaCpp baseline not loaded")
        }
        guard FoundationModelsBackend.isAvailableNow else {
            throw XCTSkip("FoundationModels not available on this host (requires macOS 26+ with Apple Intelligence enabled)")
        }
    }

    /// Single source of truth for the classification prompt — same one the
    /// per-stage evals and production IntentClassifier use. Pulling it from
    /// `PerStageEvalSupport` keeps this test from drifting if the prompt
    /// is edited in `IntentClassifier`.
    private static var systemPrompt: String { PerStageEvalSupport.systemPrompt }

    private func extractTool(_ response: String) -> String? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              let data = String(response[start...end]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tool = json["tool"] as? String else { return nil }
        return tool
    }

    /// Mirrors `IntentRoutingEval.classify`'s history-folding so both
    /// backends see the same input format. Without this the FM side would
    /// be tested on a different surface than the production routing path.
    private func userMessage(query: String, history: String) -> String {
        history.isEmpty ? query : "Chat:\n\(String(history.prefix(400)))\n\nUser: \(query)"
    }

    private func classifyLlama(_ c: Case) async -> String {
        guard let backend = Self.llamaCppBackend else { return "" }
        return await backend.respond(to: userMessage(query: c.query, history: c.history),
                                     systemPrompt: Self.systemPrompt)
    }

    private func classifyFM(_ c: Case) async -> String {
        guard let backend = Self.fmBackend else { return "" }
        return await backend.respond(to: userMessage(query: c.query, history: c.history),
                                     systemPrompt: Self.systemPrompt)
    }

    // MARK: - Parity report

    private struct ParityReport {
        var totalCases: Int
        var llamaHits: Int          // baseline matched expected
        var fmHits: Int             // candidate matched expected
        var parity: Int             // both produced the same tool extraction
        var fmWins: Int             // FM correct where llama wrong
        var fmLosses: Int           // FM wrong where llama correct
        var criticalTotal: Int
        var criticalParity: Int
        var divergences: [(query: String, expected: String, llama: String?, fm: String?)] = []

        var llamaAccuracy: Double { Double(llamaHits) / Double(totalCases) }
        var fmAccuracy: Double { Double(fmHits) / Double(totalCases) }
        var parityRate: Double { Double(parity) / Double(totalCases) }
        var criticalParityRate: Double {
            criticalTotal > 0 ? Double(criticalParity) / Double(criticalTotal) : 1.0
        }

        var description: String {
            """

            FoundationModels chat-backend parity vs llama.cpp Gemma baseline:
              overall parity:    \(parity)/\(totalCases) = \(String(format: "%.1f%%", parityRate * 100))
              critical parity:   \(criticalParity)/\(criticalTotal) = \(String(format: "%.1f%%", criticalParityRate * 100))
              llama accuracy:    \(llamaHits)/\(totalCases) = \(String(format: "%.1f%%", llamaAccuracy * 100))
              fm accuracy:       \(fmHits)/\(totalCases) = \(String(format: "%.1f%%", fmAccuracy * 100))
              fm wins / losses:  \(fmWins) / \(fmLosses)
              divergences (\(divergences.count)):
            \(divergences.prefix(20).map { "  - '\($0.query)' expected '\($0.expected)' | llama='\($0.llama ?? "text")' fm='\($0.fm ?? "text")'" }.joined(separator: "\n"))
            """
        }
    }

    private func runGoldSet() async -> ParityReport {
        var report = ParityReport(
            totalCases: Self.goldSet.count,
            llamaHits: 0, fmHits: 0, parity: 0, fmWins: 0, fmLosses: 0,
            criticalTotal: 0, criticalParity: 0
        )
        for c in Self.goldSet {
            let llamaResp = await classifyLlama(c)
            let fmResp = await classifyFM(c)
            let llamaTool = extractTool(llamaResp)
            let fmTool = extractTool(fmResp)
            let llamaCorrect = llamaTool == c.expectedTool
            let fmCorrect = fmTool == c.expectedTool
            if llamaCorrect { report.llamaHits += 1 }
            if fmCorrect { report.fmHits += 1 }
            if c.isCritical { report.criticalTotal += 1 }
            if llamaTool == fmTool {
                report.parity += 1
                if c.isCritical { report.criticalParity += 1 }
            } else {
                report.divergences.append((c.query, c.expectedTool, llamaTool, fmTool))
                if fmCorrect && !llamaCorrect { report.fmWins += 1 }
                if !fmCorrect && llamaCorrect { report.fmLosses += 1 }
            }
        }
        return report
    }

    // MARK: - Tests

    /// Always-on parity report when both backends are available. Soft floors
    /// only — the cutover decision lives in the env-gated test below.
    ///
    /// Floors are deliberately generous: this test exists to (a) emit the
    /// per-run parity report so a human reading CI output can see the trend,
    /// and (b) shout if the FM backend goes catastrophically broken
    /// (parity <40% means the backend is essentially returning nothing). It
    /// does NOT shout when FM is "just bad" — that's the cutover gate's job.
    func testFoundationModelsChat_parityRegressionFloor() async throws {
        try skipUnlessBothAvailable()
        let report = await runGoldSet()
        print(report.description)

        XCTAssertGreaterThanOrEqual(report.parityRate, 0.40,
            "FM chat parity collapsed below the 40% floor — backend likely returning empty / malformed.\(report.description)")
        XCTAssertGreaterThanOrEqual(report.llamaAccuracy, 0.80,
            "Llama baseline accuracy dropped below 80% — baseline regression, not a parity issue.\(report.description)")
    }

    /// Cutover gate: the ≥95% overall / ≥98% critical parity bar FM must clear
    /// to be (re-)promoted to the default chat backend. Per the #872 NO-GO this
    /// gate MEASURES + emits the parity number on EVERY run (like the regression
    /// floor above — never a silent green-skip), but only BLOCKS while Foundation
    /// Models is the active default. On the reverted llama.cpp/Gemma default it
    /// measures + auto-passes; it re-arms the moment detectTier()/preferredAIBackend
    /// put FM back as the default (#874). The 95/98 thresholds are unchanged.
    func testFoundationModelsChat_parityCutoverGate() async throws {
        try skipUnlessBothAvailable()

        // MEASURE + emit on every run — the parity number is always visible in
        // CI output, exactly like the regression floor. #872 NO-GO: no silent
        // green-skip into dormancy, only the BLOCK below is conditional.
        let report = await runGoldSet()
        print(report.description)

        // BLOCK only while FM is the active default. detectTier() is the
        // device-level default; preferredAIBackend is the user override —
        // either making FM active re-arms the ≥95/≥98 bar.
        let deviceDefault = DeviceCapability.detectTier().backend
        let userDefault = Preferences.preferredAIBackend
        guard deviceDefault == .foundationModels || userDefault == .foundationModels else {
            print("ℹ️ [#872 NO-GO] Foundation Models is not the active default backend "
                + "(detectTier → \(deviceDefault), preferredAIBackend → \(userDefault)); "
                + "parity measured above, cutover block dormant. Re-arms when FM is re-promoted (#874).")
            return
        }

        XCTAssertGreaterThanOrEqual(report.parityRate, 0.95,
            "FM chat backend below 95% parity vs llama.cpp baseline — cannot keep .foundationModels as the default.\(report.description)")
        XCTAssertGreaterThanOrEqual(report.criticalParityRate, 0.98,
            "FM chat backend below 98% parity on critical cases (food log, weight log, multi-turn). These are the highest-stakes routes — failing them is a regression we cannot ship.\(report.description)")
    }

    // MARK: - Gold-set hygiene (always-on, no model)

    /// Sanity-check the gold set itself so a typo can't silently drop a
    /// critical case. Runs without the model, so always-on regardless of
    /// host capability.
    func testFoundationModelsChat_goldSetSanity() {
        XCTAssertGreaterThanOrEqual(Self.goldSet.count, 20, "Parity gold set must have ≥20 cases")
        let critical = Self.goldSet.filter { $0.isCritical }
        XCTAssertGreaterThanOrEqual(critical.count, 5, "Need ≥5 critical-flagged cases (food + weight + multi-turn)")
        let expectedTools = Set(Self.goldSet.map { $0.expectedTool })
        XCTAssertTrue(expectedTools.contains("log_food"), "Critical category log_food must be represented")
        XCTAssertTrue(expectedTools.contains("log_weight"), "Critical category log_weight must be represented")
        XCTAssertGreaterThan(expectedTools.count, 8, "Gold set must cover >8 distinct tools to catch broad regressions")
        // History-bearing cases must remain present — without them the test
        // wouldn't exercise multi-turn routing where FM ↔ llama gaps are
        // most likely (different attention behaviors on short follow-ups).
        let withHistory = Self.goldSet.filter { !$0.history.isEmpty }
        XCTAssertGreaterThanOrEqual(withHistory.count, 10, "Need ≥10 multi-turn cases with non-empty history (epic #860: multi-turn is where FM ↔ Gemma diverge most)")
    }
}
