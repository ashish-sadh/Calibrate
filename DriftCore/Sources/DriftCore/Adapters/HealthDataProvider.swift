import Foundation

// MARK: - Value Types (replace nested HealthKitService.HealthWorkout / .SleepNight)

public struct HealthWorkout: Sendable, Identifiable {
    public let id: UUID
    public let type: String
    public let duration: TimeInterval
    public let calories: Double
    public let date: Date

    public init(id: UUID, type: String, duration: TimeInterval, calories: Double, date: Date) {
        self.id = id
        self.type = type
        self.duration = duration
        self.calories = calories
        self.date = date
    }

    public var durationDisplay: String {
        let m = Int(duration) / 60
        let h = m / 60
        return h > 0 ? "\(h)h \(m % 60)m" : "\(m)m"
    }
}

public struct SleepNight: Sendable {
    public let date: Date
    public let hours: Double

    public init(date: Date, hours: Double) {
        self.date = date
        self.hours = hours
    }
}

public struct CaloriesBurned: Sendable {
    public let active: Double
    public let basal: Double

    public init(active: Double, basal: Double) {
        self.active = active
        self.basal = basal
    }
}

// MARK: - HealthDataProvider Protocol

/// Adapter for HealthKit-backed data. iOS Drift app provides the concrete impl;
/// macOS tests inject a stub. Cross-platform services in DriftCore
/// (e.g. ToolRegistration handlers) reach HealthKit only through this seam.
public protocol HealthDataProvider: Sendable {
    @MainActor var isAvailable: Bool { get }
    @MainActor func fetchRecentWorkouts(days: Int) async throws -> [HealthWorkout]
    @MainActor func fetchRecentSleepData(days: Int) async throws -> [SleepNight]
    @MainActor func fetchCaloriesBurned(for date: Date) async throws -> CaloriesBurned
    @MainActor func fetchSteps(for date: Date) async throws -> Double
    @MainActor func fetchSleepHours(for date: Date) async throws -> Double
    @MainActor func fetchSleepDetail(for date: Date) async throws -> SleepDetail
    @MainActor func fetchHRV(for date: Date) async throws -> Double
    @MainActor func fetchRestingHeartRate(for date: Date) async throws -> Double
    @MainActor func fetchCycleHistory(days: Int) async throws -> [CycleEntry]
}
