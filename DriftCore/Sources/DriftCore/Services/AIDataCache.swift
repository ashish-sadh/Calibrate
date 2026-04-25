import Foundation

/// Caches async health data so synchronous context builders can use it.
/// Refreshed when the AI chat opens. 5-minute TTL.
@MainActor @Observable
public final class AIDataCache {
    public static let shared = AIDataCache()

    private init() {}

    public struct SleepData: Sendable {
        public let sleepHours: Double
        public let hrvMs: Double
        public let restingHR: Double
        public let recoveryScore: Int
        public let sleepDetail: SleepDetail?

        public init(sleepHours: Double, hrvMs: Double, restingHR: Double, recoveryScore: Int, sleepDetail: SleepDetail?) {
            self.sleepHours = sleepHours
            self.hrvMs = hrvMs
            self.restingHR = restingHR
            self.recoveryScore = recoveryScore
            self.sleepDetail = sleepDetail
        }
    }

    public struct CycleData: Sendable {
        public let currentCycleDay: Int?
        public let currentPhase: String?
        public let avgCycleLength: Int?
        public let periodCount: Int

        public init(currentCycleDay: Int?, currentPhase: String?, avgCycleLength: Int?, periodCount: Int) {
            self.currentCycleDay = currentCycleDay
            self.currentPhase = currentPhase
            self.avgCycleLength = avgCycleLength
            self.periodCount = periodCount
        }
    }

    public private(set) var sleep: SleepData?
    public private(set) var cycle: CycleData?
    private var lastRefresh: Date?
    /// Set by food_info tool handler when a lookup resolves; consumed by attachToolCards.
    nonisolated(unsafe) public var lastFoodLookupFood: Food?

    public func refreshIfNeeded() async {
        if let last = lastRefresh, Date().timeIntervalSince(last) < 300 { return }
        await refresh()
    }

    public func refresh() async {
        guard let hk = DriftPlatform.health else { return }
        let today = Date()

        let sleepHours = (try? await hk.fetchSleepHours(for: today)) ?? 0
        let hrv = (try? await hk.fetchHRV(for: today)) ?? 0
        let rhr = (try? await hk.fetchRestingHeartRate(for: today)) ?? 0
        let detail = try? await hk.fetchSleepDetail(for: today)
        let recovery = RecoveryEstimator.calculateRecovery(hrvMs: hrv, restingHR: rhr, sleepHours: sleepHours)

        sleep = SleepData(
            sleepHours: sleepHours, hrvMs: hrv, restingHR: rhr,
            recoveryScore: recovery, sleepDetail: detail
        )

        if let entries = try? await hk.fetchCycleHistory(days: 180) {
            let periods = CycleCalculations.groupIntoPeriods(entries)
            let avgLen = CycleCalculations.averageCycleLength(periods: periods)
            let day = CycleCalculations.currentCycleDay(periods: periods)
            let phase: String? = if let d = day {
                CycleCalculations.currentPhase(cycleDay: d, cycleLength: avgLen ?? 28)
            } else {
                nil
            }
            cycle = CycleData(
                currentCycleDay: day, currentPhase: phase,
                avgCycleLength: avgLen, periodCount: periods.count
            )
        }

        lastRefresh = today
    }
}
