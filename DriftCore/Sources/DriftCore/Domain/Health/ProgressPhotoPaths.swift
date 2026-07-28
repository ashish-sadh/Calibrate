import Foundation

/// Where progress-photo JPEGs live on disk. Pure Foundation so BOTH apps can
/// resolve a file URL: iOS decodes it into a `UIImage`, Android hands the URL
/// to SkipUI's `AsyncImage` (the same split `ExercisePoseViews` uses for pose
/// photos). The image bytes never leave the device — the DB stores only the
/// filename.
///
/// Split out of the iOS-only `ProgressPhotoStore` (which keeps the UIImage
/// encode/decode + NSCache) when the gallery moved to SharedUI (#1121).
public enum ProgressPhotoPaths {

    /// `<AppSupport>/ProgressPhotos/`, created on first use. Photos are
    /// INCLUDED in iCloud device backup (operator 2026-07-14) so a migration
    /// restores them alongside the `progress_photo` rows that reference them.
    public static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    public static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// True when the backing file exists. Filters DB rows whose file didn't
    /// survive a partial restore, so the gallery shows no blank thumbnails.
    public static func fileExists(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: filename).path)
    }
}
