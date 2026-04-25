import Foundation
import DriftCore
import GRDB
import Observation

@MainActor
@Observable
final class WeightViewModel {
    private let database: AppDatabase

    var entries: [WeightEntry] = []          // filtered by time range (for chart + log)
    var allEntries: [WeightEntry] = []       // ALL entries (for insights)
    var trend: WeightTrendCalculator.WeightTrend?        // from filtered entries (chart)
    var fullTrend: WeightTrendCalculator.WeightTrend?    // from ALL entries (insights)
    var selectedTimeRange: TimeRange = .threeMonths
    var granularity: Granularity = .daily
    var weightUnit: WeightUnit = Preferences.weightUnit
    var goal: WeightGoal? = WeightGoal.load()

    /// Is the user trying to lose weight? Based on current weight vs target.
    var isLosing: Bool {
        if let goal {
            let currentKg = WeightTrendService.shared.latestWeightKg ?? goal.startWeightKg
            return goal.isLosing(currentWeightKg: currentKg)
        }
        return true // default assumption
    }

    /// Goal-aware color: is this change "good"?
    func changeColor(for change: Double) -> String {
        if isLosing {
            return change < -0.01 ? "deficit" : change > 0.01 ? "surplus" : "neutral"
        } else {
            return change > 0.01 ? "deficit" : change < -0.01 ? "surplus" : "neutral"
        }
    }

    enum TimeRange: String, CaseIterable, Sendable {
        case oneWeek = "1W"
        case oneMonth = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case oneYear = "1Y"
        case all = "All"

        var days: Int? {
            switch self {
            case .oneWeek: 7
            case .oneMonth: 30
            case .threeMonths: 90
            case .sixMonths: 180
            case .oneYear: 365
            case .all: nil
            }
        }
    }

    enum Granularity: String, CaseIterable, Sendable {
        case daily = "D"
        case weekly = "W"
    }

    struct WeeklyAverage: Sendable {
        let weekStart: Date
        let average: Double
        let count: Int
    }

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func loadEntries() {
        // Re-read unit preference on every load (fixes stale unit after Settings toggle)
        weightUnit = Preferences.weightUnit
        do {
            // Single DB query — filter in memory for the chart
            allEntries = try database.fetchWeightEntries(from: nil)
            let allInput = allEntries.map { (date: $0.date, weightKg: $0.weightKg) }
            fullTrend = WeightTrendCalculator.calculateTrend(entries: allInput)

            // Filter for chart time range (in memory, not a second DB call)
            if let days = selectedTimeRange.days,
               let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) {
                let cutoffStr = DateFormatters.dateOnly.string(from: cutoff)
                entries = allEntries.filter { $0.date >= cutoffStr }
            } else {
                entries = allEntries
            }
            let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
            trend = WeightTrendCalculator.calculateTrend(entries: input)

            goal = WeightGoal.load()
            Log.weightTrend.info("Loaded \(self.entries.count)/\(self.allEntries.count) entries")
        } catch {
            Log.weightTrend.error("Failed to load: \(error.localizedDescription)")
        }
    }

    // Milestone detection
    var milestoneMessage: String?

    func addWeight(value: Double, date: Date = Date()) {
        let kg = weightUnit.convertToKg(value)
        var entry = WeightEntry(date: DateFormatters.dateOnly.string(from: date), weightKg: kg, source: "manual")
        do {
            // Check for milestone BEFORE saving (compare against existing entries)
            let existingWeights = allEntries.map(\.weightKg)
            if !existingWeights.isEmpty {
                if isLosing {
                    if let currentMin = existingWeights.min(), kg < currentMin {
                        milestoneMessage = "New Low! \(String(format: "%.1f", weightUnit.convert(fromKg: kg))) \(weightUnit.displayName)"
                    }
                } else {
                    if let currentMax = existingWeights.max(), kg > currentMax {
                        milestoneMessage = "New High! \(String(format: "%.1f", weightUnit.convert(fromKg: kg))) \(weightUnit.displayName)"
                    }
                }
            }
            try database.saveWeightEntry(&entry)
            loadEntries()
        } catch {
            Log.weightTrend.error("Failed to save: \(error.localizedDescription)")
        }
    }

    func deleteWeight(id: Int64) {
        do {
            try database.deleteWeightEntry(id: id)
            loadEntries()
        } catch {
            Log.weightTrend.error("Failed to delete: \(error.localizedDescription)")
        }
    }

    func displayWeight(_ kg: Double) -> Double { weightUnit.convert(fromKg: kg) }

    // MARK: - Weekly Averages (from filtered entries)

    var weeklyAverages: [WeeklyAverage] {
        let calendar = Calendar.current
        var weeks: [Date: [Double]] = [:]
        for entry in entries {
            guard let date = DateFormatters.dateOnly.date(from: entry.date) else { continue }
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            weeks[weekStart, default: []].append(entry.weightKg)
        }
        return weeks.map { WeeklyAverage(weekStart: $0.key, average: $0.value.isEmpty ? 0 : $0.value.reduce(0, +) / Double($0.value.count), count: $0.value.count) }
            .sorted { $0.weekStart > $1.weekStart }
    }

}
