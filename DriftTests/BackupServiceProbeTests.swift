import XCTest
@testable import Drift
@testable import DriftCore

/// Covers the `probeContainerURL()` + `containerURL()` caching pair added
/// 2026-05-20 to fix the misfiring "iCloud Drive is off" alert on devices
/// with iCloud Drive on (#7 from the UI review). The bug was a main-thread
/// call to `FileManager.url(forUbiquityContainerIdentifier:)` early in
/// launch that returned nil while the iCloud daemon was still initializing.
/// The fix is a background-thread probe that caches the result.
@MainActor
final class BackupServiceProbeTests: XCTestCase {

    private func makeService(provider: @escaping () -> URL?) -> BackupService {
        BackupService(
            containerURLProvider: provider,
            database: { AppDatabase.shared },
            userDefaults: UserDefaults(suiteName: "drift.test.\(UUID().uuidString)")!,
            bundle: .main,
            now: { Date() }
        )
    }

    func testProbeCachesContainerURL() async throws {
        let expected = URL(fileURLWithPath: "/tmp/drift-test-icloud")
        let service = makeService(provider: { expected })

        await service.probeContainerURL()
        let resolved = try service.containerURL()
        XCTAssertEqual(resolved, expected)
    }

    func testContainerURLFallsBackToSyncWhenProbeNotCalled() throws {
        let expected = URL(fileURLWithPath: "/tmp/drift-test-icloud-sync")
        let service = makeService(provider: { expected })

        // Skip probeContainerURL() entirely to mimic a caller that goes
        // straight to containerURL(). Sync fallback should still hit the
        // provider and backfill the cache.
        let resolved = try service.containerURL()
        XCTAssertEqual(resolved, expected)
    }

    func testThrowsWhenProviderReturnsNil() async {
        let service = makeService(provider: { nil })
        await service.probeContainerURL()
        XCTAssertThrowsError(try service.containerURL()) { err in
            XCTAssertEqual(err as? BackupError, .iCloudUnavailable)
        }
    }

    func testProbeIsIdempotent() async throws {
        var callCount = 0
        let expected = URL(fileURLWithPath: "/tmp/drift-test-icloud-idem")
        let service = makeService(provider: {
            callCount += 1
            return expected
        })

        await service.probeContainerURL()
        await service.probeContainerURL()
        await service.probeContainerURL()

        // First probe hits the provider once; the cached path takes over.
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(try service.containerURL(), expected)
    }

    func testCachedURLSurvivesProviderChange() async throws {
        // Once cached, subsequent sync containerURL() calls don't re-probe
        // — this is the whole point. Simulates the daemon coming online
        // mid-session: the value at probe time is what we use.
        var current: URL? = URL(fileURLWithPath: "/tmp/drift-test-first")
        let service = makeService(provider: { current })

        await service.probeContainerURL()
        XCTAssertEqual(try service.containerURL(), URL(fileURLWithPath: "/tmp/drift-test-first"))

        current = URL(fileURLWithPath: "/tmp/drift-test-second")
        // Cache wins.
        XCTAssertEqual(try service.containerURL(), URL(fileURLWithPath: "/tmp/drift-test-first"))
    }
}
