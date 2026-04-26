import XCTest
@testable import DriftCore

private final class FirstTokenCapture: @unchecked Sendable {
    private(set) var ttft_ms: Double? = nil
    private let start: DispatchTime

    init(start: DispatchTime) { self.start = start }

    func recordIfFirst() {
        guard ttft_ms == nil else { return }
        let ns = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        ttft_ms = Double(ns) / 1_000_000
    }
}

/// Latency benchmark for the AI streaming chat pipeline — TTFT and full completion time.
/// Opt-in only: set DRIFT_LATENCY_BENCH=1. Does not run in normal CI.
///
/// Run:
///   DRIFT_LATENCY_BENCH=1 xcodebuild test \
///     -project Drift.xcodeproj -scheme Drift \
///     -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
///     -only-testing:'DriftTests/ChatLatencyBenchmark'
///
/// Re-baseline after an intentional pipeline change:
///   DRIFT_LATENCY_BENCH=1 DRIFT_REBASELINE=1 xcodebuild test \
///     -only-testing:'DriftTests/ChatLatencyBenchmark'
///   # Then copy /tmp/latency-baseline.json → DriftTests/Fixtures/latency-baseline.json
final class ChatLatencyBenchmark: XCTestCase {

    // MARK: - Types

    private struct QuerySpec: Decodable {
        let id: String
        let query: String
    }

    private struct ClarifySpec: Decodable {
        let id: String
        let query: String
        let followup: String
    }

    private struct QuerySet: Decodable {
        let single_item: [QuerySpec]
        let multi_item: [QuerySpec]
        let confirmation_card: [QuerySpec]
        let clarify_round_trip: [ClarifySpec]
    }

    private struct ClarifyMeasurement {
        let turn1_ms: Double
        let turn2_ms: Double
        var total_ms: Double { turn1_ms + turn2_ms }
    }

    private struct BaselineEntry: Codable {
        var ttft_ms: Double
        var completion_ms: Double
    }

    private struct Baseline: Codable {
        var recorded_at: String
        var model_tag: String
        var gate_multiplier: Double
        var measurements: [String: BaselineEntry]
    }

    private struct Measurement {
        let ttft_ms: Double
        let completion_ms: Double
    }

    // MARK: - Class-level model (loaded once per test class)

    nonisolated(unsafe) static var backend: LlamaCppBackend?
    nonisolated(unsafe) static var modelTag = ""
    private static let modelPath = "/tmp/smollm2-360m-instruct-q8_0.gguf"

    override class func setUp() {
        super.setUp()
        guard isEnabled else { return }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            print("⚠️  ChatLatencyBenchmark: model not found at \(modelPath)")
            return
        }
        let b = LlamaCppBackend(modelPath: URL(fileURLWithPath: modelPath))
        try? b.loadSync()
        if b.isLoaded {
            backend = b
            modelTag = "smollm2-360m"
            print("✅ ChatLatencyBenchmark: loaded \(modelTag)")
        }
    }

    // MARK: - Env guards

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["DRIFT_LATENCY_BENCH"] == "1"
    }

    private var isRebaseline: Bool {
        ProcessInfo.processInfo.environment["DRIFT_REBASELINE"] == "1"
    }

    // MARK: - Tests

    func testMultiItemFoodLogLatency() async throws {
        guard Self.isEnabled else { throw XCTSkip("Set DRIFT_LATENCY_BENCH=1 to run") }
        guard let _ = Self.backend else {
            throw XCTSkip("Model not found at \(Self.modelPath)")
        }

        let querySet = try loadQueries()
        let baseline = loadBaseline()

        print("\n=== ChatLatencyBenchmark: multi-item food-log (3 runs, median) ===")
        let header = String(format: "%-40s %9s %9s  %@", "Query ID", "TTFT ms", "Done ms", "Status")
        print(header)
        print(String(repeating: "-", count: 75))

        var allPassed = true
        var newBaseline: [String: BaselineEntry] = [:]

        for spec in querySet.multi_item {
            let m = await measureStreaming(query: spec.query)
            newBaseline[spec.id] = BaselineEntry(ttft_ms: m.ttft_ms, completion_ms: m.completion_ms)

            let status: String
            if let bl = baseline?.measurements[spec.id], bl.ttft_ms > 0 {
                let limit = bl.ttft_ms * (baseline?.gate_multiplier ?? 1.3)
                if m.ttft_ms > limit {
                    status = "❌ TTFT \(Int(m.ttft_ms))ms > gate \(Int(limit))ms"
                    allPassed = false
                } else {
                    status = "✔"
                }
            } else {
                status = "(no baseline)"
            }

            print(String(format: "%-40s %9.1f %9.1f  %@",
                         spec.id, m.ttft_ms, m.completion_ms, status))
        }
        print("")

        if isRebaseline {
            writeBaseline(newBaseline)
            print("Baseline written to /tmp/latency-baseline.json")
            print("Copy it to DriftTests/Fixtures/latency-baseline.json and commit.")
        } else {
            XCTAssertTrue(allPassed, "One or more queries exceeded 1.3× baseline TTFT. See output above.")
        }
    }

    func testSingleItemFoodLogLatency() async throws {
        guard Self.isEnabled else { throw XCTSkip("Set DRIFT_LATENCY_BENCH=1 to run") }
        guard let _ = Self.backend else {
            throw XCTSkip("Model not found at \(Self.modelPath)")
        }

        let querySet = try loadQueries()

        print("\n=== ChatLatencyBenchmark: single-item food-log (3 runs, median) ===")
        print(String(format: "%-40s %9s %9s", "Query ID", "TTFT ms", "Done ms"))
        print(String(repeating: "-", count: 62))

        for spec in querySet.single_item {
            let m = await measureStreaming(query: spec.query)
            print(String(format: "%-40s %9.1f %9.1f", spec.id, m.ttft_ms, m.completion_ms))
        }
        print("")
    }

    /// Measures LLM completion time for clear log queries.
    /// Card renders ~1 frame (16ms) after completion, so completion_ms is the binding latency.
    func testConfirmationCardLatency() async throws {
        guard Self.isEnabled else { throw XCTSkip("Set DRIFT_LATENCY_BENCH=1 to run") }
        guard let _ = Self.backend else {
            throw XCTSkip("Model not found at \(Self.modelPath)")
        }

        let querySet = try loadQueries()
        let baseline = loadBaseline()

        print("\n=== ChatLatencyBenchmark: confirmation-card render (3 runs, median) ===")
        let header = String(format: "%-40s %9s %9s  %@", "Query ID", "TTFT ms", "Done ms", "Status")
        print(header)
        print(String(repeating: "-", count: 75))

        var allPassed = true
        var newBaseline: [String: BaselineEntry] = [:]

        for spec in querySet.confirmation_card {
            let m = await measureStreaming(query: spec.query)
            newBaseline[spec.id] = BaselineEntry(ttft_ms: m.ttft_ms, completion_ms: m.completion_ms)

            let status: String
            if let bl = baseline?.measurements[spec.id], bl.completion_ms > 0 {
                let limit = bl.completion_ms * (baseline?.gate_multiplier ?? 1.3)
                if m.completion_ms > limit {
                    status = "❌ Done \(Int(m.completion_ms))ms > gate \(Int(limit))ms"
                    allPassed = false
                } else {
                    status = "✔"
                }
            } else {
                status = "(no baseline)"
            }

            print(String(format: "%-40s %9.1f %9.1f  %@",
                         spec.id, m.ttft_ms, m.completion_ms, status))
        }
        print("")

        if isRebaseline {
            writeBaseline(newBaseline)
            print("Baseline written to /tmp/latency-baseline.json")
            print("Copy it to DriftTests/Fixtures/latency-baseline.json and commit.")
        } else {
            XCTAssertTrue(allPassed, "One or more card queries exceeded 1.3× baseline completion. See output above.")
        }
    }

    /// Measures full round-trip: ambiguous query (turn 1) + clarify follow-up (turn 2).
    /// Simulates user tapping a clarify chip. Gate is on total_ms (turn1 + turn2).
    func testClarifyRoundTripLatency() async throws {
        guard Self.isEnabled else { throw XCTSkip("Set DRIFT_LATENCY_BENCH=1 to run") }
        guard let _ = Self.backend else {
            throw XCTSkip("Model not found at \(Self.modelPath)")
        }

        let querySet = try loadQueries()
        let baseline = loadBaseline()

        print("\n=== ChatLatencyBenchmark: clarify round-trip (3 runs, median) ===")
        let header = String(format: "%-40s %9s %9s %9s  %@", "Query ID", "Turn1 ms", "Turn2 ms", "Total ms", "Status")
        print(header)
        print(String(repeating: "-", count: 85))

        var allPassed = true
        var newBaseline: [String: BaselineEntry] = [:]

        for spec in querySet.clarify_round_trip {
            let m = await measureClarifyRoundTrip(spec: spec)
            // Store total in completion_ms; ttft not meaningful for round-trip
            newBaseline[spec.id] = BaselineEntry(ttft_ms: 0, completion_ms: m.total_ms)

            let status: String
            if let bl = baseline?.measurements[spec.id], bl.completion_ms > 0 {
                let limit = bl.completion_ms * (baseline?.gate_multiplier ?? 1.3)
                if m.total_ms > limit {
                    status = "❌ Total \(Int(m.total_ms))ms > gate \(Int(limit))ms"
                    allPassed = false
                } else {
                    status = "✔"
                }
            } else {
                status = "(no baseline)"
            }

            print(String(format: "%-40s %9.1f %9.1f %9.1f  %@",
                         spec.id, m.turn1_ms, m.turn2_ms, m.total_ms, status))
        }
        print("")

        if isRebaseline {
            writeBaseline(newBaseline)
            print("Baseline written to /tmp/latency-baseline.json")
            print("Copy it to DriftTests/Fixtures/latency-baseline.json and commit.")
        } else {
            XCTAssertTrue(allPassed, "One or more clarify round-trips exceeded 1.3× baseline total. See output above.")
        }
    }

    // MARK: - Measurement

    private static let benchSystemPrompt = """
    You help track food, weight, and workouts. \
    LOGGING (user ate/did something) → call log tool. \
    QUESTION (user asks about data) → call info tool. \
    Examples: "I had 2 eggs" → {"tool":"log_food","params":{"name":"eggs","amount":"2"}} \
    "chicken rice and broccoli" → log each item separately.
    """

    private func measureStreaming(query: String, runs: Int = 3) async -> Measurement {
        guard let backend = Self.backend else {
            return Measurement(ttft_ms: 0, completion_ms: 0)
        }

        var ttfts: [Double] = []
        var completions: [Double] = []

        for _ in 0..<runs {
            let start = DispatchTime.now()
            let capture = FirstTokenCapture(start: start)

            _ = await backend.respondStreaming(
                to: query,
                systemPrompt: Self.benchSystemPrompt
            ) { _ in capture.recordIfFirst() }

            let doneNS = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
            completions.append(Double(doneNS) / 1_000_000)
            if let t = capture.ttft_ms { ttfts.append(t) }
        }

        return Measurement(
            ttft_ms: ttfts.isEmpty ? 0 : median(ttfts),
            completion_ms: median(completions)
        )
    }

    private func measureClarifyRoundTrip(spec: ClarifySpec, runs: Int = 3) async -> ClarifyMeasurement {
        var turn1s: [Double] = []
        var turn2s: [Double] = []

        for _ in 0..<runs {
            let m1 = await measureStreaming(query: spec.query, runs: 1)
            let m2 = await measureStreaming(query: spec.followup, runs: 1)
            turn1s.append(m1.completion_ms)
            turn2s.append(m2.completion_ms)
        }

        return ClarifyMeasurement(turn1_ms: median(turn1s), turn2_ms: median(turn2s))
    }

    private func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - Fixture loading

    private func loadQueries() throws -> QuerySet {
        let data = try fixtureData(name: "latency-queries", ext: "json")
        return try JSONDecoder().decode(QuerySet.self, from: data)
    }

    private func loadBaseline() -> Baseline? {
        guard let data = try? fixtureData(name: "latency-baseline", ext: "json") else { return nil }
        return try? JSONDecoder().decode(Baseline.self, from: data)
    }

    private func fixtureData(name: String, ext: String) throws -> Data {
        if let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: ext) {
            return try Data(contentsOf: url)
        }
        let srcRelative = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).\(ext)")
        return try Data(contentsOf: srcRelative)
    }

    // MARK: - Baseline write

    private func writeBaseline(_ measurements: [String: BaselineEntry]) {
        let baseline = Baseline(
            recorded_at: ISO8601DateFormatter().string(from: Date()),
            model_tag: Self.modelTag,
            gate_multiplier: 1.3,
            measurements: measurements
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(baseline) else { return }
        let dest = URL(fileURLWithPath: "/tmp/latency-baseline.json")
        do {
            try data.write(to: dest)
        } catch {
            print("❌ ChatLatencyBenchmark: failed to write baseline: \(error)")
        }
    }
}
