import SwiftUI
import DriftCore
#if canImport(UIKit)
import UIKit
#endif

/// One progress photo, loaded from the on-device JPEG. Mirrors the platform
/// split `ExercisePoseViews` established for pose photos: iOS decodes into a
/// `UIImage` (via `ProgressPhotoStore`'s NSCache, so scrolling a long history
/// doesn't re-decode 1440px JPEGs every pass), Android hands the file URL to
/// SkipUI's `AsyncImage`, which Coil loads and caches.
///
/// The `#if canImport(UIKit)` branch is the iOS app; the `#else` serves BOTH
/// the Android target and skipstone's macOS host pass, which compiles
/// SharedUICopy without UIKit (project_skip_sharedui_three_configs).
struct ProgressPhotoImage: View {
    let filename: String
    /// Drawn when the file is missing — a partial restore must not leave a
    /// blank hole in the timeline.
    var placeholderGlyph: String = "camera"

    var body: some View {
        #if canImport(UIKit) && DRIFT_IOS_APP
        if let image = ProgressPhotoStore.load(filename) {
            Image(uiImage: image).resizable().scaledToFill()
        } else {
            placeholder
        }
        #else
        if ProgressPhotoPaths.fileExists(filename) {
            AsyncImage(url: ProgressPhotoPaths.url(for: filename)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(Theme.cardBackgroundElevated)
            }
        } else {
            placeholder
        }
        #endif
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Theme.cardBackgroundElevated)
            #if os(Android)
            CameraShape()
                .stroke(Theme.textTertiary, lineWidth: 1.5)
                .frame(width: 18, height: 18)
            #else
            Image(systemName: placeholderGlyph)
                .font(.caption2).foregroundStyle(Theme.textTertiary)
            #endif
        }
    }
}
