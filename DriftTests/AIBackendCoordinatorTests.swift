import XCTest
@testable import Drift
@testable import DriftCore

/// #889 — invariant: when the Nebius cloud coach is configured, Drift must never
/// keep a local Gemma model resident on the cloud path. The launch path already
/// gates correctly (AIChatView installs the cloud backend and skips `loadModel`
/// when `AIBackendCoordinator.hasCoachCloud`); the gap these tests pin down is the
/// MID-SESSION race — a ~2.9GB local load kicked off on the detached task that
/// only finishes AFTER the user flipped to cloud. The completion must discard the
/// stale model, not clobber the live cloud backend.
@MainActor
final class AIBackendCoordinatorTests: XCTestCase {

    override func tearDown() {
        // These tests install a remote / FM backend on the shared singleton. Drop it
        // so it doesn't leak into other DriftTests that read `LocalAIService.shared`.
        let svc = LocalAIService.shared
        svc.clearRemoteBackend()
        svc.clearFoundationModelsBackend()
        super.tearDown()
    }

    /// A local backend stand-in for the detached llama that "just finished loading".
    /// Records whether it was unloaded so the test can prove the stale model was
    /// freed rather than pinned in memory.
    private final class StaleLocalBackendMock: AIBackend, @unchecked Sendable {
        private(set) var didUnload = false
        var isLoaded = true
        var supportsVision = false
        func load() async throws {}
        func respond(to prompt: String, systemPrompt: String) async -> String { "" }
        func respondStreaming(to prompt: String, systemPrompt: String, onToken: @escaping @Sendable (String) -> Void) async -> String { "" }
        func unload() { didUnload = true }
    }

    /// Done-When criterion 1 (the core invariant): cloud configured ⇒ zero local
    /// Gemma load, INCLUDING after a mid-session config flip. We install the Nebius
    /// remote backend (what `installCoachBackend` does), then deliver a local model
    /// load that completed mid-session — the exact moment `loadModel()`'s detached
    /// task lands on the MainActor after the user already flipped to cloud. The
    /// cloud backend must survive and the stale local model must be unloaded.
    func testCloudConfigured_neverLoadsLocalModel_evenAfterMidSessionFlip() {
        let svc = LocalAIService.shared

        // Cloud is the active backend (the launch / installCoachBackend state).
        svc.useRemoteBackend(provider: .nebius, modelID: "Qwen/Qwen3-235B-A22B-Instruct-2507", apiKey: "test-key")
        XCTAssertEqual(svc.activeBackendType, .remote)
        XCTAssertNotNil(svc.remoteProviderName, "precondition: remote backend installed")

        // The detached local load (started before the flip) now completes and tries
        // to claim the backend slot. This is the race the unload-hook must defend.
        let staleLocal = StaleLocalBackendMock()
        svc.adoptLoadedLocalBackend(staleLocal)

        // Invariant: cloud path stays cloud, and the 2.9GB local model is freed.
        XCTAssertEqual(svc.activeBackendType, .remote, "cloud backend must remain active after the mid-session race")
        XCTAssertNotNil(svc.remoteProviderName, "the live cloud backend must NOT be clobbered by the stale local load")
        XCTAssertTrue(staleLocal.didUnload, "the stale local model must be unloaded — never left resident on the cloud path")
    }

    /// Done-When criterion 1 (mid-session flip — Foundation Models variant): the
    /// same no-clobber invariant must hold when the user flipped to Apple Foundation
    /// Models mid-load. A late local load must not clobber the FM backend, and the
    /// stale model must be unloaded. Locks the `adoptLoadedLocalBackend` comment's
    /// "or Foundation Models" claim.
    func testFoundationModelsConfigured_neverAdoptsStaleLocalModel() {
        let svc = LocalAIService.shared

        svc.useFoundationModelsBackend()
        XCTAssertEqual(svc.activeBackendType, .foundationModels)

        let staleLocal = StaleLocalBackendMock()
        svc.adoptLoadedLocalBackend(staleLocal)

        XCTAssertEqual(svc.activeBackendType, .foundationModels, "FM backend must remain active after the mid-session race")
        XCTAssertTrue(staleLocal.didUnload, "the stale local model must be unloaded, not adopted over the FM backend")
    }

    /// Done-When criterion 1 (launch / install gate): installing the cloud coach
    /// backend installs a remote backend, not a local one — no local model is made
    /// the active backend. (AIChatView calls `installCoachBackend` when the team key
    /// is configured and deliberately skips `loadModel`.)
    func testInstallCoachBackend_installsRemoteNotLocal() throws {
        guard AIBackendCoordinator.hasCoachCloud else {
            throw XCTSkip("No coach cloud team key in this build — installCoachBackend path not exercisable")
        }
        let svc = LocalAIService.shared

        XCTAssertTrue(AIBackendCoordinator.installCoachBackend(), "coach cloud is configured, so install must succeed")

        XCTAssertEqual(svc.activeBackendType, .remote, "coach cloud path must install the REMOTE backend")
        XCTAssertNotNil(svc.remoteProviderName, "active backend must be the cloud provider, not a local model")
    }
}
