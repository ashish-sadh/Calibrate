import Foundation

/// Coarse, ordered phases of a backup, surfaced to the UI so the user sees
/// concrete progress ("Compressing 3.2 MB…") instead of an opaque spinner that
/// just says "uploading". Each phase carries a short user-facing `message`.
/// #backup-progress
public enum BackupPhase: Sendable, Equatable {
    /// `VACUUM INTO` — copying the live SQLite database to a snapshot.
    case snapshotting
    /// Writing allowlisted preferences to JSON.
    case savingSettings
    /// Zipping the manifest + db + prefs. `bytes` is the uncompressed payload
    /// size so the message can say how much data is being packed.
    case compressing(bytes: Int64)
    /// Moving the finished `.driftbackup` into the iCloud container.
    case movingToCloud
    /// Handed to the iCloud daemon — the async upload has started (confirmation
    /// arrives later via the metadata query).
    case uploading

    /// Short user-facing status line.
    public var message: String {
        switch self {
        case .snapshotting:   return "Copying your data…"
        case .savingSettings: return "Saving your settings…"
        case .compressing(let bytes):
            return "Compressing backup (\(Self.sizeString(bytes)))…"
        case .movingToCloud:  return "Moving to iCloud…"
        case .uploading:      return "Uploading to iCloud…"
        }
    }

    static func sizeString(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f.string(fromByteCount: max(bytes, 0))
    }
}

/// Progress callback for a backup run. Invoked off the main thread during
/// packaging, so the UI must marshal to the main actor before touching state.
public typealias BackupProgressHandler = @Sendable (BackupPhase) -> Void

public extension Notification.Name {
    /// Posted (on the main thread) when an in-flight iCloud upload is confirmed
    /// or fails. Lets Settings update "Backed up ✓" / the error live, instead of
    /// only on the next `onAppear`. #backup-progress
    static let driftBackupUploadStateChanged = Notification.Name("drift.backupUploadStateChanged")
}
