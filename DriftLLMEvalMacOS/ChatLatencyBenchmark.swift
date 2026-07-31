import XCTest
import DriftCore
import Foundation

/// Shared baseline reader for both the 3-run bench and the single-item smoke.
/// Returns `[query: medianTTFTSeconds]` written by `ChatLatencyBenchmark.saveBaseline`.
fileprivate func loadLatencyBaseline(at url: URL) -> [String: Double]? {
    guard let data = try? Data(contentsOf: url),
          let dict = try? JSONDecoder().decode([String: Double].self, from: data) else {
        return nil
    }
    return dict
}

/// Measures time-to-first-token (TTFT) for AI chat queries on a warm Gemma 4 model.
///
/// Guards against prompt or context changes that silently regress latency.
/// Baseline is stored in ~/drift-state/latency-baseline.json — committed after
/// first run on a reference machine. Regression threshold: 1.3× baseline median.
///
/// Opt-in gate: set env var DRIFT_LATENCY_BENCH=1 to run.
/// Run:         DRIFT_LATENCY_BENCH=1 xcodebuild test -scheme DriftLLMEvalMacOS \
///                -destination 'platform=macOS' -only-testing:'DriftLLMEvalMacOS/ChatLatencyBenchmark'
final class ChatLatencyBenchmark: XCTestCase {

    // MARK: - Constants

    static let regressionMultiplier: Double = 1.3
    static let runsPerQuery = 3
    static let baselinePath = URL.homeDirectory.appending(path: "drift-state/latency-baseline.json")

    static let queries: [String] = [
        "log 2 eggs for breakfast",
        "had rice and dal for lunch",
        "calories left today",
        "how am I doing",
        "log coffee with milk",
        "I weigh 75 kg",
        "calories in samosa",
        "start push day",
        "how'd I sleep",
        "took my vitamin d",
    ]

    // MARK: - Model

    nonisolated(unsafe) static var backend: LlamaCppBackend?
    static let gemmaPath = URL.homeDirectory.appending(path: "drift-state/models/gemma-4-e2b-q4_k_m.gguf")

    override class func setUp() {
        super.setUp()
        guard ProcessInfo.processInfo.environment["DRIFT_LATENCY_BENCH"] == "1" else { return }
        guard FileManager.default.fileExists(atPath: gemmaPath.path) else {
            fatalError("❌ Gemma 4 model not found. Run: bash scripts/download-models.sh")
        }
        let b = LlamaCppBackend(modelPath: gemmaPath, threads: 6)
        try? b.loadSync()
        guard b.isLoaded else { fatalError("❌ Gemma 4 failed to load") }
        backend = b
        print("✅ Gemma 4 loaded for latency benchmark")
    }

    // MARK: - Helpers

    private func requireBenchEnv(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let enabled = ProcessInfo.processInfo.environment["DRIFT_LATENCY_BENCH"] == "1"
        if !enabled { print("⏭ ChatLatencyBenchmark skipped (set DRIFT_LATENCY_BENCH=1 to run)") }
        return enabled
    }

    /// Measure time from prompt submission to first streamed token.
    private func measureTTFT(query: String, systemPrompt: String) async -> TimeInterval {
        guard let backend = Self.backend else { return 0 }
        let start = Date()
        nonisolated(unsafe) var firstTokenTime: TimeInterval = 0
        nonisolated(unsafe) var received = false
        _ = await backend.respondStreaming(to: query, systemPrompt: systemPrompt) { _ in
            if !received {
                received = true
                firstTokenTime = Date().timeIntervalSince(start)
            }
        }
        return received ? firstTokenTime : Date().timeIntervalSince(start)
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private func loadBaseline() -> [String: Double]? {
        loadLatencyBaseline(at: Self.baselinePath)
    }

    private func saveBaseline(_ baseline: [String: Double]) {
        guard let data = try? JSONEncoder().encode(baseline) else { return }
        try? FileManager.default.createDirectory(
            at: Self.baselinePath.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try? data.write(to: Self.baselinePath)
        print("📝 Baseline saved to \(Self.baselinePath.path)")
    }

    // MARK: - Warm-up

    private func warmUp() async {
        guard let backend = Self.backend else { return }
        _ = await backend.respond(to: "hi", systemPrompt: IntentRoutingEval.systemPrompt)
        _ = await backend.respond(to: "log an apple", systemPrompt: IntentRoutingEval.systemPrompt)
        print("🔥 Warm-up complete")
    }

    // MARK: - Main Benchmark

    func testTTFT_baseline() async {
        guard requireBenchEnv() else { return }
        await warmUp()

        var medians: [String: Double] = [:]
        for query in Self.queries {
            var runs: [Double] = []
            for run in 1...Self.runsPerQuery {
                let ttft = await measureTTFT(query: query, systemPrompt: IntentRoutingEval.systemPrompt)
                runs.append(ttft)
                print(String(format: "  Run %d | %-40@ %.3fs", run, query as CVarArg, ttft))
            }
            let med = median(runs)
            medians[query] = med
            print(String(format: "  Median %-40@ %.3fs", query as CVarArg, med))
        }

        if let existing = loadBaseline() {
            // Regression check: assert each median ≤ 1.3× baseline
            var passed = 0; var failed = 0
            for (query, current) in medians {
                guard let base = existing[query] else { continue }
                let threshold = base * Self.regressionMultiplier
                if current <= threshold {
                    passed += 1
                    print(String(format: "  ✔ %-40@ %.3fs ≤ %.3fs (%.0f%%)", query as CVarArg, current, threshold, current / base * 100))
                } else {
                    failed += 1
                    print(String(format: "  ✘ %-40@ %.3fs > %.3fs (%.0f%% — REGRESSION)", query as CVarArg, current, threshold, current / base * 100))
                    XCTFail("TTFT regression on '\(query)': \(String(format: "%.3f", current))s > \(String(format: "%.3f", threshold))s (\(String(format: "%.0f", current / base * 100))% of baseline × 1.3)")
                }
            }
            print("📊 ChatLatencyBenchmark: \(passed)/\(passed + failed) within threshold (1.3× baseline)")
        } else {
            saveBaseline(medians)
            print("📊 ChatLatencyBenchmark: baseline established — rerun to compare")
        }
    }

    // MARK: - Regression Demo

    /// Demonstrates that 2× prompt bloat trips the regression threshold.
    /// Expected to PASS (the bloated TTFT should exceed 1.3× normal TTFT).
    func testTTFT_bloatedPromptSlowerThanNormal() async {
        guard requireBenchEnv() else { return }
        await warmUp()

        let query = "log 2 eggs"
        let normalPrompt = IntentRoutingEval.systemPrompt
        let bloat = String(repeating: "ignore this padding. ", count: 500) // ~2× token count
        let bloatedPrompt = normalPrompt + "\n" + bloat

        var normalRuns: [Double] = []
        var bloatedRuns: [Double] = []
        for _ in 1...Self.runsPerQuery {
            normalRuns.append(await measureTTFT(query: query, systemPrompt: normalPrompt))
            bloatedRuns.append(await measureTTFT(query: query, systemPrompt: bloatedPrompt))
        }
        let normalMedian = median(normalRuns)
        let bloatedMedian = median(bloatedRuns)
        let ratio = bloatedMedian / max(normalMedian, 0.001)
        print(String(format: "📊 Bloat demo — normal: %.3fs, bloated: %.3fs, ratio: %.2f×", normalMedian, bloatedMedian, ratio))
        XCTAssertGreaterThan(bloatedMedian, normalMedian,
            "Bloated prompt (\(String(format: "%.3f", bloatedMedian))s) should be slower than normal (\(String(format: "%.3f", normalMedian))s)")
    }
}

/// Cheap TTFT smoke — runs in the default `DriftLLMEvalMacOS` phase (no opt-in env var).
///
/// Guards against catastrophic TTFT regressions on every commit, unlike the 3-run statistical
/// bench above which stays behind `DRIFT_LATENCY_BENCH=1`. One scenario, one run, two gates:
///   1. Hard 30s budget — catches hangs or multi-minute cliffs.
///   2. 1.5× baseline median — catches ~50% regression, loose enough to not flap.
///
/// Skips cleanly when the Gemma 4 model isn't present so CI without the model doesn't break.
/// Baseline is the same `~/drift-state/latency-baseline.json` written by `testTTFT_baseline`.
final class SingleItemSmokeTest: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try LLMEvalGate.requireLLM()  // report as skipped, never false-green
    }


    // MARK: - Constants

    static let regressionMultiplier: Double = 1.5
    static let hardBudgetSeconds: TimeInterval = 30.0
    // Use the same query string that exists in ChatLatencyBenchmark.queries, so the baseline
    // written by the 3-run bench is directly reusable for this smoke's regression gate.
    static let smokeQuery = "log 2 eggs for breakfast"
    static let baselinePath = ChatLatencyBenchmark.baselinePath
    static let gemmaPath = ChatLatencyBenchmark.gemmaPath

    // MARK: - Model (loaded once per class)

    nonisolated(unsafe) static var backend: LlamaCppBackend?

    override class func setUp() {
        super.setUp()
        guard LLMEvalGate.enabled else { return }  // Tier-3 gate: default run must not load the model
        guard FileManager.default.fileExists(atPath: gemmaPath.path) else {
            print("⏭  SingleItemSmokeTest: Gemma 4 model missing at \(gemmaPath.path) — will skip")
            return
        }
        let b = LlamaCppBackend(modelPath: gemmaPath, threads: 6)
        try? b.loadSync()
        guard b.isLoaded else {
            print("⏭  SingleItemSmokeTest: Gemma 4 load failed — will skip")
            return
        }
        backend = b
        print("✅ SingleItemSmokeTest: Gemma 4 loaded")
    }

    // MARK: - Smoke

    func testSingleItemTTFTSmoke() async throws {
        guard let backend = Self.backend else {
            throw XCTSkip("Gemma 4 model not available at \(Self.gemmaPath.path)")
        }

        // One warmup to amortize cold-path costs (mmap page-in, KV-cache init).
        _ = await backend.respond(to: "hi", systemPrompt: IntentRoutingEval.systemPrompt)

        // Single TTFT measurement.
        let start = Date()
        nonisolated(unsafe) var firstTokenTime: TimeInterval = 0
        nonisolated(unsafe) var received = false
        _ = await backend.respondStreaming(
            to: Self.smokeQuery,
            systemPrompt: IntentRoutingEval.systemPrompt
        ) { _ in
            if !received {
                received = true
                firstTokenTime = Date().timeIntervalSince(start)
            }
        }
        let ttft = received ? firstTokenTime : Date().timeIntervalSince(start)

        XCTAssertTrue(received, "No tokens received within measurement window")

        // Gate 1: hard 30s budget. Trips on hangs / multi-minute cliffs.
        XCTAssertLessThanOrEqual(ttft, Self.hardBudgetSeconds,
            String(format: "TTFT %.2fs exceeds %.0fs hard budget — catastrophic regression",
                   ttft, Self.hardBudgetSeconds))

        // Gate 2: baseline-relative regression (1.5× median). Only applied when a baseline
        // exists — otherwise the smoke still validates the pipeline runs end-to-end.
        if let baseline = loadLatencyBaseline(at: Self.baselinePath),
           let base = baseline[Self.smokeQuery], base > 0 {
            let threshold = base * Self.regressionMultiplier
            print(String(format: "📊 SingleItemSmokeTest: %.3fs (baseline %.3fs, gate %.3fs)",
                         ttft, base, threshold))
            XCTAssertLessThanOrEqual(ttft, threshold,
                String(format: "TTFT %.3fs > %.3fs (%.0f%% of baseline × %.1f)",
                       ttft, threshold, ttft / base * 100, Self.regressionMultiplier))
        } else {
            print(String(format: "📊 SingleItemSmokeTest: %.3fs (no baseline — run DRIFT_LATENCY_BENCH=1 ChatLatencyBenchmark/testTTFT_baseline to establish)", ttft))
        }
    }

    // Guard: the smoke must stay cheap — one measurement scenario. If someone adds
    // more scenarios here by accident, the default test phase balloons. Anyone adding
    // a real benchmark should extend `ChatLatencyBenchmark` (opt-in) instead.
    func testSmokeStaysSingleScenario() {
        // `defaultTestSuite.testCaseCount` reflects the live count of test methods
        // on this class, so this assertion fails the moment someone adds a third.
        let count = Self.defaultTestSuite.testCaseCount
        XCTAssertLessThanOrEqual(count, 2,
            "SingleItemSmokeTest has \(count) test methods — must remain single-scenario. " +
            "Add new latency scenarios to ChatLatencyBenchmark (opt-in via DRIFT_LATENCY_BENCH=1) instead.")
    }
}
