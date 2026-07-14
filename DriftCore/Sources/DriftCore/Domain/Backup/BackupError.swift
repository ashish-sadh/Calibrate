import Foundation

/// Failure modes for the iCloud backup + restore flow. Maps to the user-facing
/// copy in Section F of `Docs/designs/561-icloud-backup.md`.
public enum BackupError: Error, Equatable {
    /// `FileManager.default.url(forUbiquityContainerIdentifier:)` returned nil —
    /// iCloud Drive is off or the user is signed out of iCloud.
    case iCloudUnavailable

    /// iCloud quota is full (`NSFileWriteOutOfSpaceError`).
    case quotaExceeded

    /// Manifest checksum or `PRAGMA integrity_check` mismatch.
    case corrupted(String)

    /// Manifest is missing, malformed, or the zip lacks expected entries.
    case invalidFormat(String)

    /// Backup's `schemaVersion` is greater than what this app build supports —
    /// the user must update Drift before the backup can be restored.
    case unsupportedSchemaVersion(backupVersion: Int, current: Int)

    /// Backup's `backupFormatVersion` is greater than what this app build can read.
    case unsupportedFormatVersion(backupVersion: Int, current: Int)

    /// The snapshot was built fine but couldn't reach iCloud (network /
    /// server hiccup). Transient — the next daily backup retries.
    case uploadFailed(String)
}

extension BackupError {
    /// User-facing copy for Settings → Backup. NEVER show
    /// `String(describing:)` of this enum — the raw case dump
    /// (`invalidFormat("upload failed: …")`) leaked into the UI verbatim
    /// (field screenshot 2026-07-14).
    public var userMessage: String {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive is off or you're signed out of iCloud. Backup needs iCloud Drive enabled in Settings."
        case .quotaExceeded:
            return "Your iCloud storage is full — free up space or upgrade to keep backups running."
        case .corrupted:
            return "The backup file failed its integrity check. The next backup will replace it."
        case .invalidFormat(let detail):
            return "The backup couldn't be written (\(detail))."
        case .unsupportedSchemaVersion, .unsupportedFormatVersion:
            return "This backup was made by a newer version of Drift — update the app to restore it."
        case .uploadFailed:
            return "Couldn't reach iCloud — check your connection. Drift will retry automatically."
        }
    }
}
