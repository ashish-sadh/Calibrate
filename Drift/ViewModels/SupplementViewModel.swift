import Foundation
import DriftCore
import Observation

@MainActor
@Observable
final class SupplementViewModel {
    private let database: AppDatabase

    var supplements: [Supplement] = []
    var todayLogs: [Int64: SupplementLog] = [:]
    var selectedDate: Date = Date()
    var consistencyData: [DayConsistency] = []

    struct DayConsistency: Identifiable {
        let id: String // date string
        let date: Date
        let taken: Int
        let total: Int
        var ratio: Double { total > 0 ? Double(taken) / Double(total) : 0 }
    }

    var dateString: String { DateFormatters.dateOnly.string(from: selectedDate) }
    var takenCount: Int { todayLogs.values.filter(\.taken).count }
    var totalCount: Int { supplements.count }

    // Streak: consecutive days with all supplements taken
    var currentStreak: Int {
        var streak = 0
        let cal = Calendar.current
        // Walk backwards from today
        for dayOffset in 0..<60 {
            guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { break }
            let dateStr = DateFormatters.dateOnly.string(from: date)
            if let day = consistencyData.first(where: { $0.id == dateStr }) {
                if day.ratio >= 1.0 { streak += 1 } else { break }
            } else {
                break // no data = streak broken
            }
        }
        return streak
    }

    // Last 30 days average
    var thirtyDayAverage: Double {
        let recent = consistencyData.suffix(30)
        guard !recent.isEmpty else { return 0 }
        return recent.map(\.ratio).reduce(0, +) / Double(recent.count)
    }

    init(database: AppDatabase = .shared) {
        self.database = database
    }

    func loadSupplements() {
        do {
            supplements = try database.fetchActiveSupplements()
            let logs = try database.fetchSupplementLogs(for: dateString)
            todayLogs = Dictionary(uniqueKeysWithValues: logs.compactMap { ($0.supplementId, $0) })
            loadConsistency()
        } catch {
            Log.supplements.error("Failed to load: \(error.localizedDescription)")
        }
    }

    func loadConsistency() {
        do {
            let cal = Calendar.current
            let endDate = Date()
            guard let startDate = cal.date(byAdding: .day, value: -59, to: endDate) else { return }
            let startStr = DateFormatters.dateOnly.string(from: startDate)
            let endStr = DateFormatters.dateOnly.string(from: endDate)

            let allLogs = try database.fetchSupplementLogs(from: startStr, to: endStr)
            let supplementCount = supplements.count

            // Group logs by date
            var byDate: [String: Int] = [:] // date -> count of taken
            for log in allLogs where log.taken {
                byDate[log.date, default: 0] += 1
            }

            // Build 60-day grid
            var days: [DayConsistency] = []
            for dayOffset in (0..<60).reversed() {
                guard let date = cal.date(byAdding: .day, value: -dayOffset, to: endDate) else { continue }
                let dateStr = DateFormatters.dateOnly.string(from: date)
                let taken = byDate[dateStr] ?? 0
                days.append(DayConsistency(id: dateStr, date: date, taken: taken, total: supplementCount))
            }
            consistencyData = days
        } catch {
            Log.supplements.error("Failed to load consistency: \(error.localizedDescription)")
        }
    }

    func toggleTaken(supplementId: Int64) {
        do {
            try database.toggleSupplementTaken(supplementId: supplementId, date: dateString)
            loadSupplements()
        } catch {
            Log.supplements.error("Failed to toggle: \(error.localizedDescription)")
        }
    }

    /// Check if yesterday had supplements taken (for "Same as yesterday" button)
    var yesterdayHadSupplements: Bool {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return false }
        let yesterdayStr = DateFormatters.dateOnly.string(from: yesterday)
        let logs = (try? database.fetchSupplementLogs(for: yesterdayStr)) ?? []
        return logs.contains(where: \.taken)
    }

    /// Copy yesterday's taken supplements to today
    func copyYesterday() {
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) else { return }
        let yesterdayStr = DateFormatters.dateOnly.string(from: yesterday)
        guard let logs = try? database.fetchSupplementLogs(for: yesterdayStr) else { return }
        for log in logs where log.taken {
            if !isTaken(log.supplementId) {
                do {
                    try database.toggleSupplementTaken(supplementId: log.supplementId, date: dateString)
                } catch {
                    Log.supplements.error("Copy yesterday failed: \(error.localizedDescription)")
                }
            }
        }
        loadSupplements()
    }

    func addCustomSupplement(name: String, dosage: String, unit: String, dailyDoses: Int = 1) {
        do {
            var s = Supplement(name: name, dosage: dosage, unit: unit, sortOrder: supplements.count, dailyDoses: dailyDoses)
            try database.saveSupplement(&s)
            loadSupplements()
        } catch {
            Log.supplements.error("Failed to add: \(error.localizedDescription)")
        }
    }

    func isTaken(_ supplementId: Int64) -> Bool {
        todayLogs[supplementId]?.taken ?? false
    }
}
