import Foundation
import UIKit
import DriftCore

/// On-device storage for progress photos. Image bytes live as JPEGs in the
/// app's Application Support container (never leaves the device — privacy-
/// first); the DB holds only the filename. All calls are cheap file I/O off
/// any large in-memory caches.
enum ProgressPhotoStore {

    /// `<AppSupport>/ProgressPhotos/`. Created on first use.
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ProgressPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Progress photos are private health data — exclude from iCloud
            // backup unless the user explicitly opts into a photo export.
            var mutableDir = dir
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? mutableDir.setResourceValues(values)
        }
        return dir
    }

    static func url(for filename: String) -> URL {
        directory.appendingPathComponent(filename)
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
            return filename
        } catch {
            Log.app.error("ProgressPhotoStore save failed: \(error.localizedDescription)")
            return nil
        }
    }

    static func load(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    static func delete(_ filename: String) {
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
