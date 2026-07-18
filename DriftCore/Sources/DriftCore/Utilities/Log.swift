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

/// Fallback logger for platforms without os.Logger (Android). Mirrors the
/// os.Logger call surface Drift uses (debug/info/warning/error/fault) so
/// call sites compile unchanged; output goes to stdout, which Android
/// surfaces in logcat.
public struct PlainLogger: Sendable {
    let category: String

    public func debug(_ message: String) { emit("debug", message) }
    public func info(_ message: String) { emit("info", message) }
    public func warning(_ message: String) { emit("warning", message) }
    public func error(_ message: String) { emit("error", message) }
    public func fault(_ message: String) { emit("fault", message) }

    private func emit(_ level: String, _ message: String) {
        print("com.drift.health/\(category) [\(level)] \(message)")
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
