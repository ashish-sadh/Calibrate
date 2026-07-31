import Foundation
import PhotosUI
import UIKit
import DriftCore

/// iOS half of the `DriftPlatform.imagePicker` seam (#1128).
///
/// Wraps `PHPickerViewController` — the same UIKit picker SwiftUI's
/// `PhotosPicker` itself wraps, so consumers routed through this adapter get a
/// visually identical pick flow. Downscale matches the pre-seam call sites
/// (UIGraphicsImageRenderer long-edge clamp + jpegData), so routing a view
/// through the adapter is a no-behavior-change refactor.
final class ImagePickerService: ImagePicking {

    @MainActor
    func pickLibraryImage(maxLongEdge: Int, quality: Double) async -> Data? {
        guard let presenter = Self.presentingController() else { return nil }
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        let delegate = PickerDelegate()
        picker.delegate = delegate
        let image: UIImage? = await withCheckedContinuation { continuation in
            delegate.continuation = continuation
            presenter.present(picker, animated: true)
        }
        withExtendedLifetime(delegate) {} // delegate must outlive the pick
        guard let image else { return nil }
        return Self.jpeg(image, maxLongEdge: CGFloat(maxLongEdge), quality: CGFloat(quality))
    }

    /// Topmost presented controller off the key window — presenting from the
    /// root while a sheet is up (the normal case: pickers launch from sheets)
    /// would silently no-op.
    @MainActor
    private static func presentingController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// Same downscale as WorkoutScanSheet.jpegForUpload — long-edge clamp via
    /// UIGraphicsImageRenderer at scale 1, then jpegData.
    private static func jpeg(_ image: UIImage, maxLongEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maxLongEdge ? maxLongEdge / longEdge : 1
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.jpegData(compressionQuality: quality)
    }

    /// Bridges PHPicker's delegate callback to the awaiting continuation.
    /// PHPicker calls the delegate exactly once (including on cancel, with an
    /// empty results array), but `resumed` guards double-resume anyway —
    /// resuming a continuation twice is undefined behavior, not a soft bug.
    private final class PickerDelegate: NSObject, PHPickerViewControllerDelegate {
        var continuation: CheckedContinuation<UIImage?, Never>?
        private var resumed = false

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else {
                resume(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
                // Narrow to UIImage (Sendable) BEFORE hopping queues — sending
                // the raw NSItemProviderReading across is a Swift 6 race error.
                let image = object as? UIImage
                DispatchQueue.main.async {
                    self?.resume(image)
                }
            }
        }

        private func resume(_ image: UIImage?) {
            guard !resumed else { return }
            resumed = true
            continuation?.resume(returning: image)
            continuation = nil
        }
    }
}
