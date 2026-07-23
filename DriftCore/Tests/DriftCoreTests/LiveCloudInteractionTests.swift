import XCTest
@testable import DriftCore

/// Tier-4 (env-gated): REAL Nebius round-trips for every DriftCore extraction
/// interaction. Skips entirely unless `DRIFT_LIVE_CLOUD=1` — never runs on the
/// commit path. Run via `scripts/live-cloud-check.sh` (or
/// `DRIFT_LIVE_CLOUD=1 swift test --filter LiveCloudInteractionTests`).
///
/// Exists because the workout-scan launch (builds 358-360) shipped three field
/// bugs that unit mocks could never catch — token truncation, sampling
/// nondeterminism, and the buffered-connection cellular kill — all found only
/// by live calls. This suite makes "keep testing the interactions" a repeatable
/// command instead of ad-hoc throwaway harnesses.
///
/// Optional: `DRIFT_LIVE_SCAN_IMAGE=/path/to.jpg` adds a real photo-scan pass
/// (e.g. the operator's notebook page; not committed — personal data).
final class LiveCloudInteractionTests: XCTestCase {

    private func requireLiveGate() throws {
        guard ProcessInfo.processInfo.environment["DRIFT_LIVE_CLOUD"] == "1" else {
            throw XCTSkip("DRIFT_LIVE_CLOUD != 1 — live cloud suite is opt-in")
        }
    }

    /// The coach endpoint answers at all (key decrypts, provider reachable).
    @MainActor
    func testCoachEndpointAnswers() async throws {
        try requireLiveGate()
        XCTAssertTrue(CoachCloud.isConfigured, "team key must decrypt")
        CoachCloud.install()
        let reply = await LocalAIService.shared.respondDirect(
            systemPrompt: "Reply with exactly: ok", message: "ping")
        XCTAssertFalse(reply.isEmpty, "empty reply — err=\(String(describing: LocalAIService.shared.lastRemoteError))")
    }

    /// Exercise TEXT extraction end-to-end: multi-exercise input must come back
    /// as multiple structured entries (the truncation bug would drop the tail).
    @MainActor
    func testExerciseTextParseLive() async throws {
        try requireLiveGate()
        let entries = await NebiusExerciseLogger.parse(
            "bench press 3x10 at 135, squats 5x5 at 225, then 20 minutes cycling")
        XCTAssertNotNil(entries, "err=\(String(describing: LocalAIService.shared.lastRemoteError))")
        XCTAssertGreaterThanOrEqual(entries?.count ?? 0, 3, "all three movements must survive: \(String(describing: entries))")
    }

    /// A LONG many-exercise workout — the exact shape chat's 512-token budget
    /// used to truncate. All eight entries must survive the wire.
    @MainActor
    func testLongWorkoutTextDoesNotTruncate() async throws {
        try requireLiveGate()
        let entries = await NebiusExerciseLogger.parse(
            "incline dumbbell press 3x10 at 45, pushups 3x20, cable flies 3x12 at 30, " +
            "yoga ball pike 3x10, woodchoppers 3x15 at 15, decline crunches 3x15 at 10, " +
            "overhead press 3x8 at 65, romanian deadlift 3x10 at 135")
        XCTAssertGreaterThanOrEqual(entries?.count ?? 0, 8, "long workout truncated: \(String(describing: entries?.count))")
    }

    /// Non-workout text must return nil (anti-hallucination guard holds live).
    @MainActor
    func testNonWorkoutTextReturnsNothing() async throws {
        try requireLiveGate()
        let entries = await NebiusExerciseLogger.parse("what did I eat yesterday?")
        XCTAssertNil(entries, "non-workout text must not fabricate exercises: \(String(describing: entries))")
    }

    /// Restaurant nutrition via the web_search provider ladder. Keys come from
    /// env (DRIFT_LIVE_GOOGLE_KEY + DRIFT_LIVE_GOOGLE_CX, or DRIFT_LIVE_BRAVE_KEY)
    /// so the sweep can exercise a real keyed provider; skips without one —
    /// the keyless DDG rung is too weak to assert nutrition content on.
    @MainActor
    func testRestaurantNutritionWebLookupLive() async throws {
        try requireLiveGate()
        let env = ProcessInfo.processInfo.environment
        let savedGoogle = (Preferences.googleSearchApiKey, Preferences.googleSearchEngineId)
        let savedBrave = Preferences.braveSearchApiKey
        defer {
            Preferences.googleSearchApiKey = savedGoogle.0
            Preferences.googleSearchEngineId = savedGoogle.1
            Preferences.braveSearchApiKey = savedBrave
        }
        if let k = env["DRIFT_LIVE_GOOGLE_KEY"], let cx = env["DRIFT_LIVE_GOOGLE_CX"] {
            Preferences.googleSearchApiKey = k
            Preferences.googleSearchEngineId = cx
        } else if let k = env["DRIFT_LIVE_BRAVE_KEY"] {
            Preferences.braveSearchApiKey = k
        } else {
            throw XCTSkip("no keyed web-search provider in env — set DRIFT_LIVE_GOOGLE_KEY+CX or DRIFT_LIVE_BRAVE_KEY")
        }

        let out = try await WebSearchTool.search(query: "chipotle chicken burrito bowl calories")
        XCTAssertFalse(out.hasPrefix("No web results"), "keyed search must return results: \(out.prefix(200))")
        XCTAssertTrue(out.lowercased().contains("calorie") || out.contains(" cal"),
                      "results should mention calories: \(out.prefix(300))")
    }

    /// Optional real photo scan (DRIFT_LIVE_SCAN_IMAGE=/path/to.jpg).
    @MainActor
    func testWorkoutPhotoScanLive() async throws {
        try requireLiveGate()
        guard let path = ProcessInfo.processInfo.environment["DRIFT_LIVE_SCAN_IMAGE"],
              let data = FileManager.default.contents(atPath: path) else {
            throw XCTSkip("DRIFT_LIVE_SCAN_IMAGE unset — photo pass skipped")
        }
        var stages: [NebiusWorkoutPhotoParser.ScanStage] = []
        let result = await NebiusWorkoutPhotoParser.parse(
            imageData: data, visionModelID: AppConfig.coachVisionModelID,
            onStage: { s in stages.append(s) })
        XCTAssertNotNil(result, "scan failed — err=\(String(describing: LocalAIService.shared.lastRemoteError))")
        XCTAssertFalse(result?.isEmpty ?? true, "workout image must yield a template or session")
        XCTAssertTrue(stages.contains(.reading), "streaming must fire the .reading stage (buffered regression)")
    }
}
