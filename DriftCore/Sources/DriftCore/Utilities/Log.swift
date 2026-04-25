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
