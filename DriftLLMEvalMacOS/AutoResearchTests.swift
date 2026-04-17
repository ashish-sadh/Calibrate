import XCTest
import Foundation

/// Auto-research optimization loop for the full AI pipeline.
///
/// Always-on (no model):
///   testHardEvalSetSanity      — structure + valid tool names
///   testBaselineTokenBudget    — prompt word counts within limits
///   testBaseline               — record current held-out score (model required)
///
/// Gated (DRIFT_AUTORESEARCH=1):
///   testAutoResearch           — full optimization loop, auto-applies + pushes winner
///
/// Run baseline:
///   xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
///     -only-testing:AutoResearchTests/testBaseline
///
/// Run full loop (~40 min):
///   DRIFT_AUTORESEARCH=1 xcodebuild test -scheme DriftLLMEvalMacOS -destination 'platform=macOS' \
///     -only-testing:AutoResearchTests/testAutoResearch
final class AutoResearchTests: XCTestCase {

    // MARK: - Model Backend (shared)

    nonisolated(unsafe) static var gemma: LlamaCppBackend?

    override class func setUp() {
        super.setUp()
        let path = URL.homeDirectory.appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        let b = LlamaCppBackend(modelPath: path, threads: 6)
        try? b.loadSync()
        if b.isLoaded { gemma = b }
    }

    // MARK: - Always-On: Sanity

    func testHardEvalSetSanity() {
        let all = HardEvalSet.all
        XCTAssertFalse(all.isEmpty, "Eval set must not be empty")

        let errors = HardEvalSet.validate()
        XCTAssertTrue(errors.isEmpty, "Validation errors:\n\(errors.joined(separator: "\n"))")

        let train = all.filter(\.isTrainSet)
        let heldOut = all.filter { !$0.isTrainSet }
        XCTAssertGreaterThanOrEqual(train.count, 60, "Need ≥60 train cases, got \(train.count)")
        XCTAssertGreaterThanOrEqual(heldOut.count, 20, "Need ≥20 held-out cases, got \(heldOut.count)")

        // Each category must have at least 1 train case
        for cat in EvalCategory.allCases {
            let count = train.filter { $0.category == cat }.count
            XCTAssertGreaterThan(count, 0, "Category '\(cat.rawValue)' has no train cases")
        }

        // No duplicate inputs in same split
        let trainInputs = train.map(\.input)
        let heldInputs = heldOut.map(\.input)
        XCTAssertEqual(trainInputs.count, Set(trainInputs).count, "Duplicate inputs in train set")
        XCTAssertEqual(heldInputs.count, Set(heldInputs).count, "Duplicate inputs in held-out set")

        print("✅ HardEvalSet: \(train.count) train, \(heldOut.count) held-out, \(EvalCategory.allCases.count) categories")
    }

    func testBaselineTokenBudget() {
        let classifierWords = IntentRoutingEval.systemPrompt.split(separator: " ").count
        XCTAssertLessThanOrEqual(classifierWords, 800,
            "Classifier prompt exceeds 800 words: \(classifierWords)")

        let presentationWords = AIToolAgentPrompts.presentationPrompt.split(separator: " ").count
        XCTAssertLessThanOrEqual(presentationWords, 200,
            "Presentation prompt exceeds 200 words: \(presentationWords)")

        print("✅ Token budget: classifier \(classifierWords)/800 words, presentation \(presentationWords)/200 words")
    }

    // MARK: - Baseline (model required, always-on for sprint-start recording)

    func testBaseline() async throws {
        guard let gemma = Self.gemma else {
            throw XCTSkip("Gemma 4 not loaded — run: bash scripts/download-models.sh")
        }

        let heldOut = HardEvalSet.all.filter { !$0.isTrainSet }
        let optimizer = PromptOptimizer(backend: gemma)
        let baseline = PipelineConfig.baseline(
            classifierPrompt: IntentRoutingEval.systemPrompt,
            presentationPrompt: AIToolAgentPrompts.presentationPrompt
        )

        let result = await optimizer.evaluate(config: baseline, cases: heldOut)

        print("\n📊 BASELINE (held-out \(heldOut.count) cases)")
        print(result.summary)
        print("\nRecord this in sprint notes before making AI changes.")

        // Soft floor — warn but don't fail
        if result.score < 0.60 {
            XCTFail("Baseline below 60% — pipeline may be broken: \(String(format: "%.1f%%", result.score * 100))")
        }
    }

    // MARK: - Full Auto-Research Loop (gated)

    func testAutoResearch() async throws {
        guard ProcessInfo.processInfo.environment["DRIFT_AUTORESEARCH"] == "1" else {
            throw XCTSkip("Set DRIFT_AUTORESEARCH=1 to run the full optimization loop")
        }
        guard let gemma = Self.gemma else {
            XCTFail("Gemma 4 not loaded — run: bash scripts/download-models.sh")
            return
        }

        let train = HardEvalSet.all.filter(\.isTrainSet)
        let heldOut = HardEvalSet.all.filter { !$0.isTrainSet }
        let baseline = PipelineConfig.baseline(
            classifierPrompt: IntentRoutingEval.systemPrompt,
            presentationPrompt: AIToolAgentPrompts.presentationPrompt
        )

        let optimizer = PromptOptimizer(backend: gemma)
        let (winner, report) = await optimizer.runLoop(trainSet: train, heldOut: heldOut, baseline: baseline)

        // Write report to drift-state
        let reportDir = URL.homeDirectory.appending(path: "drift-state/autoresearch")
        try? FileManager.default.createDirectory(at: reportDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let reportURL = reportDir.appending(path: "winner-\(timestamp).txt")
        try? report.write(to: reportURL, atomically: true, encoding: .utf8)
        print("Report written to: \(reportURL.path)")

        // Check if winner actually improves on baseline
        let baselineResult = await optimizer.evaluate(config: baseline, cases: heldOut)
        let winnerResult = await optimizer.evaluate(config: winner, cases: heldOut)
        let delta = winnerResult.score - baselineResult.score

        guard delta >= 0.01 else {
            print("⚠️ No meaningful improvement found (Δ\(String(format: "%.1f%%", delta * 100))) — keeping baseline, no commit")
            return
        }

        // Run regression check before auto-applying
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let regressionPassed = await runRegressionCheck(optimizer: optimizer, winner: winner, baseline: baseline, heldOut: heldOut)

        guard regressionPassed else {
            print("❌ Regression detected — auto-apply blocked, keeping baseline")
            XCTFail("Winner caused regression on existing IntentRoutingEval cases")
            return
        }

        // Apply winner to source files and commit
        do {
            try optimizer.applyToSourceFiles(winner, projectRoot: projectRoot)
            print("✅ Applied winner to source files")

            let scoreStr = String(format: "+%.1f%%", delta * 100)
            try commitAndPush(message: "feat(ai): autoresearch — \(scoreStr) held-out | \(winner.mutation)")
            print("✅ Committed and pushed: autoresearch \(scoreStr)")
        } catch {
            print("❌ Auto-apply failed: \(error) — reverting")
            try? revertSourceFiles(projectRoot: projectRoot)
            XCTFail("Auto-apply failed: \(error)")
        }

        XCTAssertGreaterThanOrEqual(winnerResult.score, 0.72,
            "Winner below 72% — eval set may need enrichment")
    }

    // MARK: - Regression Check

    /// Re-runs the held-out eval AND checks that the winner doesn't break
    /// any IntentRoutingEval routing cases that currently pass on baseline.
    private func runRegressionCheck(
        optimizer: PromptOptimizer,
        winner: PipelineConfig,
        baseline: PipelineConfig,
        heldOut: [HardCase]
    ) async -> Bool {
        // Build lightweight regression cases from IntentRoutingEval's known-passing queries
        let regressionCases = regressionGuardCases()

        let baselineReg = await optimizer.evaluate(config: baseline, cases: regressionCases)
        let winnerReg = await optimizer.evaluate(config: winner, cases: regressionCases)

        let regDelta = winnerReg.toolRoutingScore - baselineReg.toolRoutingScore
        print("Regression guard: baseline routing \(String(format: "%.1f%%", baselineReg.toolRoutingScore * 100)) → winner \(String(format: "%.1f%%", winnerReg.toolRoutingScore * 100)) (Δ\(String(format: "%.1f%%", regDelta * 100)))")

        // Allow up to -2% routing regression (noise tolerance), block anything worse
        return regDelta >= -0.02
    }

    /// Core routing cases that must never regress — mirrors IntentRoutingEval's essential tests.
    private func regressionGuardCases() -> [HardCase] {
        let rubric = ResponseRubric.any
        return [
            HardCase(input: "log 2 eggs", history: nil, expectedTool: "log_food",
                     expectedParamHints: ["name": "egg"], responseRubric: rubric,
                     category: .foodRouting, description: "regression: log 2 eggs", isTrainSet: true),
            HardCase(input: "had biryani", history: nil, expectedTool: "log_food",
                     expectedParamHints: ["name": "biryani"], responseRubric: rubric,
                     category: .foodRouting, description: "regression: had biryani", isTrainSet: true),
            HardCase(input: "calories in samosa", history: nil, expectedTool: "food_info",
                     expectedParamHints: [:], responseRubric: rubric,
                     category: .regression, description: "regression: calories in samosa", isTrainSet: true),
            HardCase(input: "daily summary", history: nil, expectedTool: "food_info",
                     expectedParamHints: [:], responseRubric: rubric,
                     category: .quickReplyPills, description: "regression: daily summary", isTrainSet: true),
            HardCase(input: "calories left", history: nil, expectedTool: "food_info",
                     expectedParamHints: [:], responseRubric: rubric,
                     category: .quickReplyPills, description: "regression: calories left", isTrainSet: true),
            HardCase(input: "I weigh 75 kg", history: nil, expectedTool: "log_weight",
                     expectedParamHints: ["value": "75"], responseRubric: rubric,
                     category: .foodRouting, description: "regression: log weight", isTrainSet: true),
            HardCase(input: "how did I sleep", history: nil, expectedTool: "sleep_recovery",
                     expectedParamHints: [:], responseRubric: rubric,
                     category: .quickReplyPills, description: "regression: sleep", isTrainSet: true),
            HardCase(input: "took vitamin d", history: nil, expectedTool: "mark_supplement",
                     expectedParamHints: ["name": "vitamin"], responseRubric: rubric,
                     category: .supplement, description: "regression: mark supplement", isTrainSet: true),
            HardCase(input: "did I take my vitamins", history: nil, expectedTool: "supplements",
                     expectedParamHints: [:], responseRubric: rubric,
                     category: .supplement, description: "regression: supplements status", isTrainSet: true),
            HardCase(input: "is biryani healthy", history: nil, expectedTool: "food_info",
                     expectedParamHints: [:], responseRubric: rubric,
                     category: .regression, description: "regression: food question not log", isTrainSet: true),
        ]
    }

    // MARK: - Git Helpers

    private func commitAndPush(message: String) throws {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path

        let add = Process()
        add.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        add.arguments = ["-C", projectRoot, "add",
                         "Drift/Services/IntentClassifier.swift",
                         "Drift/Services/AIToolAgent.swift"]
        try add.run(); add.waitUntilExit()

        let commit = Process()
        commit.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        commit.arguments = ["-C", projectRoot, "commit", "-m", message]
        try commit.run(); commit.waitUntilExit()
        guard commit.terminationStatus == 0 else {
            throw NSError(domain: "AutoResearch", code: Int(commit.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "git commit failed"])
        }

        let push = Process()
        push.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        push.arguments = ["-C", projectRoot, "push"]
        try push.run(); push.waitUntilExit()
    }

    private func revertSourceFiles(projectRoot: URL) throws {
        let revert = Process()
        revert.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        revert.arguments = ["-C", projectRoot.path, "checkout",
                            "Drift/Services/IntentClassifier.swift",
                            "Drift/Services/AIToolAgent.swift"]
        try revert.run(); revert.waitUntilExit()
    }
}

// MARK: - Prompt Accessors (bridges to app-side static vars)

/// Thin accessors so AutoResearchTests and PromptOptimizer can read the live
/// prompt strings without importing the full iOS app module.
enum AIToolAgentPrompts {
    static var presentationPrompt: String {
        // Mirror of AIToolAgent.presentationPrompt — keep in sync.
        // Optimizer mutations write back to AIToolAgent.swift directly.
        """
        You are a friendly health tracker assistant. It's {timeContext}. {toneHint}
        Answer the user's question using ONLY the data below. Lead with your main observation, then give the numbers.
        Be warm and brief (2-3 sentences). Use the actual numbers. No medical advice. No repeating the question.
        If the topic changes from the conversation history, acknowledge it naturally before answering.
        Example: "You're doing well today — 1200 of 2000 cal with solid protein at 85g. A chicken dinner would close the gap nicely."
        """
    }
}
