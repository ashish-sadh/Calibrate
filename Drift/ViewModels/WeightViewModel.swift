import Foundation
import DriftCore
import GRDB
import Observation

@MainActor
@Observable
final class WeightViewModel {
    private let database: AppDatabase

    var entries: [WeightEntry] = []          // filtered by time range (for log + calorie overlay)
    var allEntries: [WeightEntry] = []       // ALL entries (for insights)
    /// Single source of truth for the weight trend (EMA + slope + deltas).
    /// Used by both the chart (scoped via `rangeStart` on the chart side)
    /// and `WeightInsightsView`. Was previously paired with a windowed
    /// `trend` used by the chart only — that reseeded the EMA at the
    /// leftmost visible entry's raw weight and produced a chart trajectory
    /// that contradicted the insight cards (see fix in WeightTabView).
    var fullTrend: WeightTrendCalculator.WeightTrend?
    var selectedTimeRange: TimeRange = .threeMonths
    var granularity: Granularity = .daily
    var weightUnit: WeightUnit = Preferences.weightUnit
    var goal: WeightGoal? = WeightGoal.load()

    // Calorie overlay (#669) — daily totals over the active chart range, plus
    // last-7-day tracking density used as the auto-on heuristic.
    var dailyCaloriesByDate: [String: Double] = [:]
    var daysWithCaloriesInLastWeek: Int = 0
    // Stored, not computed. Earlier version was a computed property reading
    // from UserDefaults via Preferences — but @Observable only tracks reads
    // of stored properties, so toggling did nothing in the UI (UserDefaults
    // write didn't trigger SwiftUI re-render). Stored property + sync to
    // Preferences in the setter gives both observability and persistence.
    // Initial value seeded from Preferences in resyncCaloriesOverlay() once
    // daysWithCaloriesInLastWeek loads.
    var showCaloriesOverlay: Bool = false

    /// Reload `showCaloriesOverlay` from Preferences using the current
    /// last-week tracking density as the default-when-unset basis.
    /// Call after `daysWithCaloriesInLastWeek` is loaded so the auto-on
    /// heuristic gets fresh inputs. Manual user toggle persists in
    /// UserDefaults and overrides the heuristic.
    func resyncCaloriesOverlay() {
        showCaloriesOverlay = Preferences.weightChartCaloriesEnabled(
            daysWithCaloriesInLastWeek: daysWithCaloriesInLastWeek
        )
    }

    /// Toggle the overlay. Updates the stored property (drives re-render via
    /// @Observable) and persists via Preferences (survives app restart, also
    /// pins the manual choice over the auto-on heuristic).
    func toggleCaloriesOverlay() {
        showCaloriesOverlay.toggle()
        Preferences.setWeightChartCaloriesEnabled(showCaloriesOverlay)
    }

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

            // Filter `entries` for the calorie overlay and the log list
            // below the chart. The chart itself reads `fullTrend.dataPoints`
            // and scopes visually via `rangeStart`.
            if let days = selectedTimeRange.days,
               let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) {
                let cutoffStr = DateFormatters.dateOnly.string(from: cutoff)
                entries = allEntries.filter { $0.date >= cutoffStr }
            } else {
                entries = allEntries
            }

            goal = WeightGoal.load()
            loadCalorieOverlay()
            Log.weightTrend.info("Loaded \(self.entries.count)/\(self.allEntries.count) entries")
        } catch {
            Log.weightTrend.error("Failed to load: \(error.localizedDescription)")
        }
    }

    private func loadCalorieOverlay() {
        let today = Date()
        let calendar = Calendar.current
        // entries is sorted by date DESCENDING (fetchWeightEntries orders
        // .desc), so first = newest, last = oldest. Earlier code used
        // entries.first as chartStart, which set it to today and limited
        // the calorie query to a single day — overlay always reported
        // "No calories logged in this range" for users with historical
        // data in older months. Use min(by:) to be sort-order-agnostic.
        let oldestEntryDate = entries.min(by: { $0.date < $1.date })?.date
        let chartStart = oldestEntryDate.flatMap { DateFormatters.dateOnly.date(from: $0) }
            ?? calendar.date(byAdding: .day, value: -7, to: today)
            ?? today
        let chartStartStr = DateFormatters.dateOnly.string(from: chartStart)
        let todayStr = DateFormatters.dateOnly.string(from: today)
        do {
            dailyCaloriesByDate = try database.fetchDailyCalories(from: chartStartStr, to: todayStr)
        } catch {
            dailyCaloriesByDate = [:]
            Log.weightTrend.error("Calorie overlay load failed: \(error.localizedDescription)")
        }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) ?? today
        let weekAgoStr = DateFormatters.dateOnly.string(from: weekAgo)
        let weekSlice = dailyCaloriesByDate.filter { $0.key >= weekAgoStr && $0.value > 0 }
        // Reach back to the DB if the chart range is shorter than 7 days.
        if weekAgoStr < chartStartStr {
            daysWithCaloriesInLastWeek = (try? database.fetchDailyCalories(from: weekAgoStr, to: todayStr).filter { $0.value > 0 }.count) ?? 0
        } else {
            daysWithCaloriesInLastWeek = weekSlice.count
        }
        // Re-evaluate the overlay default now that tracking density is known.
        // Manual user toggle (persisted in Preferences) wins; this only
        // affects users who haven't yet tapped the flame button.
        resyncCaloriesOverlay()
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
