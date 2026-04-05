import Foundation

/// Caches async HealthKit data (sleep, cycle) so synchronous context builders can use it.
/// Refreshed when the AI chat opens. 5-minute TTL.
@MainActor @Observable
final class AIDataCache {
    static let shared = AIDataCache()

    struct SleepData: Sendable {
        let sleepHours: Double
        let hrvMs: Double
        let restingHR: Double
        let recoveryScore: Int
        let sleepDetail: HealthKitService.SleepDetail?
    }

    struct CycleData: Sendable {
        let currentCycleDay: Int?
        let currentPhase: String?
        let avgCycleLength: Int?
        let periodCount: Int
    }

    private(set) var sleep: SleepData?
    private(set) var cycle: CycleData?
    private var lastRefresh: Date?

    func refreshIfNeeded() async {
        if let last = lastRefresh, Date().timeIntervalSince(last) < 300 { return }
        await refresh()
    }

    func refresh() async {
        let hk = HealthKitService.shared
        let today = Date()

        // Sleep & Recovery
        let sleepHours = (try? await hk.fetchSleepHours(for: today)) ?? 0
        let hrv = (try? await hk.fetchHRV(for: today)) ?? 0
        let rhr = (try? await hk.fetchRestingHeartRate(for: today)) ?? 0
        let detail = try? await hk.fetchSleepDetail(for: today)
        let recovery = RecoveryEstimator.calculateRecovery(hrvMs: hrv, restingHR: rhr, sleepHours: sleepHours)

        sleep = SleepData(
            sleepHours: sleepHours,
            hrvMs: hrv,
            restingHR: rhr,
            recoveryScore: recovery,
            sleepDetail: detail
        )

        // Cycle
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
                currentCycleDay: day,
                currentPhase: phase,
                avgCycleLength: avgLen,
                periodCount: periods.count
            )
        }

        lastRefresh = today
    }
}
