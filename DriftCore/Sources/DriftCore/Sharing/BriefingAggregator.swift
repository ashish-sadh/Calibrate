import Foundation

/// Turns a window of local data into the handful of averages a coach actually
/// uses. Pure and injectable — it takes arrays, never touches the database or
/// HealthKit itself, so it is Tier-0 testable and works identically on both
/// platforms.
///
/// Sleep is passed in rather than read here because it lives in HealthKit on
/// iOS and has no source at all on Android yet; the same shape
/// `BehaviorInsightService` already uses.
public enum BriefingAggregator {

    /// A day's nutrition as the aggregator wants it. Days with no food logged
    /// are simply absent — averaging a skipped day as zero would tell a coach
    /// the client ate nothing, when the truth is they didn't log.
    public struct NutritionDay: Sendable, Equatable {
        public var date: Date
        public var calories: Double
        public var proteinG: Double
        public init(date: Date, calories: Double, proteinG: Double) {
            self.date = date
            self.calories = calories
            self.proteinG = proteinG
        }
    }

    /// Build the metrics payload, including ONLY the categories the client
    /// opted into for this coach. Filtering happens here, before the network,
    /// so a withheld category leaves no trace in the request at all.
    public static func metrics(level: BriefingSharingLevel,
                               windowDays: Int = 7,
                               sleepHours: [(date: Date, hours: Double)] = [],
                               nutrition: [NutritionDay] = [],
                               weights: [(date: Date, lbs: Double)] = [],
                               proteinTargetG: Double? = nil,
                               workoutsCompleted: Int? = nil,
                               scans: [DEXAScan] = [],
                               daysLogged: Int? = nil,
                               trendSleep: [(date: Date, hours: Double)] = [],
                               trendNutrition: [NutritionDay] = [],
                               trendWeights: [(date: Date, lbs: Double)] = [],
                               records: [PersonalRecord] = []) -> BriefingMetrics {
        var metrics = BriefingMetrics()
        metrics.windowDays = windowDays

        // Adherence rides with any sharing at all — it's the number that makes
        // the rest worth reading, and it's derived from workouts the coach can
        // already see.
        metrics.workoutsCompleted = workoutsCompleted

        if level.contains(.sleep) {
            metrics.avgSleepHours = average(sleepHours.map(\.hours))
        }
        if level.contains(.nutrition) {
            metrics.avgCalories = average(nutrition.map(\.calories))
            metrics.avgProteinG = average(nutrition.map(\.proteinG))
            metrics.proteinTargetG = proteinTargetG
            metrics.daysLogged = daysLogged
            metrics.caloriesSeries = weeklyAverages(
                trendNutrition.map { (date: $0.date, value: $0.calories) })
        }
        if level.contains(.weight) {
            metrics.weightChangeLbs = change(weights)
            metrics.weightSeries = weeklyAverages(
                trendWeights.map { (date: $0.date, value: $0.lbs) })
        }
        if level.contains(.sleep) {
            metrics.sleepSeries = weeklyAverages(
                trendSleep.map { (date: $0.date, value: $0.hours) })
        }
        if level.contains(.bodyComp) {
            applyBodyComp(&metrics, scans: scans)
        }
        if level.contains(.strength) {
            metrics.records = records.isEmpty ? nil : records
        }
        return metrics
    }

    /// Bucket daily values into WEEKLY AVERAGES, oldest first. Weekly is the
    /// consent boundary, not a display choice — see `WeeklyPoint`. Weeks with
    /// no data are skipped rather than zeroed, and a lone week is dropped by
    /// `BriefingMetrics.trends` because one point is not a trend.
    static func weeklyAverages(_ samples: [(date: Date, value: Double)],
                               calendar: Calendar = .current) -> [WeeklyPoint]? {
        guard !samples.isEmpty else { return nil }
        var buckets: [Date: [Double]] = [:]
        for sample in samples {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: sample.date)?.start
            else { continue }
            buckets[week, default: []].append(sample.value)
        }
        let points = buckets.keys.sorted().compactMap { week -> WeeklyPoint? in
            guard let mean = average(buckets[week] ?? []) else { return nil }
            return WeeklyPoint(weekStart: DateFormatters.dateOnly.string(from: week),
                               value: (mean * 10).rounded() / 10)
        }
        return points.isEmpty ? nil : points
    }

    /// Latest scan's headline numbers + change since the previous scan.
    /// Deltas only exist when BOTH scans carry the value — a delta against
    /// nothing reads like progress that never happened.
    static func applyBodyComp(_ metrics: inout BriefingMetrics, scans: [DEXAScan]) {
        let ordered = scans.sorted { $0.scanDate > $1.scanDate }
        guard let latest = ordered.first else { return }
        let previous = ordered.dropFirst().first

        metrics.scanDate = latest.scanDate
        metrics.bodyFatPct = latest.bodyFatPct
        if let now = latest.bodyFatPct, let then = previous?.bodyFatPct {
            metrics.bodyFatDeltaPct = now - then
        }
        let kgToLbs = 2.20462
        metrics.leanMassLbs = latest.leanMassKg.map { $0 * kgToLbs }
        if let now = latest.leanMassKg, let then = previous?.leanMassKg {
            metrics.leanMassDeltaLbs = (now - then) * kgToLbs
        }
    }

    /// Nil for an empty set, so "no data" stays distinguishable from zero.
    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Net movement across the window: last minus first, chronologically. A
    /// single weigh-in has no trend to report, so it yields nil rather than 0 —
    /// "no change" is a claim we haven't earned from one data point.
    static func change(_ weights: [(date: Date, lbs: Double)]) -> Double? {
        guard weights.count >= 2 else { return nil }
        let sorted = weights.sorted { $0.date < $1.date }
        return sorted.last!.lbs - sorted.first!.lbs
    }
}
