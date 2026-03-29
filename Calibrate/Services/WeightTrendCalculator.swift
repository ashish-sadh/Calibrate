import Foundation

/// Pure-logic weight trend calculator. No side effects, highly testable.
/// Uses Exponential Moving Average (EMA) and linear regression
/// to compute weight trends and estimated caloric deficit/surplus.
enum WeightTrendCalculator {

    // MARK: - Public Types

    struct WeightTrend: Sendable {
        let currentEMA: Double              // kg
        let previousEMA: Double             // kg
        let weeklyRateKg: Double            // kg/week (negative = losing)
        let estimatedDailyDeficit: Double    // kcal (negative = deficit)
        let trendDirection: TrendDirection
        let projection30Day: Double?        // kg, nil if insufficient data
        let dataPoints: [WeightDataPoint]
        let weightChanges: WeightChanges
    }

    struct WeightDataPoint: Sendable {
        let date: Date
        let dateString: String
        let actualWeight: Double?           // kg, nil if no measurement
        let emaWeight: Double               // kg
    }

    struct WeightChanges: Sendable {
        let threeDay: Double?    // kg change
        let sevenDay: Double?
        let fourteenDay: Double?
        let thirtyDay: Double?
        let ninetyDay: Double?
    }

    enum TrendDirection: Sendable {
        case losing
        case maintaining
        case gaining

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

    // MARK: - Constants

    /// EMA smoothing factor. 0.1 = today's weight contributes 10%.
    /// Same approach as Hacker's Diet / MacroFactor / Happy Scale.
    static let alpha: Double = 0.1

    /// kcal per kg of body weight change.
    static let kcalPerKg: Double = 7700

    /// Threshold for "maintaining" vs "losing/gaining" in kg/week.
    static let maintainingThreshold: Double = 0.05

    // MARK: - Core Calculation

    /// Calculate the full weight trend from a list of weight entries.
    /// Entries must have `date` in "YYYY-MM-DD" format and `weightKg`.
    static func calculateTrend(
        entries: [(date: String, weightKg: Double)]
    ) -> WeightTrend? {
        guard !entries.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Sort by date ascending
        let sorted = entries
            .compactMap { entry -> (date: Date, dateString: String, weight: Double)? in
                guard let date = formatter.date(from: entry.date) else { return nil }
                return (date, entry.date, entry.weightKg)
            }
            .sorted { $0.date < $1.date }

        guard !sorted.isEmpty else { return nil }

        // Calculate EMA
        var dataPoints: [WeightDataPoint] = []
        var ema = sorted[0].weight

        for entry in sorted {
            ema = alpha * entry.weight + (1 - alpha) * ema
            dataPoints.append(WeightDataPoint(
                date: entry.date,
                dateString: entry.dateString,
                actualWeight: entry.weight,
                emaWeight: ema
            ))
        }

        let currentEMA = dataPoints.last!.emaWeight
        let previousEMA = dataPoints.count >= 2 ? dataPoints[dataPoints.count - 2].emaWeight : currentEMA

        // Calculate weekly rate via linear regression on last 14 days of EMA
        let fourteenDaysAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date())!
        let recentPoints = dataPoints.filter { $0.date >= fourteenDaysAgo }

        let weeklyRateKg: Double
        if recentPoints.count >= 3 {
            weeklyRateKg = linearRegressionSlope(points: recentPoints) * 7
        } else if dataPoints.count >= 2 {
            let first = dataPoints.first!
            let last = dataPoints.last!
            let days = Calendar.current.dateComponents([.day], from: first.date, to: last.date).day ?? 1
            weeklyRateKg = days > 0 ? (last.emaWeight - first.emaWeight) / Double(days) * 7 : 0
        } else {
            weeklyRateKg = 0
        }

        let estimatedDailyDeficit = weeklyRateKg * kcalPerKg / 7

        let trendDirection: TrendDirection
        if weeklyRateKg < -maintainingThreshold {
            trendDirection = .losing
        } else if weeklyRateKg > maintainingThreshold {
            trendDirection = .gaining
        } else {
            trendDirection = .maintaining
        }

        // 30-day projection
        let projection30Day: Double?
        if dataPoints.count >= 3 {
            projection30Day = currentEMA + (weeklyRateKg / 7 * 30)
        } else {
            projection30Day = nil
        }

        // Weight changes at various intervals
        let weightChanges = calculateWeightChanges(dataPoints: dataPoints)

        return WeightTrend(
            currentEMA: currentEMA,
            previousEMA: previousEMA,
            weeklyRateKg: weeklyRateKg,
            estimatedDailyDeficit: estimatedDailyDeficit,
            trendDirection: trendDirection,
            projection30Day: projection30Day,
            dataPoints: dataPoints,
            weightChanges: weightChanges
        )
    }

    // MARK: - Linear Regression

    /// Compute the slope of a linear regression on EMA weight values.
    /// Returns slope in kg/day.
    static func linearRegressionSlope(points: [WeightDataPoint]) -> Double {
        guard points.count >= 2 else { return 0 }

        let referenceDate = points[0].date
        let n = Double(points.count)

        var sumX: Double = 0
        var sumY: Double = 0
        var sumXY: Double = 0
        var sumX2: Double = 0

        for point in points {
            let x = Double(Calendar.current.dateComponents([.day], from: referenceDate, to: point.date).day ?? 0)
            let y = point.emaWeight
            sumX += x
            sumY += y
            sumXY += x * y
            sumX2 += x * x
        }

        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return 0 }

        return (n * sumXY - sumX * sumY) / denominator
    }

    // MARK: - Weight Changes

    static func calculateWeightChanges(dataPoints: [WeightDataPoint]) -> WeightChanges {
        guard let latest = dataPoints.last else {
            return WeightChanges(threeDay: nil, sevenDay: nil, fourteenDay: nil, thirtyDay: nil, ninetyDay: nil)
        }

        func changeOverDays(_ days: Int) -> Double? {
            let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: latest.date)!
            // Find the closest data point to the target date
            let closest = dataPoints.min(by: { a, b in
                abs(a.date.timeIntervalSince(targetDate)) < abs(b.date.timeIntervalSince(targetDate))
            })
            guard let closest, closest.date != latest.date else { return nil }
            // Only use if within 2 days of target
            let daysDiff = abs(Calendar.current.dateComponents([.day], from: closest.date, to: targetDate).day ?? 0)
            guard daysDiff <= 2 else { return nil }
            return latest.emaWeight - closest.emaWeight
        }

        return WeightChanges(
            threeDay: changeOverDays(3),
            sevenDay: changeOverDays(7),
            fourteenDay: changeOverDays(14),
            thirtyDay: changeOverDays(30),
            ninetyDay: changeOverDays(90)
        )
    }
}
