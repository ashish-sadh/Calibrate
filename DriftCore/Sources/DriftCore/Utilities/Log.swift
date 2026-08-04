/// Android's `ANDROID_LOG_*` priorities from `android/log.h` (ABI-stable since
/// API 1), keyed by the level names `PlainLogger.emit` uses. Declared outside
/// the platform gates so it stays testable from macOS.
enum AndroidLogPriority {
    static func priority(for level: String) -> Int32 {
        switch level {
        case "debug": return 3
        case "info": return 4
        case "warning": return 5
        case "error": return 6
        case "fault": return 7
        default: return 4
        }
    }
}

#if canImport(os)
import os

/// Structured logging for the Drift app using os.Logger.
/// View logs in Console.app with subsystem filter: "com.drift.health"
public enum Log {
    public static let database = Logger(subsystem: "com.drift.health", category: "database")
    public static let healthKit = Logger(subsystem: "com.drift.health", category: "healthkit")
    public static let weightTrend = Logger(subsystem: "com.drift.health", category: "weight-trend")
    public static let foodLog = Logger(subsystem: "com.drift.health", category: "food-log")
    public static let supplements = Logger(subsystem: "com.drift.health", category: "supplements")
    public static let glucose = Logger(subsystem: "com.drift.health", category: "glucose")
    public static let bodyComp = Logger(subsystem: "com.drift.health", category: "body-composition")
    public static let biomarkers = Logger(subsystem: "com.drift.health", category: "biomarkers")
    public static let app = Logger(subsystem: "com.drift.health", category: "app")
}
#else

#if os(Android)
/// liblog's C entry point, declared directly rather than by depending on
/// swift-android-native's `AndroidLogging` — that would make every macOS
/// `swift test` and iOS build resolve an extra package for three lines. The
/// `log` library is linked via the platform-conditioned `linkerSettings` on
/// the DriftCore target in Package.swift.
@_silgen_name("__android_log_write")
private func drift_android_log_write(_ priority: Int32,
                                     _ tag: UnsafePointer<CChar>,
                                     _ text: UnsafePointer<CChar>) -> Int32
#endif

/// Fallback logger for platforms without os.Logger (Android). Mirrors the
/// os.Logger call surface Drift uses (debug/info/warning/error/fault) so
/// call sites compile unchanged.
///
/// On Android, output goes straight to liblog — Android discards a process's
/// stdout, so the `print` this used to do was silently dropped (#1081). The
/// tag is `com.drift.health/<category>`, matching the `subsystem/category`
/// shape Skip's own logger emits, so one `adb logcat | grep com.drift.health`
/// catches everything. Elsewhere off-Apple (Linux) it still prints to stdout.
public struct PlainLogger: Sendable {
    let category: String

    public func debug(_ message: String) { emit("debug", message) }
    public func info(_ message: String) { emit("info", message) }
    public func warning(_ message: String) { emit("warning", message) }
    public func error(_ message: String) { emit("error", message) }
    public func fault(_ message: String) { emit("fault", message) }

    private func emit(_ level: String, _ message: String) {
        #if os(Android)
        let tag = "com.drift.health/\(category)"
        let priority = AndroidLogPriority.priority(for: level)
        _ = tag.withCString { tagPointer in
            message.withCString { textPointer in
                drift_android_log_write(priority, tagPointer, textPointer)
            }
        }
        #else
        print("com.drift.health/\(category) [\(level)] \(message)")
        #endif
    }
}

public enum Log {
    public static let database = PlainLogger(category: "database")
    public static let healthKit = PlainLogger(category: "healthkit")
    public static let weightTrend = PlainLogger(category: "weight-trend")
    public static let foodLog = PlainLogger(category: "food-log")
    public static let supplements = PlainLogger(category: "supplements")
    public static let glucose = PlainLogger(category: "glucose")
    public static let bodyComp = PlainLogger(category: "body-composition")
    public static let biomarkers = PlainLogger(category: "biomarkers")
    public static let app = PlainLogger(category: "app")
}
#endif
