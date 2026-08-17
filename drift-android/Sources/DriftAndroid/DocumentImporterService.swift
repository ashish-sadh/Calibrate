import Foundation
import SkipFuse
import DriftCore

/// Android half of the `DriftPlatform.documentImporter` seam (#1175).
///
/// Launches the system document picker (SAF `ACTION_OPEN_DOCUMENT`) through
/// `DocumentPickerFacade.kt` and polls its companion-object state for the
/// result — the same fire-then-recover shape `ImagePickerService` uses, because
/// Skip's reflection bridge can neither call `suspend` functions nor deliver a
/// Kotlin→Swift callback. The picked file arrives as one base64 string; unlike
/// the image seam there is no decode step, the bytes are the file's own.
///
/// SAF grants a transient read on the returned `content://` Uri, so this seam
/// asks for no runtime permission and adds nothing to the manifest.
public final class DocumentImporterService: DocumentImporting {
    public init() {}

    private static let facadeClass = "drift.android.DocumentPickerFacade"
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
    /// MIME types cross as ONE comma-joined String: multi-String facade args
    /// are proven (`HttpFacade.post`), an `Array<String>` arg through
    /// `AnyDynamicObject` is not.
    private static func facadeLaunch(_ mimeCsv: String) -> Bool {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).launch(mimeCsv) as Bool?) ?? false
    }
    private static func facadePoll() -> Int {
        (try? AnyDynamicObject(className: facadeClass, arguments: []).poll() as Int?) ?? 3
    }
    private static func facadeTakeResult() -> String? {
        try? AnyDynamicObject(className: facadeClass, arguments: []).takeResult() as String?
    }
    #else
    private static func facadeLaunch(_ mimeCsv: String) -> Bool { false }
    private static func facadePoll() -> Int { 3 }
    private static func facadeTakeResult() -> String? { nil }
    #endif

    @MainActor
    public func importDocument(allowedMIMETypes: [String]) async -> Data? {
        // launch() must run on the Android main thread (it fires an Activity
        // contract) — @MainActor IS the main looper, so call it directly.
        guard Self.facadeLaunch(allowedMIMETypes.joined(separator: ",")) else { return nil }
        while true {
            try? await Task.sleep(nanoseconds: Self.pollNanos)
            let status = (try? await Self.onFacadeQueue { Self.facadePoll() }) ?? 3
            switch status {
            case 2:
                let b64 = try? await Self.onFacadeQueue { Self.facadeTakeResult() }
                guard let b64, let data = Data(base64Encoded: b64), !data.isEmpty else { return nil }
                logger.info("DocumentImporterService: imported \(data.count) bytes")
                return data
            case 3:
                return nil
            default:
                continue // 1 = picker up / reading — keep polling
            }
        }
    }
}
