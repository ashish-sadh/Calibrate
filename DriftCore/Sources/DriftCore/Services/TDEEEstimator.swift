import Foundation

/// Unified TDEE estimation using Base + Dampened Corrections.
///
/// Base = 2000 × √(weight/70) × activityFactor (always computed)
/// Then each available data source pulls the base toward observed reality:
///   + Mifflin correction (0.4 dampening) — when age/height/sex provided
///   + Apple Health correction (0.5 dampening) — when resting + active available
///   + Weight Trend correction (0.3 dampening) — when food logging consistent
@MainActor
public final class TDEEEstimator {
    public static let shared = TDEEEstimator()

    private init() {}

    // MARK: - Configuration

    public enum Sex: String, Codable, Sendable, CaseIterable {
        case male, female
        public var label: String { rawValue.capitalized }
    }

    public struct TDEEConfig: Codable, Sendable {
        public var activityMultiplier: Double
        public var appleHealthTrust: Double
        public var manualAdjustment: Double

        public var age: Int?
        public var heightCm: Double?
        public var sex: Sex?

        public var adaptiveTDEE: Double?
        public var adaptiveDataPoints: Int = 0

        init(activityMultiplier: Double, appleHealthTrust: Double, manualAdjustment: Double, age: Int? = nil, heightCm: Double? = nil, sex: Sex? = nil, adaptiveTDEE: Double? = nil, adaptiveDataPoints: Int = 0) {
            self.activityMultiplier = activityMultiplier
            self.appleHealthTrust = appleHealthTrust
            self.manualAdjustment = manualAdjustment
            self.age = age
            self.heightCm = heightCm
            self.sex = sex
            self.adaptiveTDEE = adaptiveTDEE
            self.adaptiveDataPoints = adaptiveDataPoints
        }

        public static let `default` = TDEEConfig(
            activityMultiplier: 29,
            appleHealthTrust: 1.0,
            manualAdjustment: 0
        )

        public var loggingConsistencyThreshold: Double { 0.5 }

        public var activityLabel: String {
            switch activityMultiplier {
            case ..<24: "Sedentary"
            case ..<27: "Lightly Active"
            case ..<30: "Moderately Active"
            case ..<33: "Very Active"
            default: "Athlete"
            }
        }

        public var hasMifflinProfile: Bool {
            age != nil && heightCm != nil && sex != nil
        }

        /// Map activity slider (22-36) to Mifflin activity factor (1.2-1.9)
        public var mifflinActivityFactor: Double {
            1.2 + (activityMultiplier - 22) * 0.05
        }
    }

    private static let configKey = "drift_tdee_config"

    public static func loadConfig() -> TDEEConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(TDEEConfig.self, from: data) else {
            return .default
        }
        return config
    }

    public static func saveConfig(_ config: TDEEConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
        shared.current = nil
        UserDefaults.standard.removeObject(forKey: shared.cacheKey)
    }

    // MARK: - Estimate

    public struct Estimate: Codable, Sendable {
        public let tdee: Double
        public let source: Source
        public let confidence: Confidence
        public let timestamp: Date
        public let activeSources: [String]
        public var adaptiveTDEE: Double?

        init(tdee: Double, source: Source, confidence: Confidence, timestamp: Date, activeSources: [String], adaptiveTDEE: Double? = nil) {
            self.tdee = tdee
            self.source = source
            self.confidence = confidence
            self.timestamp = timestamp
            self.activeSources = activeSources
            self.adaptiveTDEE = adaptiveTDEE
        }

        public enum Source: String, Codable, Sendable {
            case appleHealth = "Apple Health"
            case weightTrend = "Weight Trend"
            case blended = "Blended"
            case mifflin = "Mifflin-St Jeor"
            case bodyWeight = "Body Weight"
        }

        public enum Confidence: String, Codable, Sendable {
            case high, medium, low
        }

        public var explanation: String {
            switch source {
            case .appleHealth:
                return "Resting + active energy from Apple Health (7-day avg)."
            case .weightTrend:
                return "Derived from food logs and weight trend."
            case .blended:
                return "Blended from multiple data sources."
            case .mifflin:
                return "Calculated from your profile (age, height, sex)."
            case .bodyWeight:
                return "Estimated from body weight. Add profile or log data for better accuracy."
            }
        }
    }

    private let cacheKey = "drift_tdee_cache"
    public private(set) var current: Estimate?

    // MARK: - Core Formula

    /// Anchored at 2000 kcal for 70kg, sqrt scaling for diminishing returns.
    /// Soft-capped at 2700 kcal — without profile data, stay conservative.
    public nonisolated static func computeBase(weightKg: Double?, activityMultiplier: Double) -> Double {
        guard let w = weightKg, w > 0 else { return 2000 }
        let raw = 2000 * sqrt(w / 70) * (activityMultiplier / 29)
        let softCap = 2700.0
        guard raw > softCap else { return raw }
        return softCap + (raw - softCap) * 0.3
    }

    /// Compute Mifflin-St Jeor TDEE. Works with partial profile.
    public nonisolated static func computeMifflin(weightKg: Double, config: TDEEConfig) -> (tdee: Double, confidence: Double)? {
        guard config.age != nil || config.heightCm != nil || config.sex != nil else { return nil }

        let age = Double(config.age ?? 30)
        let height = config.heightCm ?? 170

        let bmr: Double
        if let sex = config.sex {
            switch sex {
            case .male:   bmr = 10 * weightKg + 6.25 * height - 5 * age + 5
            case .female: bmr = 10 * weightKg + 6.25 * height - 5 * age - 161
            }
        } else {
            let maleBMR = 10 * weightKg + 6.25 * height - 5 * age + 5
            let femaleBMR = 10 * weightKg + 6.25 * height - 5 * age - 161
            bmr = (maleBMR + femaleBMR) / 2
        }

        var fieldsProvided = 0.0
        if config.age != nil { fieldsProvided += 1 }
        if config.heightCm != nil { fieldsProvided += 1 }
        if config.sex != nil { fieldsProvided += 1 }
        let confidence = fieldsProvided / 3.0

        return (bmr * config.mifflinActivityFactor, confidence)
    }

    // MARK: - Refresh (async — uses Apple Health via DriftPlatform.health)

    public func refresh() async {
        let config = Self.loadConfig()
        let weightKg = WeightTrendService.shared.latestWeightKg

        var tdee = Self.computeBase(weightKg: weightKg, activityMultiplier: config.activityMultiplier)
        var sources: [String] = weightKg != nil ? ["Weight"] : ["Default"]
        var bestSource: Estimate.Source = weightKg != nil ? .bodyWeight : .bodyWeight

        if let w = weightKg, let (mifflin, confidence) = Self.computeMifflin(weightKg: w, config: config) {
            tdee += (mifflin - tdee) * 0.4 * confidence
            sources.append("Profile\(confidence < 1 ? " (partial)" : "")")
            bestSource = .mifflin
        }

        let ahTDEE = await fetchAppleHealth7DayAvg(config: config)
        if let ah = ahTDEE {
            tdee += (ah - tdee) * 0.5
            sources.append("Apple Health")
            bestSource = sources.count >= 3 ? .blended : .appleHealth
        }

        let trendTDEE = fetchWeightTrendTDEE()
        let consistency = foodLoggingConsistency()
        if let trend = trendTDEE, consistency >= config.loggingConsistencyThreshold {
            tdee += (trend - tdee) * 0.3
            sources.append("Weight Trend")
            bestSource = .blended
        }

        // Adaptive TDEE: DISABLED — caused dangerous drops.
        resetAdaptiveIfNeeded()

        tdee = max(1200, tdee + config.manualAdjustment)

        let confidence: Estimate.Confidence = sources.count >= 3 ? .high : sources.count >= 2 ? .medium : .low
        let estimate = Estimate(tdee: tdee, source: bestSource, confidence: confidence,
                                timestamp: Date(), activeSources: sources, adaptiveTDEE: nil)
        current = estimate
        cache(estimate)
        Log.app.info("TDEE: \(Int(tdee)) kcal (\(sources.joined(separator: "+")))")
    }

    // MARK: - Sync path (no Apple Health)

    public func cachedOrSync() -> Estimate {
        if let current { return current }
        if let cached = loadCache() { self.current = cached; return cached }

        let config = Self.loadConfig()
        let weightKg = WeightTrendService.shared.latestWeightKg

        var tdee = Self.computeBase(weightKg: weightKg, activityMultiplier: config.activityMultiplier)
        var sources: [String] = weightKg != nil ? ["Weight"] : ["Default"]
        var bestSource: Estimate.Source = .bodyWeight

        if let w = weightKg, let (mifflin, confidence) = Self.computeMifflin(weightKg: w, config: config) {
            tdee += (mifflin - tdee) * 0.4 * confidence
            sources.append("Profile\(confidence < 1 ? " (partial)" : "")")
            bestSource = .mifflin
        }

        let trendTDEE = fetchWeightTrendTDEE()
        let consistency = foodLoggingConsistency()
        if let trend = trendTDEE, consistency >= config.loggingConsistencyThreshold {
            tdee += (trend - tdee) * 0.3
            sources.append("Weight Trend")
            bestSource = .blended
        }

        tdee = max(1200, tdee + config.manualAdjustment)

        let confidence: Estimate.Confidence = sources.count >= 2 ? .medium : .low
        let est = Estimate(tdee: tdee, source: bestSource, confidence: confidence,
                           timestamp: Date(), activeSources: sources, adaptiveTDEE: nil)
        current = est; return est
    }

    // MARK: - Apple Health (smart multi-signal, 7-day average)

    private func fetchAppleHealth7DayAvg(config: TDEEConfig) async -> Double? {
        guard let hk = DriftPlatform.health, hk.isAvailable else { return nil }

        let weightKg = WeightTrendService.shared.latestWeightKg ?? 70
        let kcalPerStep = 0.04 * max(1.0, weightKg / 70)

        var dailyTotals: [Double] = []
        let calendar = Calendar.current

        for dayOffset in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
            guard let burn = try? await hk.fetchCaloriesBurned(for: date) else { continue }
            let steps = (try? await hk.fetchSteps(for: date)) ?? 0

            let resting = burn.basal
            guard resting > 500 else { continue }

            let stepDerivedActive = steps * kcalPerStep
            let active = max(burn.active, stepDerivedActive)
            dailyTotals.append(resting + active)
        }

        guard dailyTotals.count >= 3 else { return nil }
        let avg = dailyTotals.reduce(0, +) / Double(dailyTotals.count)
        return avg * config.appleHealthTrust
    }

    // MARK: - Weight Trend + Food Logs (Adaptive TDEE)

    private func fetchWeightTrendTDEE() -> Double? {
        guard let trend = WeightTrendService.shared.trend else { return nil }
        guard !WeightTrendService.shared.isStale else { return nil }

        let deficit = trend.estimatedDailyDeficit
        let today = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today

        guard let avgIntake = try? AppDatabase.shared.averageDailyCalories(
            from: DateFormatters.dateOnly.string(from: twoWeeksAgo),
            to: DateFormatters.dateOnly.string(from: today)),
              avgIntake > 500 else { return nil }

        let tdee = avgIntake - deficit
        return tdee > 800 ? tdee : nil
    }

    /// Clears stored adaptive state from the broken v1 implementation.
    private func resetAdaptiveIfNeeded() {
        var config = Self.loadConfig()
        if config.adaptiveTDEE != nil || config.adaptiveDataPoints > 0 {
            config.adaptiveTDEE = nil
            config.adaptiveDataPoints = 0
            Self.saveConfig(config)
        }
    }

    // MARK: - Food Logging Consistency

    public func foodLoggingConsistency() -> Double {
        let db = AppDatabase.shared
        let today = Date()
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: today) ?? today
        guard let count = try? db.daysWithFoodLogged(
            from: DateFormatters.dateOnly.string(from: twoWeeksAgo),
            to: DateFormatters.dateOnly.string(from: today)) else { return 0 }
        return Double(count) / 14.0
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
