import Foundation

/// Photo-library image-in seam (#1128) — the ONE API every image-capture
/// surface calls, so picker plumbing never becomes an `#if` forest in views.
///
/// Presents the OS photo library and returns the picked image as a downscaled
/// JPEG (long edge ≤ `maxLongEdge`, `quality` 0…1), or nil if the user cancels
/// or the pick fails. The returned bytes are ready to POST to a vision model or
/// persist to disk — consumers never see a platform image type.
///
/// iOS wraps `PHPickerViewController` (the same picker SwiftUI's `PhotosPicker`
/// wraps); Android wraps `ImagePickerFacade` (PickVisualMedia Activity-result,
/// decode + downscale on the Kotlin side because Swift-on-Android has no image
/// APIs). Registered at launch as `DriftPlatform.imagePicker`; nil on
/// macOS/tests = fail-soft (entry points hide or no-op).
public protocol ImagePicking: Sendable {
    @MainActor func pickLibraryImage(maxLongEdge: Int, quality: Double) async -> Data?
}
