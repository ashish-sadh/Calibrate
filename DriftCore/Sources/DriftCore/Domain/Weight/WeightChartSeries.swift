import Foundation

/// Builds the two plotted series for the Body-tab weight chart from the trend
/// calculator's output — extracted from `WeightChartView` so the mapping is
/// Tier-0 testable (#932): every scale reading lands on the raw series at its
/// converted value, every day carries its EMA, and the weekly view averages
/// within calendar weeks.
public enum WeightChartSeries {

    public struct Point: Equatable, Sendable {
        public let date: Date
        /// Raw scale reading in display units — nil on days without a weigh-in.
        public let actual: Double?
        /// Smoothed (EMA) trend in display units.
        public let ema: Double

        public init(date: Date, actual: Double?, ema: Double) {
            self.date = date
            self.actual = actual
            self.ema = ema
        }
    }

    /// One point per calculator day, converted to display units.
    public static func daily(
        _ points: [WeightTrendCalculator.WeightDataPoint], unit: WeightUnit
    ) -> [Point] {
        points.map {
            Point(date: $0.date,
                  actual: $0.actualWeight.map { unit.convert(fromKg: $0) },
                  ema: unit.convert(fromKg: $0.emaWeight))
        }
    }

    /// Calendar-week aggregation: average of the week's actual weigh-ins
    /// (nil when the week has none) and average EMA, anchored to week start.
    public static func weekly(
        _ points: [WeightTrendCalculator.WeightDataPoint], unit: WeightUnit,
        calendar: Calendar = .current
    ) -> [Point] {
        var weeks: [Date: (actuals: [Double], emas: [Double])] = [:]
        for p in points {
            let ws = calendar.dateInterval(of: .weekOfYear, for: p.date)?.start ?? p.date
            if let a = p.actualWeight { weeks[ws, default: ([], [])].actuals.append(a) }
            weeks[ws, default: ([], [])].emas.append(p.emaWeight)
        }
        return weeks.sorted { $0.key < $1.key }.map { ws, data in
            let avgA = data.actuals.isEmpty ? nil
                : unit.convert(fromKg: data.actuals.reduce(0, +) / Double(data.actuals.count))
            let avgE = data.emas.isEmpty ? 0
                : unit.convert(fromKg: data.emas.reduce(0, +) / Double(data.emas.count))
            return Point(date: ws, actual: avgA, ema: avgE)
        }
    }
}
