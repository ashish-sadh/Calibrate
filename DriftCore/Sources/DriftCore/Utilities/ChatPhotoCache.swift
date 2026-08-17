import Foundation

/// Scratch store for chat photo attachments (#1174).
///
/// Android has no `Data` → `Image` API — SkipUI renders images from a URL
/// (Coil-backed `AsyncImage`), so an attached JPEG has to exist as a file
/// before the input-bar thumbnail or the user bubble can show it. iOS decodes
/// the same bytes with `UIImage(data:)` and never calls in here; the type lives
/// in DriftCore because it is pure Foundation.
///
/// These files are scratch, not user data: caches directory, UUID names (so
/// Coil's URL-keyed cache can never serve a stale photo after a re-attach), and
/// `store` prunes anything older than a day on the way in.
///
/// GC deliberately does NOT hang off the view model's lifecycle. Wiping in
/// `AIChatViewModel.init` looked equivalent and is not: `@State var vm =
/// AIChatViewModel()` re-evaluates its initial value every time Compose
/// re-instantiates the view struct, so the wipe fired *after* an attach and
/// deleted the file the live thumbnail pointed at — a blank square on the
/// emulator (#1174). An age prune has no such coupling and needs no caller.
public enum ChatPhotoCache {

    /// Attachments outlive the turn that sent them (the user bubble keeps
    /// rendering its photo), so the prune window is a day rather than a
    /// session. The OS also reclaims the caches directory under pressure.
    static let maxAge: TimeInterval = 24 * 60 * 60

    /// `<caches>/chat-photos/`. Created on demand by `store`; `clear` removes it
    /// outright, so a platform that never attaches a photo never creates it.
    public static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("chat-photos", isDirectory: true)
    }

    /// Write `data` to a fresh JPEG and return its URL, or nil if the write
    /// fails — the caller then sends the turn without a visible thumbnail
    /// rather than blocking the send.
    public static func store(_ data: Data, now: Date = Date()) -> URL? {
        let dir = directory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        prune(before: now.addingTimeInterval(-maxAge))
        let url = dir.appendingPathComponent("\(UUID().uuidString).jpg")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Log.app.error("ChatPhotoCache: could not write attachment to \(dir.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Drop attachments last modified before `cutoff`.
    static func prune(before cutoff: Date) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified >= cutoff { continue }
            try? fm.removeItem(at: entry)
        }
    }

    /// Drop one attachment — the input bar's remove-X, so a discarded photo
    /// doesn't sit in caches until the next chat presentation.
    public static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Wipe every cached attachment.
    public static func clear() {
        let dir = directory
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.removeItem(at: dir)
    }
}
