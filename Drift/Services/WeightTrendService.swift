import Foundation

/// Centralized weight trend service. ALL callers use this instead of independently
/// fetching weight entries and calculating trends. Applies 90-day filter and
/// staleness guardrails consistently.
@MainActor
final class WeightTrendService {
    static let shared = WeightTrendService()

    // MARK: - Cached Trend Data

    /// Last calculated trend (90-day window, outliers removed).
    private(set) var trend: WeightTrendCalculator.WeightTrend?

    /// True if no weight logged in last 60 days — don't show trends.
    private(set) var isStale: Bool = true

    /// Latest weight entry (even if stale — for display purposes).
    private(set) var latestWeightKg: Double?

    // MARK: - Convenience Accessors

    /// EMA-smoothed trend weight (for calculations). Falls back to latest when stale.
    var trendWeight: Double? { isStale ? latestWeightKg : trend?.currentEMA }
    var weeklyRate: Double? { isStale ? nil : trend?.weeklyRateKg }
    var dailyDeficit: Double? { isStale ? nil : trend?.estimatedDailyDeficit }
    var weightChanges: WeightTrendCalculator.WeightChanges? { isStale ? nil : trend?.weightChanges }
    var projectedWeightKg: Double? {
        guard !isStale, let trend else { return nil }
        return trend.currentEMA + (trend.weeklyRateKg * 4.3) // ~30 days
    }
    var trendDirection: WeightTrendCalculator.TrendDirection? { isStale ? nil : trend?.trendDirection }

    // MARK: - Refresh

    /// Recalculate trend from DB. Call on app launch, after weight log, etc.
    func refresh() {
        let db = AppDatabase.shared
        let cal = Calendar.current
        let now = Date()

        // Fetch all entries for latestWeightKg (unfiltered)
        latestWeightKg = (try? db.fetchWeightEntries(from: nil))?.first?.weightKg

        // 90-day filter for trend calculation
        let cutoff = cal.date(byAdding: .day, value: -90, to: now)
        let cutoffStr = cutoff.map { DateFormatters.dateOnly.string(from: $0) }
        guard let entries = try? db.fetchWeightEntries(from: cutoffStr), !entries.isEmpty else {
            trend = nil
            isStale = true
            return
        }

        // Staleness check: most recent entry > 60 days ago?
        let sixtyDaysAgo = cal.date(byAdding: .day, value: -60, to: now) ?? now
        if let mostRecentDate = DateFormatters.dateOnly.date(from: entries.first!.date) {
            isStale = mostRecentDate < sixtyDaysAgo
        } else {
            isStale = true
        }

        // Calculate trend (outlier detection happens inside WeightTrendCalculator)
        let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
        trend = WeightTrendCalculator.calculateTrend(entries: input)
    }

    // MARK: - Custom Range (for algorithm preview)

    /// Calculate trend for a custom range + config. Not cached.
    func trendForRange(days: Int, config: WeightTrendCalculator.AlgorithmConfig? = nil) -> WeightTrendCalculator.WeightTrend? {
        let db = AppDatabase.shared
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let cutoffStr = cutoff.map { DateFormatters.dateOnly.string(from: $0) }
        guard let entries = try? db.fetchWeightEntries(from: cutoffStr), !entries.isEmpty else { return nil }
        let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
        if let config {
            return WeightTrendCalculator.calculateTrend(entries: input, config: config)
        }
        return WeightTrendCalculator.calculateTrend(entries: input)
    }

    /// All entries for the history list (unfiltered — shows full timeline).
    func allEntries() -> [WeightEntry] {
        (try? AppDatabase.shared.fetchWeightEntries(from: nil)) ?? []
    }
}
