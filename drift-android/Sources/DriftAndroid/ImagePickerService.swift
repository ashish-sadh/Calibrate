import Foundation
import SkipFuse
import DriftCore

/// Android half of the `DriftPlatform.imagePicker` seam (#1128).
///
/// Launches the system Photo Picker through `ImagePickerFacade.kt` and polls
/// its companion-object state for the result — the same fire-then-recover
/// shape HealthConnectFacade uses, because Skip's reflection bridge can
/// neither call `suspend` functions nor deliver a Kotlin→Swift callback.
/// The picked photo arrives as one base64 JPEG string, already downscaled and
/// EXIF-corrected on the Kotlin side (Swift-on-Android has no image APIs).
public final class ImagePickerService: ImagePicking {
    public init() {}

    private static let facadeClass = "drift.android.ImagePickerFacade"
    /// Human-driven picker: a 120 ms poll costs a few dozen cheap int reads
    /// over the seconds the user browses; no completion signal exists to await.
    private static let pollNanos: UInt64 = 120_000_000

    private static func onFacadeQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try work()) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    // The JNI bridge exists only in the Android compile; Skip's Darwin
    // bridging pass compiles this same file for iphonesimulator, so every
    // facade touchpoint lives behind one #if with inert Darwin stubs.
    #if os(Android)
    private static func facadeLaunch(_ maxEdge: Int, _ quality: Int) -> Bool {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).launch(maxEdge, quality) as Bool?) ?? false
    }
    private static func facadePoll() -> Int {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).poll() as Int?) ?? 3
    }
    private static func facadeTakeResult() -> String? {
        try? AnyDynamicObject(className: facadeClass, arguments: []).takeResult() as String?
    }
    #else
    private static func facadeLaunch(_ maxEdge: Int, _ quality: Int) -> Bool { false }
    private static func facadePoll() -> Int { 3 }
    private static func facadeTakeResult() -> String? { nil }
    #endif

    @MainActor
    public func pickLibraryImage(maxLongEdge: Int, quality: Double) async -> Data? {
        // launch() must run on the Android main thread (it fires an Activity
        // contract) — @MainActor IS the main looper, so call it directly.
        guard Self.facadeLaunch(maxLongEdge, Int((quality * 100).rounded())) else { return nil }
        while true {
            try? await Task.sleep(nanoseconds: Self.pollNanos)
            let status = (try? await Self.onFacadeQueue { Self.facadePoll() }) ?? 3
            switch status {
            case 2:
                let b64 = try? await Self.onFacadeQueue { Self.facadeTakeResult() }
                guard let b64, let data = Data(base64Encoded: b64), !data.isEmpty else { return nil }
                logger.info("ImagePickerService: picked \(data.count) bytes")
                return data
            case 3:
                return nil
            default:
                continue // 1 = picker up / decoding — keep polling
            }
        }
    }
}
