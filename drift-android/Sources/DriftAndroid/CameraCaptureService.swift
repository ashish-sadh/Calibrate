import Foundation
import SkipFuse
import DriftCore

/// Android half of the "Take Photo" capture path for Snap meal logging
/// (#1111). Sibling of `ImagePickerService` (gallery pick, #1128) — same
/// fire-then-recover shape, because Skip's reflection bridge can neither
/// call `suspend` functions nor deliver a Kotlin→Swift callback. Gallery
/// picking already has its own cross-platform seam (`DriftPlatform.imagePicker`);
/// this service is camera-only, matching `CameraCaptureFacade.kt`'s shape.
public final class CameraCaptureService {
    public init() {}

    private static let facadeClass = "drift.android.CameraCaptureFacade"
    /// Same poll cadence as `ImagePickerService` — a human-driven capture,
    /// no completion signal exists to await instead.
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
    private static func facadeHasPermission() -> Bool {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).hasPermission() as Bool?) ?? false
    }
    private static func facadeRequestPermission() -> Bool {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).requestPermission() as Bool?) ?? false
    }
    private static func facadePermissionPoll() -> Int {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).permissionPoll() as Int?) ?? 2
    }
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
    private static func facadeHasPermission() -> Bool { false }
    private static func facadeRequestPermission() -> Bool { false }
    private static func facadePermissionPoll() -> Int { 2 }
    private static func facadeLaunch(_ maxEdge: Int, _ quality: Int) -> Bool { false }
    private static func facadePoll() -> Int { 3 }
    private static func facadeTakeResult() -> String? { nil }
    #endif

    /// Requests CAMERA permission if needed, fires the system camera, and
    /// returns the captured JPEG (downscaled + EXIF-corrected on the Kotlin
    /// side). Returns nil on permission denial, user cancel, or failure —
    /// callers cannot distinguish these (matches `ImagePickerService`'s
    /// cancel semantics; there is nothing actionable to say beyond "didn't
    /// get a photo").
    @MainActor
    public func captureImage(maxLongEdge: Int, quality: Double) async -> Data? {
        if !Self.facadeHasPermission() {
            guard Self.facadeRequestPermission() else { return nil }
            while true {
                try? await Task.sleep(nanoseconds: Self.pollNanos)
                let status = (try? await Self.onFacadeQueue { Self.facadePermissionPoll() }) ?? 2
                if status == 1 { break }      // granted
                if status == 2 { return nil } // denied
                // 0 = still pending the system dialog — keep polling.
            }
        }

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
                logger.info("CameraCaptureService: captured \(data.count) bytes")
                return data
            case 3:
                return nil
            default:
                continue // 1 = camera up / decoding — keep polling
            }
        }
    }
}
