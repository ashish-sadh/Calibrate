import Foundation

/// Unified weight service — used by both UI views and AI tool calls.
/// Wraps AppDatabase weight methods + WeightTrendCalculator.
@MainActor
public enum WeightServiceAPI {

    // MARK: - Log

    /// Log a weight entry. Returns the saved entry.
    public static func logWeight(value: Double, unit: String) -> WeightEntry? {
        let kg = unit.lowercased().hasPrefix("kg") ? value : value / 2.20462
        guard kg > 10 && kg < 300 else { return nil } // Sanity check
        var entry = WeightEntry(date: DateFormatters.todayString, weightKg: kg, source: "manual")
        do {
            try AppDatabase.shared.saveWeightEntry(&entry)
            // Cross-domain pronoun pointer — powers "am I under goal" after a weight log. #241.
            let formatted = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
            ConversationState.shared.recordLastEntry(
                domain: .weight,
                summary: "\(formatted) \(unit.lowercased())"
            )
            return entry
        } catch {
            return nil
        }
    }

    // MARK: - Body Composition

    public static func latestBodyComposition() -> BodyComposition? {
        try? AppDatabase.shared.fetchLatestBodyComposition()
    }

    public static func saveBodyComposition(_ entry: inout BodyComposition) {
        try? AppDatabase.shared.saveBodyComposition(&entry)
    }

    /// Save a weight entry directly (when caller handles unit conversion).
    public static func saveWeightEntry(_ entry: inout WeightEntry) {
        try? AppDatabase.shared.saveWeightEntry(&entry)
    }

    public static func fetchBodyComposition() -> [BodyComposition] {
        (try? AppDatabase.shared.fetchBodyComposition()) ?? []
    }

    // MARK: - Trend (internal — exposed via describeTrend)

    static func getTrend() -> WeightTrendInfo? {
        let service = WeightTrendService.shared
        guard let trend = service.trend, !service.isStale else { return nil }
        let u = Preferences.weightUnit
        let latest = (try? AppDatabase.shared.fetchWeightEntries(from: nil))?.first
        return WeightTrendInfo(
            currentWeight: u.convert(fromKg: trend.currentEMA),
            unit: u.displayName,
            weeklyRate: u.convert(fromKg: trend.weeklyRateKg),
            direction: "\(trend.trendDirection)",
            sevenDayChange: trend.weightChanges.sevenDay.map { u.convert(fromKg: $0) },
            thirtyDayChange: trend.weightChanges.thirtyDay.map { u.convert(fromKg: $0) },
            bodyFatPct: latest?.bodyFatPct,
            bmi: latest?.bmi,
            waterPct: latest?.waterPct
        )
    }

    // MARK: - History

    public static func getHistory(days: Int = 30) -> [WeightEntry] {
        guard let entries = try? AppDatabase.shared.fetchWeightEntries() else { return [] }
        if days >= 365 { return entries }
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return entries }
        let cutoffStr = DateFormatters.dateOnly.string(from: cutoff)
        return entries.filter { $0.date >= cutoffStr }
    }

    // MARK: - Goal (internal — only used by describeTrend / future iOS code)

    static func getGoalProgress() -> GoalProgressInfo? {
        guard let goal = WeightGoal.load(),
              let entries = try? AppDatabase.shared.fetchWeightEntries(),
              let latest = entries.last else { return nil }
        let u = Preferences.weightUnit
        let progress = goal.progress(currentWeightKg: latest.weightKg)
        return GoalProgressInfo(
            currentWeight: u.convert(fromKg: latest.weightKg),
            targetWeight: u.convert(fromKg: goal.targetWeightKg),
            unit: u.displayName,
            progressPct: Int(progress * 100),
            monthsRemaining: goal.monthsToAchieve
        )
    }

    /// Natural language description of weight trend.
    public static func describeTrend() -> String {
        guard let trend = getTrend() else { return "No weight data yet." }
        var lines: [String] = []
        lines.append("Current: \(String(format: "%.1f", trend.currentWeight))\(trend.unit)")
        lines.append("Rate: \(String(format: "%+.1f", trend.weeklyRate))\(trend.unit)/week (\(trend.direction))")
        if let d7 = trend.sevenDayChange {
            lines.append("7-day change: \(String(format: "%+.1f", d7))\(trend.unit)")
        }
        if let d30 = trend.thirtyDayChange {
            lines.append("30-day change: \(String(format: "%+.1f", d30))\(trend.unit)")
        }
        if let bf = trend.bodyFatPct { lines.append("Body fat: \(String(format: "%.1f", bf))%") }
        if let bmi = trend.bmi { lines.append("BMI: \(String(format: "%.1f", bmi))") }
        if let water = trend.waterPct { lines.append("Water: \(String(format: "%.1f", water))%") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Internal Data Types (only consumed within DriftCore)

struct WeightTrendInfo: Sendable {
    let currentWeight: Double
    let unit: String
    let weeklyRate: Double
    let direction: String
    let sevenDayChange: Double?
    let thirtyDayChange: Double?
    let bodyFatPct: Double?
    let bmi: Double?
    let waterPct: Double?
}

struct GoalProgressInfo: Sendable {
    let currentWeight: Double
    let targetWeight: Double
    let unit: String
    let progressPct: Int
    let monthsRemaining: Int
}
