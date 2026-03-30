import Foundation
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
    var currentWeight: Double? // kg (EMA)
    var weeklyRate: Double? // kg/week
    var dailyDeficit: Double? // kcal (from weight trend)
    var supplementsTaken: Int = 0
    var supplementsTotal: Int = 0
    var isHealthKitAvailable: Bool = false
    // Recovery
    var recoveryScore: Int = 0
    var recoveryLevel: RecoveryEstimator.DailyRecovery.Level = .red
    var hrvMs: Double = 0
    var restingHR: Double = 0

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

        // Load weight trend
        do {
            let entries = try database.fetchWeightEntries()
            let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
            if let trend = WeightTrendCalculator.calculateTrend(entries: input) {
                currentWeight = trend.currentEMA
                weeklyRate = trend.weeklyRateKg
                dailyDeficit = trend.estimatedDailyDeficit
            }
        } catch {
            Log.weightTrend.error("Failed to load weight trend: \(error.localizedDescription)")
        }

        // Load HealthKit data
        let hkService = HealthKitService.shared
        isHealthKitAvailable = await hkService.isAvailable

        if isHealthKitAvailable {
            do {
                let calories = try await hkService.fetchCaloriesBurned(for: Date())
                activeCalories = calories.active
                basalCalories = calories.basal
                caloriesBurned = calories.active + calories.basal

                steps = try await hkService.fetchSteps(for: Date())
                sleepHours = try await hkService.fetchSleepHours(for: Date())

                // Recovery
                hrvMs = try await hkService.fetchHRV(for: Date())
                restingHR = try await hkService.fetchRestingHeartRate(for: Date())
                let (score, level) = RecoveryEstimator.calculateRecovery(
                    hrvMs: hrvMs, restingHR: restingHR, sleepHours: sleepHours
                )
                recoveryScore = score
                recoveryLevel = level
            } catch {
                Log.healthKit.error("HealthKit fetch failed: \(error.localizedDescription)")
            }
        }
    }
}
