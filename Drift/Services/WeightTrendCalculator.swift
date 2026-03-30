import Foundation

/// Pure-logic weight trend calculator. No side effects, highly testable.
///
/// ## Algorithm Overview
/// Uses Exponential Moving Average (EMA) for weight smoothing and linear regression
/// for rate-of-change estimation. Energy deficit is derived from the weight trend.
///
/// ## Adaptive TDEE approach (for reference)
/// Adaptive TDEE apps use BOTH food intake + weight trend to derive expenditure:
///   Expenditure = Intake - (Weight Change × Energy Density)
///   Deficit = Intake - Expenditure
/// This is more accurate because it captures metabolic adaptation.
///
/// ## Our approach (weight-trend only)
/// Since we may not have accurate food logging data, we estimate deficit from
/// weight change alone using a configurable energy density (kcal per kg of body change).
/// The 7700 kcal/kg rule overestimates early in a diet because:
/// - Week 1: ~4858 kcal/kg (glycogen + water loss)
/// - Weeks 4+: ~7200 kcal/kg (mostly fat)
/// - Long-term average: ~5500-7000 kcal/kg depending on body composition
///
/// ## Tunable Parameters (via AlgorithmConfig)
/// - `emaAlpha`: EMA smoothing factor (0.05-0.2). Lower = smoother, slower to react.
/// - `regressionWindowDays`: Days of EMA data for linear regression (14-28).
/// - `kcalPerKg`: Energy density of weight change (5500-7700).
/// - `maintainingThresholdKgPerWeek`: Threshold for "maintaining" classification.
///
enum WeightTrendCalculator {

    // MARK: - Configuration

    /// Tunable algorithm parameters. Adjust these to calibrate deficit estimates.
    struct AlgorithmConfig: Codable, Sendable {
        /// EMA smoothing factor. Higher = more responsive, noisier.
        /// - 0.05: Very smooth (half-life ~13 days). Good for noisy data.
        /// - 0.10: Balanced (half-life ~6.6 days). Default, same as Happy Scale.
        /// - 0.15: More responsive (half-life ~4.3 days). Good for consistent daily weighers.
        /// - 0.20: Very responsive (half-life ~3.1 days). Only if weighing daily + low variance.
        var emaAlpha: Double

        /// Number of days of EMA data to use for linear regression.
        /// Popular apps use ~20 days. Range: 14-28.
        /// Longer = more stable estimate, slower to detect changes.
        /// Shorter = faster to react, but noisier.
        var regressionWindowDays: Int

        /// Energy density of body weight change in kcal per kg.
        /// - 7700: Traditional "1 kg = 7700 kcal" (pure fat). Overestimates deficit.
        /// - 7000: Adjusted for mixed fat + lean loss. Good for extended diets.
        /// - 5500: Conservative. Accounts for water/glycogen in early dieting.
        /// - Custom: Set based on your experience. If Drift shows higher deficit
        ///   than expected, lower this value.
        var kcalPerKg: Double

        /// Weekly rate threshold (kg/week) below which we classify as "maintaining".
        var maintainingThresholdKgPerWeek: Double

        static let `default` = AlgorithmConfig(
            emaAlpha: 0.1,
            regressionWindowDays: 21,
            kcalPerKg: 6000, // Lower than 7700 for realistic weight loss
            maintainingThresholdKgPerWeek: 0.05
        )

        /// Conservative: smoother, lower energy density (conservative estimates)
        static let conservative = AlgorithmConfig(
            emaAlpha: 0.08,
            regressionWindowDays: 21,
            kcalPerKg: 5500,
            maintainingThresholdKgPerWeek: 0.05
        )

        /// Aggressive: more responsive, higher energy density
        static let responsive = AlgorithmConfig(
            emaAlpha: 0.15,
            regressionWindowDays: 14,
            kcalPerKg: 7700,
            maintainingThresholdKgPerWeek: 0.05
        )
    }

    // MARK: - Public Types

    struct WeightTrend: Sendable {
        let currentEMA: Double
        let previousEMA: Double
        let weeklyRateKg: Double
        let estimatedDailyDeficit: Double
        let trendDirection: TrendDirection
        let projection30Day: Double?
        let dataPoints: [WeightDataPoint]
        let weightChanges: WeightChanges
        let config: AlgorithmConfig // expose so UI can show what config was used
    }

    struct WeightDataPoint: Sendable {
        let date: Date
        let dateString: String
        let actualWeight: Double?
        let emaWeight: Double
    }

    struct WeightChanges: Sendable {
        let threeDay: Double?
        let sevenDay: Double?
        let fourteenDay: Double?
        let thirtyDay: Double?
        let ninetyDay: Double?
    }

    enum TrendDirection: Sendable {
        case losing, maintaining, gaining

        var displayText: String {
            switch self {
            case .losing: "Decrease"
            case .maintaining: "Stable"
            case .gaining: "Increase"
            }
        }

        var systemImage: String {
            switch self {
            case .losing: "arrow.down.right"
            case .maintaining: "arrow.right"
            case .gaining: "arrow.up.right"
            }
        }
    }

    // MARK: - Core Calculation

    static func calculateTrend(
        entries: [(date: String, weightKg: Double)],
        config: AlgorithmConfig = loadConfig()
    ) -> WeightTrend? {
        guard !entries.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let sorted = entries
            .compactMap { entry -> (date: Date, dateString: String, weight: Double)? in
                guard let date = formatter.date(from: entry.date) else { return nil }
                return (date, entry.date, entry.weightKg)
            }
            .sorted { $0.date < $1.date }

        guard !sorted.isEmpty else { return nil }

        // Calculate EMA with configurable alpha
        var dataPoints: [WeightDataPoint] = []
        var ema = sorted[0].weight

        for entry in sorted {
            ema = config.emaAlpha * entry.weight + (1 - config.emaAlpha) * ema
            dataPoints.append(WeightDataPoint(
                date: entry.date,
                dateString: entry.dateString,
                actualWeight: entry.weight,
                emaWeight: ema
            ))
        }

        guard let lastPoint = dataPoints.last else { return nil }
        let currentEMA = lastPoint.emaWeight
        let previousEMA = dataPoints.count >= 2 ? dataPoints[dataPoints.count - 2].emaWeight : currentEMA

        // Linear regression on configurable window
        guard let windowStart = Calendar.current.date(byAdding: .day, value: -config.regressionWindowDays, to: Date()) else { return nil }
        let recentPoints = dataPoints.filter { $0.date >= windowStart }

        let weeklyRateKg: Double
        if recentPoints.count >= 3 {
            weeklyRateKg = linearRegressionSlope(points: recentPoints) * 7
        } else if dataPoints.count >= 2 {
            let first = dataPoints.first ?? lastPoint
            let last = lastPoint
            let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1
            weeklyRateKg = days > 0 ? (last.emaWeight - first.emaWeight) / Double(days) * 7 : 0
        } else {
            weeklyRateKg = 0
        }

        // Deficit using configurable energy density
        let estimatedDailyDeficit = weeklyRateKg * config.kcalPerKg / 7

        let trendDirection: TrendDirection
        if weeklyRateKg < -config.maintainingThresholdKgPerWeek {
            trendDirection = .losing
        } else if weeklyRateKg > config.maintainingThresholdKgPerWeek {
            trendDirection = .gaining
        } else {
            trendDirection = .maintaining
        }

        let projection30Day: Double? = dataPoints.count >= 3
            ? currentEMA + (weeklyRateKg / 7 * 30)
            : nil

        return WeightTrend(
            currentEMA: currentEMA,
            previousEMA: previousEMA,
            weeklyRateKg: weeklyRateKg,
            estimatedDailyDeficit: estimatedDailyDeficit,
            trendDirection: trendDirection,
            projection30Day: projection30Day,
            dataPoints: dataPoints,
            weightChanges: calculateWeightChanges(dataPoints: dataPoints),
            config: config
        )
    }

    // MARK: - Config Persistence

    private static let configKey = "drift_algorithm_config"

    static func loadConfig() -> AlgorithmConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(AlgorithmConfig.self, from: data) else {
            return .default
        }
        return config
    }

    static func saveConfig(_ config: AlgorithmConfig) {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    // MARK: - Linear Regression

    static func linearRegressionSlope(points: [WeightDataPoint]) -> Double {
        guard points.count >= 2 else { return 0 }

        let referenceDate = points[0].date
        let n = Double(points.count)

        var sumX: Double = 0, sumY: Double = 0, sumXY: Double = 0, sumX2: Double = 0

        for point in points {
            let x = Double(Calendar.current.dateComponents([.day], from: referenceDate, to: point.date).day ?? 0)
            let y = point.emaWeight
            sumX += x; sumY += y; sumXY += x * y; sumX2 += x * x
        }

        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return 0 }
        return (n * sumXY - sumX * sumY) / denominator
    }

    // MARK: - Weight Changes

    static func calculateWeightChanges(dataPoints: [WeightDataPoint]) -> WeightChanges {
        guard let latest = dataPoints.last, let latestActual = latest.actualWeight else {
            return WeightChanges(threeDay: nil, sevenDay: nil, fourteenDay: nil, thirtyDay: nil, ninetyDay: nil)
        }

        func changeOverDays(_ days: Int) -> Double? {
            guard let target = Calendar.current.date(byAdding: .day, value: -days, to: latest.date) else { return nil }
            let closest = dataPoints.min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }
            guard let closest, closest.date != latest.date,
                  let closestActual = closest.actualWeight else { return nil }
            let daysDiff = abs(Calendar.current.dateComponents([.day], from: closest.date, to: target).day ?? 0)
            guard daysDiff <= 3 else { return nil } // allow 3 days tolerance for sparse data
            return latestActual - closestActual
        }

        return WeightChanges(
            threeDay: changeOverDays(3), sevenDay: changeOverDays(7),
            fourteenDay: changeOverDays(14), thirtyDay: changeOverDays(30),
            ninetyDay: changeOverDays(90)
        )
    }
}
