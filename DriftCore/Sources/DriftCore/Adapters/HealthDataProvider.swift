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

    /// Decodes the Android Health Connect facade's JSON array
    /// (`[{"id","type","durationSec","calories","startMillis"}, ...]`) into
    /// the same shape HealthKit produces: sorted start-date DESC, capped 100.
    /// `startMillis` is epoch millis, never a DateFormatter round-trip — an
    /// unpinned formatter is UTC on Android but local on Apple platforms.
    public static func decode(fromFacadeJSON json: String) -> [HealthWorkout] {
        guard let data = json.data(using: .utf8),
              let records = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let workouts = records.compactMap { record -> HealthWorkout? in
            guard let type = record["type"] as? String,
                  let durationSec = record["durationSec"] as? Double,
                  let startMillis = record["startMillis"] as? Double else { return nil }
            let calories = record["calories"] as? Double ?? 0
            let id = (record["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            return HealthWorkout(
                id: id,
                type: type,
                duration: durationSec,
                calories: calories,
                date: Date(timeIntervalSince1970: startMillis / 1000)
            )
        }
        return Array(workouts.sorted { $0.date > $1.date }.prefix(100))
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

/// Age / height / biological sex sourced from the platform health store.
/// All fields optional — the store may have none of them.
public struct HealthUserProfile: Sendable {
    public let age: Int?
    public let heightCm: Double?
    public let sex: TDEEEstimator.Sex?

    public init(age: Int?, heightCm: Double?, sex: TDEEEstimator.Sex?) {
        self.age = age
        self.heightCm = heightCm
        self.sex = sex
    }
}

// MARK: - HealthDataProvider Protocol

/// Adapter for platform health-store data (HealthKit on iOS, Health Connect on
/// Android). The app shell provides the concrete impl; macOS tests inject a
/// stub. Cross-platform services in DriftCore (e.g. ToolRegistration handlers)
/// and all Views reach the health store only through this seam.
public protocol HealthDataProvider: Sendable {
    @MainActor var isAvailable: Bool { get }
    @MainActor func requestAuthorization() async throws
    @MainActor func fetchUserProfile() async -> HealthUserProfile
    @MainActor func fetchRecentWorkouts(days: Int) async throws -> [HealthWorkout]
    @MainActor func fetchRecentSleepData(days: Int) async throws -> [SleepNight]
    @MainActor func fetchCaloriesBurned(for date: Date) async throws -> CaloriesBurned
    @MainActor func fetchSteps(for date: Date) async throws -> Double
    @MainActor func fetchSleepHours(for date: Date) async throws -> Double
    @MainActor func fetchSleepDetail(for date: Date) async throws -> SleepDetail
    @MainActor func fetchHRV(for date: Date) async throws -> Double
    @MainActor func fetchRestingHeartRate(for date: Date) async throws -> Double
    @MainActor func fetchRespiratoryRate(for date: Date) async throws -> Double
    @MainActor func fetchGlucoseReadings(from startDate: Date, to endDate: Date) async throws -> [GlucoseReading]
    @MainActor func fetchCycleHistory(days: Int) async throws -> [CycleEntry]
    @MainActor func fetchOvulationHistory(days: Int) async throws -> [OvulationEntry]
    @MainActor func fetchBBTHistory(days: Int) async throws -> [BBTEntry]
    @MainActor func fetchSpottingHistory(days: Int) async throws -> [SpottingEntry]
    @MainActor func hasCycleData() async -> Bool
    @MainActor func fetchHRVHistory(days: Int) async throws -> [(date: Date, ms: Double)]
    @MainActor func fetchRestingHeartRateHistory(days: Int) async throws -> [(date: Date, bpm: Double)]
    @MainActor func fetchRespiratoryRateHistory(days: Int) async throws -> [(date: Date, rpm: Double)]
    @MainActor func fetchSleepHistory(days: Int) async throws -> [(date: Date, hours: Double)]
    @MainActor func syncWeight() async throws -> Int
    @MainActor func fullResyncWeight() async throws -> Int
    @MainActor func syncBodyComposition() async throws -> Int
}
