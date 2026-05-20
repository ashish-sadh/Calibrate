import Foundation
import DriftCore

/// iOS-side iCloud backup orchestrator. Owns ubiquity-container access, packages
/// snapshots via DriftCore's `BackupPackager`, prunes via `BackupRingBuffer`,
/// monitors uploads via `NSMetadataQuery`, and routes restores into
/// `BackupRestorer`. Pure orchestration — all packaging / restoring logic lives
/// in DriftCore so this file stays iOS-only.
public final class BackupService: @unchecked Sendable {
    /// iCloud container identifier — matches `iCloud.com.drift.health`
    /// declared in entitlements + project.yml.
    public static let ubiquityContainerIdentifier = "iCloud.com.drift.health"

    /// Subdirectory inside the ubiquity container where `.driftbackup` files
    /// live. Created on first backup.
    public static let backupsSubdirectory = "Backups"

    /// UserDefaults key for the most recent successful *upload-confirmed*
    /// backup timestamp. `BackupMonitor` (#679) consumes this for the
    /// stale-banner check; SettingsView surfaces it as "Last backed up".
    public static let lastSuccessfulBackupDateKey = "drift.lastSuccessfulBackupDate"

    /// UserDefaults key for the most recent backup error message. Cleared on
    /// next successful upload.
    public static let lastBackupErrorKey = "drift.lastBackupError"

    public static let shared = BackupService()

    private let containerURLProvider: () -> URL?
    private let database: () -> AppDatabase
    private let userDefaults: UserDefaults
    private let bundle: Bundle
    private let now: () -> Date
    private let packager: BackupPackager
    private let restorer: BackupRestorer
    private let queriesLock = NSLock()
    private var activeQueries: [URL: NSMetadataQuery] = [:]
    private var queryObservers: [URL: NSObjectProtocol] = [:]

    public convenience init() {
        self.init(
            containerURLProvider: {
                FileManager.default.url(
                    forUbiquityContainerIdentifier: BackupService.ubiquityContainerIdentifier
                )
            },
            database: { AppDatabase.shared },
            userDefaults: .standard,
            bundle: .main,
            now: { Date() }
        )
    }

    public init(
        containerURLProvider: @escaping () -> URL?,
        database: @escaping () -> AppDatabase,
        userDefaults: UserDefaults,
        bundle: Bundle,
        now: @escaping () -> Date = { Date() }
    ) {
        self.containerURLProvider = containerURLProvider
        self.database = database
        self.userDefaults = userDefaults
        self.bundle = bundle
        self.now = now
        self.packager = BackupPackager()
        self.restorer = BackupRestorer()
    }

    // MARK: - Public API

    /// Root of the iCloud Drive ubiquity container, or throw `.iCloudUnavailable`
    /// when the user has iCloud Drive disabled or is signed out.
    public func containerURL() throws -> URL {
        guard let url = containerURLProvider() else {
            throw BackupError.iCloudUnavailable
        }
        return url
    }

    /// Build a `.driftbackup`, move it into the iCloud container, prune the
    /// ring buffer, and start an `NSMetadataQuery` to record
    /// `lastSuccessfulBackupDate` once iCloud confirms upload. Returns the
    /// destination URL after the file is on disk; upload confirmation is
    /// async and side-effects UserDefaults later.
    @discardableResult
    public func performBackup() async throws -> URL {
        let timestamp = now()
        let backupsDir = try backupsDirectory()
        let filename = BackupPackager.filename(for: timestamp)
        let destination = backupsDir.appendingPathComponent(filename)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)

        do {
            _ = try packager.package(
                dbWriter: database().writer,
                userDefaults: userDefaults,
                appMetadata: appMetadata(),
                timestamp: timestamp,
                destination: tempURL
            )
            try moveOrMapQuota(from: tempURL, to: destination)
        } catch let err as BackupError {
            recordError(err)
            throw err
        } catch {
            let mapped = mapWriteError(error)
            recordError(mapped)
            throw mapped
        }

        pruneRingBuffer(excluding: destination)
        startUploadMonitor(for: destination)
        // Local write succeeded — the previous failure is no longer "the last
        // attempt." Clearing here keeps Settings → Backup from showing a stale
        // red error label next to the green "uploading…" confirmation while
        // we wait for `recordUploadSuccess` to fire from the metadata query.
        userDefaults.removeObject(forKey: Self.lastBackupErrorKey)
        return destination
    }

    /// Enumerate every `.driftbackup` in the container's `Backups/`
    /// subdirectory. Files whose manifest can't be parsed are dropped (a
    /// half-uploaded or hand-crafted file shouldn't crash the picker).
    /// Returns newest-first.
    public func availableBackups() -> [BackupInfo] {
        guard let backupsDir = try? backupsDirectory() else { return [] }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: backupsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        return entries
            .filter { $0.pathExtension == BackupKeys.backupFileExtension }
            .compactMap { url -> BackupInfo? in
                guard let manifest = try? BackupPackager.readManifest(from: url) else {
                    return nil
                }
                return BackupInfo(url: url, manifest: manifest)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Run integrity validation + atomic restore from a backup URL into the
    /// app's live SQLite path. Mapping into `BackupError` is the responsibility
    /// of `BackupRestorer`; we just re-throw.
    @discardableResult
    public func restore(from backupURL: URL) async throws -> BackupManifest {
        let databaseURL = try AppDatabase.databaseFileURL()
        return try restorer.restore(
            from: backupURL,
            toDatabasePath: databaseURL,
            userDefaults: userDefaults
        )
    }

    /// Most recent upload-confirmed backup date, or nil if no successful
    /// upload has been observed.
    public var lastSuccessfulBackupDate: Date? {
        userDefaults.object(forKey: Self.lastSuccessfulBackupDateKey) as? Date
    }

    /// Most recent backup error string, or nil after the next successful
    /// upload clears it.
    public var lastBackupError: String? {
        userDefaults.string(forKey: Self.lastBackupErrorKey)
    }

    // MARK: - Internals

    func backupsDirectory() throws -> URL {
        let container = try containerURL()
        let dir = container.appendingPathComponent(Self.backupsSubdirectory, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func appMetadata() -> BackupPackager.AppMetadata {
        let version = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
        let build = (bundle.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
        return BackupPackager.AppMetadata(
            appBuild: build,
            appVersion: version,
            schemaVersion: Migrations.currentVersion
        )
    }

    private func moveOrMapQuota(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        do {
            try fm.moveItem(at: source, to: destination)
        } catch {
            throw mapWriteError(error)
        }
    }

    private func mapWriteError(_ error: Error) -> BackupError {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError {
            return .quotaExceeded
        }
        return .invalidFormat("write failed: \(error.localizedDescription)")
    }

    private func recordError(_ err: BackupError) {
        userDefaults.set(String(describing: err), forKey: Self.lastBackupErrorKey)
    }

    private func pruneRingBuffer(excluding newURL: URL) {
        let all = availableBackups()
        let (_, delete) = BackupRingBuffer.partition(all, now: now())
        let fm = FileManager.default
        for backup in delete where backup.url != newURL {
            try? fm.removeItem(at: backup.url)
        }
    }

    // MARK: - Upload monitoring

    private func startUploadMonitor(for url: URL) {
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(
            format: "%K == %@",
            NSMetadataItemFSNameKey,
            url.lastPathComponent as NSString
        )

        let token = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate,
            object: query,
            queue: .main
        ) { [weak self] _ in
            self?.handleMetadataUpdate(query: query, monitoredURL: url)
        }

        queriesLock.lock()
        activeQueries[url] = query
        queryObservers[url] = token
        queriesLock.unlock()

        DispatchQueue.main.async {
            query.start()
        }
    }

    private func handleMetadataUpdate(query: NSMetadataQuery, monitoredURL: URL) {
        query.disableUpdates()
        defer { query.enableUpdates() }
        for i in 0..<query.resultCount {
            guard let item = query.result(at: i) as? NSMetadataItem else { continue }
            let isUploaded = (item.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool) ?? false
            let uploadError = item.value(forAttribute: NSMetadataUbiquitousItemUploadingErrorKey) as? NSError
            if isUploaded && uploadError == nil {
                recordUploadSuccess(date: now())
                stopMonitor(for: monitoredURL)
                return
            }
            if let uploadError {
                recordUploadFailure(uploadError)
                stopMonitor(for: monitoredURL)
                return
            }
        }
    }

    /// Persist `lastSuccessfulBackupDate` and clear `lastBackupError`. Called
    /// from the NSMetadataQuery completion path; exposed at internal access
    /// for unit tests that can't fabricate `NSMetadataItem` directly.
    func recordUploadSuccess(date: Date) {
        userDefaults.set(date, forKey: Self.lastSuccessfulBackupDateKey)
        userDefaults.removeObject(forKey: Self.lastBackupErrorKey)
    }

    /// Persist an upload failure surfaced via `NSMetadataUbiquitousItemUploadingErrorKey`
    /// so Settings → Backup can show it. Maps `NSFileWriteOutOfSpaceError` to
    /// `.quotaExceeded` to match the local-write path.
    func recordUploadFailure(_ error: NSError) {
        let mapped: BackupError
        if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
            mapped = .quotaExceeded
        } else {
            mapped = .invalidFormat("upload failed: \(error.localizedDescription)")
        }
        userDefaults.set(String(describing: mapped), forKey: Self.lastBackupErrorKey)
    }

    private func stopMonitor(for url: URL) {
        queriesLock.lock()
        defer { queriesLock.unlock() }
        if let token = queryObservers.removeValue(forKey: url) {
            NotificationCenter.default.removeObserver(token)
        }
        if let query = activeQueries.removeValue(forKey: url) {
            query.stop()
        }
    }
}
