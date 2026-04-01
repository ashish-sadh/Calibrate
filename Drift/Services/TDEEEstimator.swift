import Foundation

/// Unified TDEE estimation. All views should use `TDEEEstimator.shared` for consistent calorie targets.
///
/// Sources (blended by confidence):
/// 1. Apple Health: 7-day avg of resting + active energy (passive, most reliable)
/// 2. Weight trend + food logs: intake - deficit (only when logging is consistent)
/// 3. Body weight × activity multiplier (Mifflin-St Jeor approximation)
///
/// All parameters are user-tunable via Algorithm Settings.
@MainActor
final class TDEEEstimator {
    static let shared = TDEEEstimator()

    // MARK: - Configuration

    struct TDEEConfig: Codable, Sendable {
        /// Activity multiplier for weight-based TDEE (kcal per kg bodyweight per day).
        var activityMultiplier: Double

        /// How much to trust Apple Health data (0.0–1.0).
        var appleHealthTrust: Double

        /// Manual TDEE adjustment in kcal (positive = add, negative = subtract).
        /// Applied on top of the computed estimate. Use when your wearable under/overestimates.
        var manualAdjustment: Double

        static let `default` = TDEEConfig(
            activityMultiplier: 29,
            appleHealthTrust: 1.0,
            manualAdjustment: 0
        )

        var loggingConsistencyThreshold: Double { 0.5 }

        var activityLabel: String {
            switch activityMultiplier {
            case ..<24: "Sedentary"
            case ..<27: "Lightly Active"
            case ..<30: "Moderately Active"
            case ..<33: "Very Active"
            default: "Athlete"
            }
        }
    }

    private static let configKey = "drift_tdee_config"

    static func loadConfig() -> TDEEConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(TDEEConfig.self, from: data) else {
            return .default
        }
        return config
    }

    static func saveConfig(_ config: TDEEConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        // Invalidate cache so next read uses new config
        shared.current = nil
        UserDefaults.standard.removeObject(forKey: shared.cacheKey)
    }

    // MARK: - Estimate

    struct Estimate: Codable, Sendable {
        let tdee: Double
        let source: Source
        let confidence: Confidence
        let timestamp: Date

        enum Source: String, Codable, Sendable {
            case appleHealth = "Apple Health"
            case weightTrend = "Weight Trend"
            case blended = "Blended"
            case bodyWeight = "Body Weight"
        }

        enum Confidence: String, Codable, Sendable {
            case high   // 7+ days of Apple Health or consistent logging
            case medium // some Apple Health or partial logging
            case low    // weight-based estimate only
        }

        var explanation: String {
            switch source {
            case .appleHealth:
                return "7-day average from Apple Health (resting + active energy)."
            case .weightTrend:
                return "Derived from your food logs and weight trend."
            case .blended:
                return "Blended from Apple Health energy and weight trend data."
            case .bodyWeight:
                return "Estimated from body weight and activity level. Log weight & food for better accuracy."
            }
        }
    }

    private let cacheKey = "drift_tdee_cache"

    /// Current best TDEE estimate. Cached for consistency within a session.
    private(set) var current: Estimate?

    /// Compute TDEE from all available sources. Call on app launch and periodically.
    /// Activity level always blends in at 30% when better data exists, 100% when alone.
    func refresh() async {
        let config = Self.loadConfig()
        let appleHealthTDEE = await fetchAppleHealth7DayAvg(config: config)
        let trendTDEE = fetchWeightTrendTDEE()
        let activityTDEE = fetchWeightFallback(config: config) ?? 2000
        let consistency = foodLoggingConsistency()

        let estimate: Estimate

        if let ah = appleHealthTDEE, let trend = trendTDEE, consistency >= config.loggingConsistencyThreshold {
            // All three: 50% AH + 35% trend + 15% activity
            let blended = ah * 0.50 + trend * 0.35 + activityTDEE * 0.15
            estimate = Estimate(tdee: blended, source: .blended,
                                confidence: .high, timestamp: Date())
        } else if let ah = appleHealthTDEE {
            // AH dominant + light activity: 85% AH + 15% activity
            let blended = ah * 0.85 + activityTDEE * 0.15
            estimate = Estimate(tdee: blended, source: .appleHealth,
                                confidence: .high, timestamp: Date())
        } else if let trend = trendTDEE, consistency >= config.loggingConsistencyThreshold {
            // Trend + activity: 70% trend + 30% activity
            let blended = trend * 0.7 + activityTDEE * 0.3
            estimate = Estimate(tdee: blended, source: .weightTrend,
                                confidence: .medium, timestamp: Date())
        } else {
            // Activity only: 100%
            estimate = Estimate(tdee: activityTDEE, source: .bodyWeight,
                                confidence: .low, timestamp: Date())
        }

        // Apply manual adjustment
        let adjusted = Estimate(tdee: max(800, estimate.tdee + config.manualAdjustment),
                                source: estimate.source, confidence: estimate.confidence, timestamp: estimate.timestamp)
        current = adjusted
        cache(adjusted)
        Log.app.info("TDEE: \(Int(adjusted.tdee)) kcal (\(adjusted.source.rawValue), adj \(Int(config.manualAdjustment)))")
    }

    /// Get cached or compute synchronously using all available non-async sources.
    /// Activity level always blends in (30% with trend data, 100% alone).
    func cachedOrSync() -> Estimate {
        if let current { return current }
        if let cached = loadCache() { self.current = cached; return cached }

        let config = Self.loadConfig()
        let trendTDEE = fetchWeightTrendTDEE()
        let activityTDEE = fetchWeightFallback(config: config) ?? 2000
        let consistency = foodLoggingConsistency()

        let baseTDEE: Double
        let source: Estimate.Source
        let confidence: Estimate.Confidence

        if let trend = trendTDEE, consistency >= config.loggingConsistencyThreshold {
            // Trend dominant: 70% trend + 30% activity
            baseTDEE = trend * 0.70 + activityTDEE * 0.30
            source = .weightTrend
            confidence = .medium
        } else {
            // Activity only: 100%
            baseTDEE = activityTDEE
            source = .bodyWeight
            confidence = .low
        }

        let est = Estimate(tdee: max(800, baseTDEE + config.manualAdjustment),
                           source: source, confidence: confidence, timestamp: Date())
        current = est; return est
    }

    // MARK: - Apple Health (smart multi-signal, 7-day average)

    /// Uses resting energy + the HIGHER of (active energy, step-derived estimate).
    /// iPhone often underreports active energy without a Watch. Steps are more reliable.
    /// Also adds ~5% for Thermic Effect of Food (TEF) which AH doesn't capture.
    private func fetchAppleHealth7DayAvg(config: TDEEConfig) async -> Double? {
        #if targetEnvironment(simulator)
        return nil
        #else
        let hk = HealthKitService.shared
        guard hk.isAvailable else { return nil }

        let db = AppDatabase.shared
        let weightKg = (try? db.fetchWeightEntries(from: nil))?.first?.weightKg ?? 70
        // Step calorie factor: ~0.04 kcal/step for 70kg person, scales with weight
        let kcalPerStep = 0.04 * weightKg / 70

        var dailyTotals: [Double] = []
        let calendar = Calendar.current

        for dayOffset in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }

            guard let burn = try? await hk.fetchCaloriesBurned(for: date) else { continue }
            let steps = (try? await hk.fetchSteps(for: date)) ?? 0

            let resting = burn.basal
            guard resting > 500 else { continue } // need valid resting data

            // Active: use the higher of AH active energy or step-derived estimate
            // iPhone without Watch severely underestimates active energy
            let stepDerivedActive = steps * kcalPerStep
            let active = max(burn.active, stepDerivedActive)

            let dayTotal = resting + active
            dailyTotals.append(dayTotal)
        }

        guard dailyTotals.count >= 3 else { return nil }
        let avg = dailyTotals.reduce(0, +) / Double(dailyTotals.count)
        return avg * config.appleHealthTrust
        #endif
    }

    // MARK: - Weight Trend + Food Logs (Adaptive TDEE)

    /// TDEE = avg intake - estimated deficit from weight trend.
    /// This is the adaptive TDEE approach: Expenditure = Intake - (WeightChange × EnergyDensity)
    private func fetchWeightTrendTDEE() -> Double? {
        let db = AppDatabase.shared
        guard let entries = try? db.fetchWeightEntries(from: nil), entries.count >= 7 else { return nil }
        let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
        guard let trend = WeightTrendCalculator.calculateTrend(entries: input) else { return nil }

        let deficit = trend.estimatedDailyDeficit // negative when losing
        let today = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today

        guard let avgIntake = try? db.averageDailyCalories(
            from: DateFormatters.dateOnly.string(from: twoWeeksAgo),
            to: DateFormatters.dateOnly.string(from: today)),
              avgIntake > 500 else { return nil }

        let tdee = avgIntake - deficit // deficit negative → TDEE = intake + |deficit|
        return tdee > 800 ? tdee : nil
    }

    // MARK: - Food Logging Consistency

    /// Returns 0.0–1.0: fraction of days with food logged in last 14 days.
    func foodLoggingConsistency() -> Double {
        let db = AppDatabase.shared
        let today = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today
        guard let count = try? db.daysWithFoodLogged(
            from: DateFormatters.dateOnly.string(from: twoWeeksAgo),
            to: DateFormatters.dateOnly.string(from: today)) else { return 0 }
        return Double(count) / 14.0
    }

    // MARK: - Body Weight Fallback

    private func fetchWeightFallback(config: TDEEConfig) -> Double? {
        let db = AppDatabase.shared
        guard let entries = try? db.fetchWeightEntries(from: nil), let latest = entries.first else { return nil }
        // Base 200 kcal accounts for fixed organ metabolism (brain, liver, kidneys)
        // that doesn't scale with weight. Prevents underestimation for lighter people.
        // At 53kg × 28 + 200 = 1,684. At 75kg × 28 + 200 = 2,300. Both reasonable.
        return 200 + latest.weightKg * config.activityMultiplier
    }

    // MARK: - Cache

    private func cache(_ estimate: Estimate) {
        if let data = try? JSONEncoder().encode(estimate) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func loadCache() -> Estimate? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let est = try? JSONDecoder().decode(Estimate.self, from: data) else { return nil }
        if Date().timeIntervalSince(est.timestamp) > 6 * 3600 { return nil }
        return est
    }
}
