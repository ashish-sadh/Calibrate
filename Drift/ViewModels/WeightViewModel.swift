import Foundation
import GRDB
import Observation

@MainActor
@Observable
final class WeightViewModel {
    private let database: AppDatabase

    var entries: [WeightEntry] = []
    var trend: WeightTrendCalculator.WeightTrend?
    var selectedTimeRange: TimeRange = .threeMonths
    var granularity: Granularity = .daily
    var weightUnit: WeightUnit = Preferences.weightUnit

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

    struct MonthlyAverage: Sendable {
        let month: Date
        let average: Double
        let count: Int
    }

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func loadEntries() {
        do {
            let startDate: String?
            if let days = selectedTimeRange.days {
                let date = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
                startDate = DateFormatters.dateOnly.string(from: date)
            } else {
                startDate = nil
            }
            entries = try database.fetchWeightEntries(from: startDate)
            calculateTrend()
            Log.weightTrend.info("Loaded \(self.entries.count) weight entries")
        } catch {
            Log.weightTrend.error("Failed to load: \(error.localizedDescription)")
        }
    }

    func addWeight(value: Double, date: Date = Date()) {
        let kg = weightUnit.convertToKg(value)
        var entry = WeightEntry(date: DateFormatters.dateOnly.string(from: date), weightKg: kg, source: "manual")
        do {
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

    // MARK: - Weekly Averages (most recent first)

    var weeklyAverages: [WeeklyAverage] {
        let calendar = Calendar.current
        var weeks: [Date: [Double]] = [:]
        for entry in entries {
            guard let date = DateFormatters.dateOnly.date(from: entry.date) else { continue }
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
            weeks[weekStart, default: []].append(entry.weightKg)
        }
        return weeks.map { WeeklyAverage(weekStart: $0.key, average: $0.value.reduce(0, +) / Double($0.value.count), count: $0.value.count) }
            .sorted { $0.weekStart > $1.weekStart }
    }

    var currentMonthAverage: MonthlyAverage? {
        let now = Date()
        let monthEntries = entries.filter { entry in
            guard let date = DateFormatters.dateOnly.date(from: entry.date) else { return false }
            return Calendar.current.isDate(date, equalTo: now, toGranularity: .month)
        }
        guard !monthEntries.isEmpty else { return nil }
        let avg = monthEntries.map(\.weightKg).reduce(0, +) / Double(monthEntries.count)
        return MonthlyAverage(month: Calendar.current.dateInterval(of: .month, for: now)?.start ?? now, average: avg, count: monthEntries.count)
    }

    // MARK: - Entries grouped by month (for log view)

    struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let entries: [WeightEntry]
        let average: Double
    }

    var entriesByMonth: [MonthGroup] {
        let calendar = Calendar.current
        var groups: [String: (title: String, entries: [WeightEntry])] = [:]
        for entry in entries {
            guard let date = DateFormatters.dateOnly.date(from: entry.date) else { continue }
            let key = String(format: "%04d-%02d", calendar.component(.year, from: date), calendar.component(.month, from: date))
            let title = DateFormatters.monthYear.string(from: date)
            groups[key, default: (title, [])].entries.append(entry)
        }
        return groups.map { (key, val) in
            MonthGroup(id: key, title: val.title, entries: val.entries, average: val.entries.map(\.weightKg).reduce(0, +) / Double(val.entries.count))
        }.sorted { $0.id > $1.id }
    }

    private func calculateTrend() {
        let input = entries.map { (date: $0.date, weightKg: $0.weightKg) }
        trend = WeightTrendCalculator.calculateTrend(entries: input)
    }
}
