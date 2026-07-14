import Foundation
import UIKit
import DriftCore

/// On-device storage for progress photos. Image bytes live as JPEGs in the
/// app's Application Support container (never leaves the device — privacy-
/// first); the DB holds only the filename. All calls are cheap file I/O off
/// any large in-memory caches.
enum ProgressPhotoStore {

    /// In-memory decode cache keyed by filename. Progress thumbnails are read
    /// on every gallery/compare render; without this each pass re-decodes full
    /// ~1440px JPEGs synchronously on the main thread (scroll jank). Bounded so
    /// a long history can't balloon memory.
    // NSCache is internally thread-safe, so unchecked shared access is fine.
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

    /// `<AppSupport>/ProgressPhotos/`. Created on first use. Photos are INCLUDED
    /// in iCloud device backup (operator 2026-07-14: "make progress photos part
    /// of iCloud backup") so a device migration restores them alongside the
    /// `progress_photo` DB rows that reference them.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
    }

    /// True when the backing file exists on disk. Used to filter DB rows whose
    /// file didn't survive (defensive; with backup inclusion this should be
    /// rare, but a partial restore must not show blank thumbnails).
    static func fileExists(_ filename: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: filename).path)
    }

    /// Persist an image for a (date, pose) as a downscaled JPEG. Returns the
    /// filename to store in the DB, or nil on failure. Filenames are stable per
    /// (date, pose) so re-shooting overwrites the same file.
    static func save(_ image: UIImage, date: String, pose: ProgressPose) -> String? {
        let filename = "\(date)_\(pose.rawValue).jpg"
        let downscaled = downscale(image, maxDimension: 1440)
        guard let data = downscaled.jpegData(compressionQuality: 0.82) else { return nil }
        do {
            try data.write(to: url(for: filename), options: .atomic)
            cache.setObject(downscaled, forKey: filename as NSString)  // re-shoot updates cache in place
            return filename
        } catch {
            Log.app.error("ProgressPhotoStore save failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func load(_ filename: String) -> UIImage? {
        if let cached = cache.object(forKey: filename as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: url(for: filename).path) else { return nil }
        cache.setObject(image, forKey: filename as NSString)
        return image
    }

    static func delete(_ filename: String) {
        cache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: url(for: filename))
    }

    static func delete(_ filenames: [String]) {
        for f in filenames { delete(f) }
    }

    /// Cap the longest side so a 12-megapixel camera shot doesn't cost ~5 MB
    /// each — 1440px is plenty for a side-by-side physique comparison.
    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
