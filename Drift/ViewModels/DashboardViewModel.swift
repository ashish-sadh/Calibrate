import Foundation
import DriftCore
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    private let database: AppDatabase

    var todayNutrition: DailyNutrition = .zero
    var caloriesBurned: Double = 0
    var activeCalories: Double = 0
    var basalCalories: Double = 0
    var steps: Double = 0
    var sleepHours: Double = 0
    var trendWeight: Double?   // kg (EMA-smoothed — for TDEE/macro calcs, not direct display)
    var latestWeight: Double?  // kg (raw latest entry — what user sees everywhere)
    var weeklyRate: Double? // kg/week
    var dailyDeficit: Double? // kcal (from weight trend)
    var avgDailyIntake: Double = 0 // 14-day avg calories eaten
    var foodLogConsistency: Double = 0 // 0.0-1.0 (fraction of last 14 days with food logged)
    var supplementsTaken: Int = 0
    var supplementsTotal: Int = 0
    var isHealthKitAvailable: Bool = false
    // Apple Health Workouts
    var todayWorkouts: [HealthWorkout] = []
    var recentAppleWorkoutDates: [Date] = []
    // Recovery
    var recoveryScore: Int = 0
    var hrvMs: Double = 0
    var restingHR: Double = 0

    var behaviorInsights: [BehaviorInsight] = []
    var proactiveAlerts: [BehaviorInsight] = []
    var isLoading = false

    var calorieBalance: Double {
        todayNutrition.calories - caloriesBurned
    }

    var calorieBalanceText: String {
        let balance = Int(calorieBalance)
        if balance < 0 {
            return "\(balance) kcal deficit"
        } else if balance > 0 {
            return "+\(balance) kcal surplus"
        }
        return "Balanced"
    }

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func loadToday() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let today = DateFormatters.todayString

        // Load nutrition from local DB
        do {
            todayNutrition = try database.fetchDailyNutrition(for: today)
        } catch {
            Log.app.error("Failed to load nutrition: \(error.localizedDescription)")
        }

        // Load supplements
        do {
            let supplements = try database.fetchActiveSupplements()
            let logs = try database.fetchSupplementLogs(for: today)
            supplementsTotal = supplements.count
            supplementsTaken = logs.filter(\.taken).count
        } catch {
            Log.supplements.error("Failed to load supplements: \(error.localizedDescription)")
        }

        // Sync latest weight from Apple Health
        #if !targetEnvironment(simulator)
        do {
            let synced = try await HealthKitService.shared.syncWeight()
            if synced > 0 { Log.healthKit.info("Dashboard synced \(synced) weight entries") }
        } catch {
            Log.healthKit.error("Dashboard weight sync failed: \(error.localizedDescription)")
        }
        #endif

        // Load weight trend from centralized service
        let trendService = WeightTrendService.shared
        trendService.refresh()
        trendWeight = trendService.trendWeight
        latestWeight = trendService.latestWeightKg
        weeklyRate = trendService.weeklyRate
        dailyDeficit = trendService.dailyDeficit

        // Load 14-day avg daily intake + consistency (for energy balance bar)
        do {
            let today = Date()
            let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today
            let fromStr = DateFormatters.dateOnly.string(from: twoWeeksAgo)
            let toStr = DateFormatters.dateOnly.string(from: today)
            avgDailyIntake = try database.averageDailyCalories(from: fromStr, to: toStr)
            let daysLogged = try database.daysWithFoodLogged(from: fromStr, to: toStr)
            foodLogConsistency = Double(daysLogged) / 14.0
        } catch {
            Log.app.error("Failed to load avg intake: \(error.localizedDescription)")
        }

        // Load HealthKit data
        let hkService = HealthKitService.shared
        isHealthKitAvailable = await hkService.isAvailable

        var sleepHist: [(date: Date, hours: Double)] = []

        if isHealthKitAvailable {
            // Fetch each independently — one failure doesn't block others
            if let cal = try? await hkService.fetchCaloriesBurned(for: Date()) {
                activeCalories = cal.active
                basalCalories = cal.basal
                caloriesBurned = cal.active + cal.basal
            }
            steps = (try? await hkService.fetchSteps(for: Date())) ?? 0
            todayWorkouts = (try? await hkService.fetchWorkouts(for: Date())) ?? []
            recentAppleWorkoutDates = ((try? await hkService.fetchRecentWorkouts(days: 7)) ?? []).map { $0.date }
            sleepHours = (try? await hkService.fetchSleepHours(for: Date())) ?? 0
            hrvMs = (try? await hkService.fetchHRV(for: Date())) ?? 0
            restingHR = (try? await hkService.fetchRestingHeartRate(for: Date())) ?? 0

            // Build baselines with 14-day windows (must match SleepRecoveryView for consistent scores)
            let hrvHist = (try? await hkService.fetchHRVHistory(days: 14)) ?? []
            let rhrHist = (try? await hkService.fetchRestingHeartRateHistory(days: 14)) ?? []
            let sleepHist14 = (try? await hkService.fetchSleepHistory(days: 14)) ?? []
            let respHist = (try? await hkService.fetchRespiratoryRateHistory(days: 14)) ?? []
            let baselines = RecoveryEstimator.calculateBaselines(
                hrvHistory: hrvHist, rhrHistory: rhrHist,
                respHistory: respHist, sleepHistory: sleepHist14)
            // 30-day sleep for behavior insights (needs longer window)
            sleepHist = (try? await hkService.fetchSleepHistory(days: 30)) ?? []

            recoveryScore = RecoveryEstimator.calculateRecovery(
                hrvMs: hrvMs, restingHR: restingHR, sleepHours: sleepHours,
                baselines: baselines
            )
        }

        // Compute behavior insights (after HealthKit so sleep data is available)
        behaviorInsights = BehaviorInsightService.computeInsights(sleepHistory: sleepHist)

        // Only update alerts if content changed — loadToday() fires frequently (appear, 3min loop,
        // pull-to-refresh) and unchanged alerts should not re-trigger SwiftUI diffing/animation.
        let newAlerts = BehaviorInsightService.computeProactiveAlerts(recentAppleWorkouts: recentAppleWorkoutDates)
        if newAlerts.map(\.title) != proactiveAlerts.map(\.title) {
            proactiveAlerts = newAlerts
        }
    }
}
