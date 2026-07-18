import Foundation
#if canImport(os)
import os.signpost
#endif

/// Cold-launch instrumentation. Each blocking step in `DriftApp.task` wraps
/// itself with a start-time and a `LaunchTrace.logStep(...)` call, emitting
/// both Console.app-filterable text (via `Log.app`) and an Instruments
/// signpost. Without this, "launch feels slow" complaints get debugged from
/// zero every time — we'd been shipping startup fixes against guessed numbers.
///
/// Filter: subsystem `com.drift.health`, category `app` (text logs) or
/// `launch` (signposts).
public enum LaunchTrace {
    #if canImport(os)
    private static let signposter = OSSignposter(subsystem: "com.drift.health", category: "launch")
    #endif

    /// Format a per-step trace line. Pure formatting so callers can be unit-tested.
    public static func formatStep(_ step: String, elapsedMs: Int) -> String {
        "launch_trace step=\(step) elapsed_ms=\(elapsedMs)"
    }

    /// Format the end-to-end trace line.
    public static func formatTotal(elapsedMs: Int) -> String {
        "launch_trace step=sync_complete total_ms=\(elapsedMs)"
    }

    /// Milliseconds elapsed since `start`. Truncated to Int for stable log shape.
    public static func elapsedMs(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }

    /// Log a completed step. Emits Console.app text + Instruments signpost.
    public static func logStep(_ step: String, elapsedMs: Int) {
        #if canImport(os)
        Log.app.info("\(formatStep(step, elapsedMs: elapsedMs), privacy: .public)")
        signposter.emitEvent("launch_step", "step=\(step) elapsed_ms=\(elapsedMs)")
        #else
        Log.app.info(formatStep(step, elapsedMs: elapsedMs))
        #endif
    }

    /// Log end-to-end launch time. Emits Console.app text + Instruments signpost.
    public static func logTotal(elapsedMs: Int) {
        #if canImport(os)
        Log.app.info("\(formatTotal(elapsedMs: elapsedMs), privacy: .public)")
        signposter.emitEvent("launch_complete", "total_ms=\(elapsedMs)")
        #else
        Log.app.info(formatTotal(elapsedMs: elapsedMs))
        #endif
    }
}
