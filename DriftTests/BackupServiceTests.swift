import XCTest
@testable import DriftCore
@testable import Drift

final class BackupServiceTests: XCTestCase {

    private var tempContainer: URL!
    private var defaultsSuite: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempContainer = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempContainer, withIntermediateDirectories: true)

        let suiteName = "BackupServiceTests-\(UUID().uuidString)"
        defaultsSuite = UserDefaults(suiteName: suiteName)
        defaultsSuite.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let tempContainer {
            try? FileManager.default.removeItem(at: tempContainer)
        }
        defaultsSuite = nil
        try super.tearDownWithError()
    }

    // MARK: - containerURL()

    func testContainerURLThrowsWhenProviderReturnsNil() {
        let service = makeService(containerURLProvider: { nil })
        XCTAssertThrowsError(try service.containerURL()) { error in
            XCTAssertEqual(error as? BackupError, .iCloudUnavailable)
        }
    }

    func testContainerURLReturnsProvidedURL() throws {
        let service = makeService()
        let url = try service.containerURL()
        XCTAssertEqual(url, tempContainer)
    }

    // MARK: - performBackup()

    func testPerformBackupWritesFileMatchingNamingPattern() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_762_412_412) // arbitrary
        let service = makeService(now: { fixedDate })

        let url = try await service.performBackup()

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, BackupKeys.backupFileExtension)
        XCTAssertTrue(
            url.lastPathComponent.hasPrefix("drift-backup-"),
            "Filename should start with drift-backup-: \(url.lastPathComponent)"
        )
        XCTAssertEqual(url.lastPathComponent, BackupPackager.filename(for: fixedDate))
    }

    func testPerformBackupWritesIntoBackupsSubdirectory() async throws {
        let service = makeService()
        let url = try await service.performBackup()
        XCTAssertEqual(
            url.deletingLastPathComponent().lastPathComponent,
            BackupService.backupsSubdirectory
        )
    }

    // MARK: - availableBackups()

    func testAvailableBackupsReturnsParsedManifestsNewestFirst() async throws {
        // Three packaged backups at known timestamps. Use real packager so the
        // backups are byte-valid; tests asserting against a mocked manifest
        // diverge from the production unzip path the moment manifest schema
        // changes (#700 was exactly that).
        let oldest = Date(timeIntervalSince1970: 1_762_000_000)
        let middle = Date(timeIntervalSince1970: 1_762_300_000)
        let newest = Date(timeIntervalSince1970: 1_762_600_000)

        for date in [oldest, middle, newest] {
            let svc = makeService(now: { date })
            _ = try await svc.performBackup()
        }

        let listing = makeService().availableBackups()
        XCTAssertEqual(listing.count, 3)
        XCTAssertEqual(listing.map(\.timestamp), [newest, middle, oldest])
    }

    func testAvailableBackupsReturnsEmptyWhenContainerUnavailable() {
        let service = makeService(containerURLProvider: { nil })
        XCTAssertEqual(service.availableBackups(), [])
    }

    func testAvailableBackupsSkipsUnreadableFiles() async throws {
        let service = makeService()
        _ = try await service.performBackup()

        // Plant a bogus .driftbackup that isn't a real zip — listing must
        // skip it gracefully rather than throwing.
        let backupsDir = try service.backupsDirectory()
        let bogus = backupsDir.appendingPathComponent(
            "drift-backup-1900-01-01T000000.driftbackup"
        )
        try Data("not a zip".utf8).write(to: bogus)

        let listing = service.availableBackups()
        XCTAssertEqual(listing.count, 1)
        XCTAssertFalse(listing.contains(where: { $0.url == bogus }))
    }

    // MARK: - Ring buffer integration

    func testPerformBackupPrunesRingBufferToElevenWhenOverflowed() async throws {
        // Pre-seed 12 weekly-spaced backups directly via the packager so the
        // ring-buffer prune only fires on the performBackup() under test. If
        // we drove setup through performBackup(), each call would itself
        // prune and the precondition would never reach 12.
        let calendar = Calendar(identifier: .iso8601)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let backupsDir = try makeService().backupsDirectory()
        let packager = BackupPackager()
        let db = try AppDatabase.empty()
        let meta = BackupPackager.AppMetadata(
            appBuild: "1",
            appVersion: "0.1.0",
            schemaVersion: Migrations.currentVersion
        )

        for weeksAgo in (1...12).reversed() {
            guard let date = calendar.date(
                byAdding: .day,
                value: -weeksAgo * 7,
                to: baseDate
            ) else { continue }
            let destination = backupsDir
                .appendingPathComponent(BackupPackager.filename(for: date))
            _ = try packager.package(
                dbWriter: db.writer,
                userDefaults: defaultsSuite,
                appMetadata: meta,
                timestamp: date,
                destination: destination
            )
        }

        XCTAssertEqual(
            makeService().availableBackups().count, 12,
            "Setup precondition"
        )

        let service = makeService(now: { baseDate })
        _ = try await service.performBackup()

        let remaining = service.availableBackups()
        XCTAssertEqual(
            remaining.count, 11,
            "Ring buffer should keep at most 7 daily + 4 weekly = 11 backups"
        )
    }

    // MARK: - Upload monitor

    func testPerformBackupClearsStaleErrorOnLocalWriteSuccess() async throws {
        // Stale failure from a prior attempt sits in UserDefaults. The next
        // successful local write must clear it so Settings → Backup doesn't
        // show a red error label next to the green "uploading…" confirmation
        // while we wait for `recordUploadSuccess` to fire from iCloud's
        // metadata query.
        defaultsSuite.set("previous failure", forKey: BackupService.lastBackupErrorKey)

        let service = makeService()
        _ = try await service.performBackup()

        XCTAssertNil(defaultsSuite.string(forKey: BackupService.lastBackupErrorKey))
        XCTAssertNil(service.lastBackupError)
    }

    func testRecordUploadSuccessPersistsTimestampAndClearsError() {
        let service = makeService()
        defaultsSuite.set("previous failure", forKey: BackupService.lastBackupErrorKey)

        let observed = Date(timeIntervalSince1970: 1_762_700_000)
        service.recordUploadSuccess(date: observed)

        XCTAssertEqual(
            defaultsSuite.object(forKey: BackupService.lastSuccessfulBackupDateKey) as? Date,
            observed
        )
        XCTAssertNil(defaultsSuite.string(forKey: BackupService.lastBackupErrorKey))
        XCTAssertEqual(service.lastSuccessfulBackupDate, observed)
        XCTAssertNil(service.lastBackupError)
    }

    // MARK: - Helpers

    private func makeService(
        containerURLProvider: (() -> URL?)? = nil,
        now: @escaping () -> Date = { Date() }
    ) -> BackupService {
        let provider = containerURLProvider ?? { [tempContainer] in tempContainer }
        // Tests don't rely on cross-call DB state — only on the packaging
        // path producing a byte-valid .driftbackup. A fresh in-memory DB per
        // call is fine.
        let db: () -> AppDatabase = { try! AppDatabase.empty() }
        return BackupService(
            containerURLProvider: provider,
            database: db,
            userDefaults: defaultsSuite,
            bundle: .main,
            now: now
        )
    }
}
